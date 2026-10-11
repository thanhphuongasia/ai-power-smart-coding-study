/// Trạng thái phiên làm bài: tiến trình từng block (đã xong/đang làm/khoá),
/// đồng hồ đếm giờ, phát hiện ngồi im (idle) và tự thoát khi hết giờ.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/content_providers.dart';
import '../../data/demo_seed.dart';
import '../../domain/content.dart';
import '../../domain/models.dart';
import '../stats/activity.dart';
import 'session_providers.dart';

/// Trạng thái đồng hồ của phiên làm bài.
enum SessionPhase { active, idle, timedOut }

/// Ngồi im bao lâu thì hệ thống hỏi "vẫn đang làm chứ?".
const idleThreshold = Duration(minutes: 2);

/// Đếm ngược khi đang ở trạng thái idle — hết thì tự lưu và thoát.
const idleCountdown = Duration(seconds: 60);

/// Thời lượng tối đa một phiên làm bài trước khi tự thoát.
const maxSessionDuration = Duration(minutes: 15);

/// Tiến trình của một exercise. "Đã xong" chỉ có MỘT nguồn: [passed] (chỉ đặt
/// khi chạy đúng toàn bộ unit test). Draft/hint/lời giải key theo NHÃN ô
/// (`Block.label`: A, B, C...).
class ExerciseProgress {
  const ExerciseProgress({
    this.passed = false,
    this.totalBlocks = 0,
    this.drafts = const {},
    this.hintsUsed = const {},
    this.solutionViewed = const {},
  });

  final bool passed;

  /// Số ô của bài, để suy ra [completedBlocks] (không phải trạng thái riêng).
  final int totalBlocks;
  final Map<String, String> drafts;
  final Map<String, int> hintsUsed;
  final Set<String> solutionViewed;

  /// Suy ra từ [passed]: xong thì mọi ô xong, chưa thì 0.
  int get completedBlocks => passed ? totalBlocks : 0;

  /// "Đang làm dở" (INV-09): chưa passed và có ít nhất một draft không rỗng.
  bool get inProgress =>
      !passed && drafts.values.any((code) => code.trim().isNotEmpty);

  ExerciseProgress copyWith({
    bool? passed,
    Map<String, String>? drafts,
    Map<String, int>? hintsUsed,
    Set<String>? solutionViewed,
  }) {
    return ExerciseProgress(
      passed: passed ?? this.passed,
      totalBlocks: totalBlocks,
      drafts: drafts ?? this.drafts,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      solutionViewed: solutionViewed ?? this.solutionViewed,
    );
  }
}

/// Tiến trình của mọi exercise, khởi tạo từ [seedPassedExercises] +
/// [seedDrafts]. KHÔNG autoDispose — phải sống qua việc [SessionController]
/// (autoDispose) bị huỷ khi người học rời màn hình.
class ProgressController extends Notifier<Map<String, ExerciseProgress>> {
  @override
  Map<String, ExerciseProgress> build() {
    // ref.read, KHÔNG watch (INV-10): nội dung đổi không được dựng lại
    // controller và xoá tiến độ.
    final content = ref.read(contentIndexProvider);
    final ids = {...seedPassedExercises, ...seedDrafts.keys};
    return {
      for (final id in ids)
        // Id demo không có trong nội dung server → bỏ qua (không crash).
        if (_blockCount(content, id) case final total?)
          id: ExerciseProgress(
            passed: seedPassedExercises.contains(id),
            totalBlocks: total,
            drafts: Map.of(seedDrafts[id] ?? const {}),
          ),
    };
  }

  static int? _blockCount(Content content, String id) {
    try {
      return content.exerciseById(id).blocks.length;
    } on StateError {
      return null;
    }
  }

  ExerciseProgress _progressOf(String exerciseId) {
    return state[exerciseId] ??
        ExerciseProgress(
          totalBlocks: ref
              .read(contentIndexProvider)
              .exerciseById(exerciseId)
              .blocks
              .length,
        );
  }

