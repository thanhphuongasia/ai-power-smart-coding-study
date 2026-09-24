/// Providers cho state phiên làm bài — xem `session_controller.dart` cho
/// logic. Tách riêng theo INTERFACES.md để widget chỉ cần import file này.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed.dart';
import '../../domain/models.dart';
import 'session_controller.dart';

/// Nguồn thời gian hiện tại — override bằng clock giả (fakeAsync) trong
/// test, mặc định dùng `DateTime.now`.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Tiến trình của mọi exercise. KHÔNG autoDispose — phải sống qua việc
/// [sessionProvider] (autoDispose) bị huỷ khi người học rời màn hình.
final progressProvider =
    NotifierProvider<ProgressController, Map<String, ExerciseProgress>>(
      ProgressController.new,
    );

/// Phiên làm bài hiện tại theo `exerciseId` — autoDispose khi không còn ai
/// lắng nghe (rời màn hình).
final sessionProvider = NotifierProvider.autoDispose
    .family<SessionController, SessionState, String>(SessionController.new);

/// Exercise đầu tiên đang làm dở (`0 < completed < tổng số block`), dùng để
/// gợi ý "tiếp tục" ở màn Home.
final inProgressExerciseProvider = Provider<Exercise?>((ref) {
  final progress = ref.watch(progressProvider);
  for (final theme in seedThemes) {
    for (final topic in theme.topics) {
      for (final file in topic.files) {
        for (final exercise in file.exercises) {
          final completed = progress[exercise.id]?.completedBlocks ?? 0;
          if (completed > 0 && completed < exercise.blocks.length) {
            return exercise;
          }
        }
      }
    }
  }
  return null;
});
