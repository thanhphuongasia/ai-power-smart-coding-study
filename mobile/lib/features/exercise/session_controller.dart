/// Trạng thái phiên làm bài: tiến trình từng block (đã xong/đang làm/khoá),
/// đồng hồ đếm giờ, phát hiện ngồi im (idle) và tự thoát khi hết giờ.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed.dart';
import '../../domain/answer_checker.dart';
import '../../domain/models.dart';
import 'session_providers.dart';

/// Trạng thái một block so với tiến trình hiện tại của người học.
enum BlockStatus { done, active, locked }

/// Trạng thái đồng hồ của phiên làm bài.
enum SessionPhase { active, idle, timedOut }

/// Ngồi im bao lâu thì hệ thống hỏi "vẫn đang làm chứ?".
const idleThreshold = Duration(minutes: 2);

/// Đếm ngược khi đang ở trạng thái idle — hết thì tự lưu và thoát.
const idleCountdown = Duration(seconds: 60);

/// Thời lượng tối đa một phiên làm bài trước khi tự thoát.
const maxSessionDuration = Duration(minutes: 15);

/// Tiến trình của một exercise: số block đã xong (`completedBlocks`), draft
/// code đang gõ dở theo blockId, và số hint đã dùng theo blockId.
class ExerciseProgress {
  const ExerciseProgress({
    required this.completedBlocks,
    required this.drafts,
    required this.hintsUsed,
  });

  final int completedBlocks;
  final Map<String, String> drafts;
  final Map<String, int> hintsUsed;

  ExerciseProgress copyWith({
    int? completedBlocks,
    Map<String, String>? drafts,
    Map<String, int>? hintsUsed,
  }) {
    return ExerciseProgress(
      completedBlocks: completedBlocks ?? this.completedBlocks,
      drafts: drafts ?? this.drafts,
      hintsUsed: hintsUsed ?? this.hintsUsed,
    );
  }
}

/// Tiến trình của mọi exercise, khởi tạo từ [seedCompletedBlocks]. KHÔNG
/// autoDispose — phải sống qua việc [SessionController] (autoDispose) bị
/// huỷ khi người học rời màn hình.
class ProgressController extends Notifier<Map<String, ExerciseProgress>> {
  @override
  Map<String, ExerciseProgress> build() {
    return {
      for (final entry in seedCompletedBlocks.entries)
        entry.key: ExerciseProgress(
          completedBlocks: entry.value,
          drafts: const {},
          hintsUsed: const {},
        ),
    };
  }

  ExerciseProgress _progressOf(String exerciseId) {
    return state[exerciseId] ??
        const ExerciseProgress(
          completedBlocks: 0,
          drafts: {},
          hintsUsed: {},
        );
  }

  /// Tăng `completedBlocks` CHỈ khi [blockIndex] đúng bằng block đang active
  /// (tức bằng `completedBlocks` hiện tại) — chống báo pass sai thứ tự.
  void markBlockPassed(String exerciseId, int blockIndex) {
    final current = _progressOf(exerciseId);
    if (blockIndex != current.completedBlocks) return;
    state = {
      ...state,
      exerciseId: current.copyWith(
        completedBlocks: current.completedBlocks + 1,
      ),
    };
  }

  /// Lưu draft code đang gõ dở cho block [blockId] của [exerciseId].
  void saveDraft(String exerciseId, String blockId, String code) {
    final current = _progressOf(exerciseId);
    state = {
      ...state,
      exerciseId: current.copyWith(
        drafts: {...current.drafts, blockId: code},
      ),
    };
  }

  /// Tăng số hint đã dùng cho [blockId], tối đa 3. Trả về số hint sau khi
  /// tăng (không tăng quá 3 dù gọi thêm bao nhiêu lần).
  int useHint(String exerciseId, String blockId) {
    final current = _progressOf(exerciseId);
    final used = current.hintsUsed[blockId] ?? 0;
    final next = used >= 3 ? used : used + 1;
    state = {
      ...state,
      exerciseId: current.copyWith(
        hintsUsed: {...current.hintsUsed, blockId: next},
      ),
    };
    return next;
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

  /// Bắt đầu (hoặc khởi động lại) phiên: reset mốc thời gian, chạy
  /// `Timer.periodic` 1s.
  void start() {
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

  /// Chấm code cho block [blockIndex]. Pass thì cập nhật tiến trình qua
  /// [ProgressController.markBlockPassed].
  RunResult run(int blockIndex, String code) {
    final exercise = exerciseById(exerciseId);
    final block = exercise.blocks[blockIndex];
    final result = runBlock(code, block);
    if (result.passed) {
      ref
          .read(progressProvider.notifier)
          .markBlockPassed(exerciseId, blockIndex);
    }
    return result;
  }
}

/// Trạng thái block [index] so với tiến trình [p]: done / active / locked.
BlockStatus blockStatusOf(ExerciseProgress p, int index) {
  if (index < p.completedBlocks) return BlockStatus.done;
  if (index == p.completedBlocks) return BlockStatus.active;
  return BlockStatus.locked;
}

final RegExp _assignmentPattern = RegExp(r'^([A-Za-z_]\w*)\s*=(?!=)');
final RegExp _forLoopPattern = RegExp(r'^for\s+([A-Za-z_]\w*)\s+in\b');

/// Định danh đã biết tại block [blockIndex]: tham số của hàm cộng tên biến
/// được GÁN (`x = ...`) hoặc biến LẶP (`for x in ...`) xuất hiện trong
/// `acceptedAnswers[0]` của các block TRƯỚC [blockIndex].
List<String> knownIdentifiersFor(Exercise exercise, int blockIndex) {
  final identifiers = <String>{...exercise.params};

  final upperBound = blockIndex < exercise.blocks.length
      ? blockIndex
      : exercise.blocks.length;
  for (var i = 0; i < upperBound; i++) {
    final block = exercise.blocks[i];
    if (block.acceptedAnswers.isEmpty) continue;
    final answer = block.acceptedAnswers.first;
    for (final rawLine in answer.split('\n')) {
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
  return identifiers.toList();
}