  /// Đánh dấu cả bài đã pass (backend trả `passed`). Idempotent: đã passed thì
  /// không ghi hoạt động lần nữa.
  void markPassed(String exerciseId) {
    final current = _progressOf(exerciseId);
    if (current.passed) return;
    ref.read(activityProvider.notifier).record();
    state = {...state, exerciseId: current.copyWith(passed: true)};
  }

  /// Lưu draft code đang gõ dở cho ô [label] của [exerciseId].
  void saveDraft(String exerciseId, String label, String code) {
    final current = _progressOf(exerciseId);
    state = {
      ...state,
      exerciseId: current.copyWith(drafts: {...current.drafts, label: code}),
    };
  }

  /// Tăng số hint đã dùng cho ô [label], tối đa 3. Trả về số hint sau khi
  /// tăng (không tăng quá 3 dù gọi thêm bao nhiêu lần).
  int useHint(String exerciseId, String label) {
    final current = _progressOf(exerciseId);
    final used = current.hintsUsed[label] ?? 0;
    final next = used >= 3 ? used : used + 1;
    state = {
      ...state,
      exerciseId: current.copyWith(
        hintsUsed: {...current.hintsUsed, label: next},
      ),
    };
    return next;
  }

  /// Ghi nhận người học đã xem lời giải ô [label] (INV-07: ô này không sạch).
  void viewSolution(String exerciseId, String label) {
    final current = _progressOf(exerciseId);
    if (current.solutionViewed.contains(label)) return;
    state = {
      ...state,
      exerciseId: current.copyWith(
        solutionViewed: {...current.solutionViewed, label},
      ),
    };
  }
}

/// Trạng thái đồng hồ của phiên làm bài hiện tại.
class SessionState {
  const SessionState({
    required this.elapsed,
    required this.phase,
    required this.idleCountdownSeconds,
  });

  final Duration elapsed;
  final SessionPhase phase;
  final int idleCountdownSeconds;
}

/// Quản lý đồng hồ đếm giờ + idle + timeout cho MỘT exercise (family theo
/// `exerciseId`). Đọc thời gian qua [clockProvider] để test được bằng
/// fakeAsync, không phụ thuộc `DateTime.now()` thật.
class SessionController extends Notifier<SessionState> {
  SessionController(this.exerciseId);

  final String exerciseId;

  Timer? _timer;
  DateTime? _sessionStart;
  DateTime? _lastActivity;
  DateTime? _idleEnteredAt;

  DateTime Function() get _clock => ref.read(clockProvider);

  @override
  SessionState build() {
    ref.onDispose(_cancelTimer);
    return const SessionState(
      elapsed: Duration.zero,
      phase: SessionPhase.active,
      idleCountdownSeconds: 0,
    );
  }

