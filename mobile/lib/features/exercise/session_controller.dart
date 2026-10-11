/// Trạng thái phiên làm bài: tiến trình từng block (đã xong/đang làm/khoá),
/// đồng hồ đếm giờ, phát hiện ngồi im (idle) và tự thoát khi hết giờ.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/content_providers.dart';
import '../../data/progress_api.dart';
import '../../domain/content.dart';
import '../../domain/models.dart';
import '../review/review_controller.dart'
    show reviewScheduleProvider, syncLearningState;
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

/// Delay gom các lần gõ trước khi đẩy draft lên server.
const draftSyncDelay = Duration(milliseconds: 800);

/// Tiến trình của mọi exercise, khởi tạo từ snapshot server
/// ([loadedProgressProvider]). KHÔNG autoDispose — phải sống qua việc
/// [SessionController] (autoDispose) bị huỷ khi người học rời màn hình.
///
/// Đẩy lên server: draft gom 800 ms/exercise; hint và xem lời giải đẩy ngay;
/// `markPassed` chỉ đổi cục bộ (server đã tự ghi lúc `/run`). Lỗi mạng không
/// ném — state cục bộ giữ nguyên, lần đổi sau đẩy lại toàn bộ exercise đó.
/// Draft còn đang chờ lúc controller bị huỷ (đổi/đăng xuất phiên) thì bỏ.
class ProgressController extends Notifier<Map<String, ExerciseProgress>> {
  final Map<String, Timer> _draftTimers = {};

  @override
  Map<String, ExerciseProgress> build() {
    ref.onDispose(() {
      for (final t in _draftTimers.values) {
        t.cancel();
      }
      _draftTimers.clear();
    });
    // ref.read, KHÔNG watch (INV-10): nội dung đổi không được dựng lại
    // controller và xoá tiến độ.
    final content = ref.read(contentIndexProvider);
    final snapshot = ref.watch(loadedProgressProvider);
    return {
      for (final e in (snapshot?.exercises ?? const {}).entries)
        // Id server có mà nội dung không có → bỏ qua (không crash). Nhãn ô không
        // còn trong bài (admin đổi/xoá ô) cũng bỏ: giữ lại thì mọi PUT của bài
        // này bị server từ chối (422 nhãn lạ) và tiến độ ngừng đồng bộ.
        if (_labels(content, e.key) case final labels?)
          e.key: ExerciseProgress(
            passed: e.value.passed,
            totalBlocks: labels.length,
            drafts: {
              for (final d in e.value.drafts.entries)
                if (labels.contains(d.key)) d.key: d.value,
            },
            hintsUsed: {
              for (final h in e.value.hintsUsed.entries)
                if (labels.contains(h.key)) h.key: h.value,
            },
            solutionViewed: e.value.solutionViewed
                .where(labels.contains)
                .toSet(),
          ),
    };
  }

  /// Đẩy ngay tiến độ hiện tại của [exerciseId]; không bao giờ ném.
  void _push(String exerciseId) {
    if (!ref.mounted || !canPushProgress(ref)) return;
    final progress = state[exerciseId];
    if (progress == null) return;
    // Draft quá lớn / có NUL: server sẽ từ chối → giữ cục bộ, không gửi.
    if (!draftsPushable(progress.drafts)) return;
    final api = ref.read(progressApiProvider);
    unawaited(_save(api, exerciseId, progress));
  }

  static Future<void> _save(
    ProgressApi api,
    String exerciseId,
    ExerciseProgress progress,
  ) async {
    try {
      await api.saveExercise(exerciseId, progress);
    } catch (_) {}
  }

  static Set<String>? _labels(Content content, String id) {
    try {
      return {for (final b in content.exerciseById(id).blocks) b.label};
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
    syncLearningState(
      ref,
      ref.read(reviewScheduleProvider),
      ref.read(activityProvider),
    );
  }

  /// Lưu draft code đang gõ dở cho ô [label] của [exerciseId].
  void saveDraft(String exerciseId, String label, String code) {
    final current = _progressOf(exerciseId);
    state = {
      ...state,
      exerciseId: current.copyWith(drafts: {...current.drafts, label: code}),
    };
    if (!canPushProgress(ref)) return;
    _draftTimers[exerciseId]?.cancel();
    _draftTimers[exerciseId] = Timer(draftSyncDelay, () {
      _draftTimers.remove(exerciseId);
      _push(exerciseId);
    });
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
    if (next != used) _push(exerciseId);
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
    _push(exerciseId);
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