  /// Bắt đầu phiên: reset mốc thời gian, chạy `Timer.periodic` 1s.
  ///
  /// Idempotent: nếu timer đang chạy (_timer != null && _timer!.isActive)
  /// và chưa timedOut, chỉ gọi activity() để đánh dấu có hoạt động (thoát idle
  /// nếu đang), KHÔNG reset elapsed về 0. Chỉ khi chưa có timer hoặc đã
  /// timedOut mới khởi động lại toàn bộ phiên từ đầu.
  ///
  /// Điều này cho phép gọi start() lặp lại từ initState của màn block mà
  /// không làm đồng hồ nhảy về 00:00 mỗi lần.
  void start() {
    // Nếu timer đang chạy và chưa timedOut → chỉ đánh dấu activity
    if (_timer != null &&
        _timer!.isActive &&
        state.phase != SessionPhase.timedOut) {
      activity();
      return;
    }

    // Khởi động lại toàn bộ phiên từ đầu
    final now = _clock();
    _sessionStart = now;
    _lastActivity = now;
    _idleEnteredAt = null;
    state = const SessionState(
      elapsed: Duration.zero,
      phase: SessionPhase.active,
      idleCountdownSeconds: 0,
    );
    _cancelTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final sessionStart = _sessionStart;
    final lastActivity = _lastActivity;
    if (sessionStart == null || lastActivity == null) return;
    if (state.phase == SessionPhase.timedOut) return;

    final now = _clock();
    final elapsed = now.difference(sessionStart);

    if (elapsed >= maxSessionDuration) {
      state = SessionState(
        elapsed: elapsed,
        phase: SessionPhase.timedOut,
        idleCountdownSeconds: 0,
      );
      _cancelTimer();
      return;
    }

    final sinceActivity = now.difference(lastActivity);
    if (sinceActivity >= idleThreshold) {
      _idleEnteredAt ??= lastActivity.add(idleThreshold);
      final idleFor = now.difference(_idleEnteredAt!);
      final remaining = idleCountdown.inSeconds - idleFor.inSeconds;
      if (remaining <= 0) {
        state = SessionState(
          elapsed: elapsed,
          phase: SessionPhase.timedOut,
          idleCountdownSeconds: 0,
        );
        _cancelTimer();
        return;
      }
      state = SessionState(
        elapsed: elapsed,
        phase: SessionPhase.idle,
        idleCountdownSeconds: remaining,
      );
      return;
    }

    state = SessionState(
      elapsed: elapsed,
      phase: SessionPhase.active,
      idleCountdownSeconds: 0,
    );
  }

  /// Người học vừa tương tác (gõ code, chạm màn hình...) — về active, reset
  /// mốc đếm idle.
  void activity() {
    if (state.phase == SessionPhase.timedOut) return;
    _lastActivity = _clock();
    _idleEnteredAt = null;
    state = SessionState(
      elapsed: state.elapsed,
      phase: SessionPhase.active,
      idleCountdownSeconds: 0,
    );
  }

  /// Bấm "vẫn đang làm chứ?" lúc đang idle — cùng hành vi với [activity].
  void resume() => activity();

  /// Dừng đếm giờ (huỷ timer) mà không đổi trạng thái đã có.
  void stop() => _cancelTimer();

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

final RegExp _assignmentPattern = RegExp(r'^([A-Za-z_]\w*)\s*=(?!=)');
final RegExp _selfAttrPattern = RegExp(r'\bself\.([A-Za-z_]\w*)\s*=(?!=)');
final RegExp _forLoopPattern = RegExp(r'^for\s+([A-Za-z_]\w*)\s+in\b');

/// Định danh đã biết tại block [blockIndex]: tên hàm, tham số, tên biến GÁN /
/// biến LẶP trong phần code khoá của `template` (nhìn thấy ở mọi ô), cộng
/// tên GÁN/LẶP trong `acceptedAnswers[0]` của các block TRƯỚC [blockIndex].
List<String> knownIdentifiersFor(Exercise exercise, int blockIndex) {
  final identifiers = <String>{exercise.functionName, ...exercise.params};

  void collect(String code) {
    for (final rawLine in code.split('\n')) {
      final line = rawLine.trim();
      final forMatch = _forLoopPattern.firstMatch(line);
      if (forMatch != null) {
        identifiers.add(forMatch.group(1)!);
        continue;
      }
      final assignMatch = _assignmentPattern.firstMatch(line);
      if (assignMatch != null) {
        identifiers.add(assignMatch.group(1)!);
      }
    }
  }

  collect(exercise.template);

  final className = exercise.className;
  if (className != null) {
    identifiers
      ..add('self')
      ..add(className);
    for (final m in _selfAttrPattern.allMatches(exercise.template)) {
      identifiers.add(m.group(1)!);
    }
  }

  final upperBound = blockIndex < exercise.blocks.length
      ? blockIndex
      : exercise.blocks.length;
  for (var i = 0; i < upperBound; i++) {
    final block = exercise.blocks[i];
    if (block.acceptedAnswers.isEmpty) continue;
    collect(block.acceptedAnswers.first);
  }
  return identifiers.toList();
}
