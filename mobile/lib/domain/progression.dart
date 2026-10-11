/// Quy tắc khoá bài (INV-08): một nơi duy nhất cho ExerciseRow, nút
/// "Bài tiếp theo" và việc mở thẳng route.
///
/// Bài k trong một `CodeFile` mở khi k = 0 hoặc bài k-1 (cùng file) đã passed.
/// Bài nằm ở nhiều file (vd split-chunks) mở nếu mở ở BẤT KỲ file nào chứa nó.
/// Không khoá xuyên file/topic.
library;

import 'content.dart';
import 'models.dart';

Iterable<CodeFile> _allFiles(Content content) sync* {
  for (final theme in content.themes) {
    for (final topic in theme.topics) {
      yield* topic.files;
    }
  }
}

/// Bài [exerciseId] đã mở chưa, biết tập bài đã passed [passed].
/// Bài đã passed luôn mở. Id không có trong [content] (và chưa passed) thì khoá.
bool isExerciseUnlocked(
  Content content,
  String exerciseId,
  Set<String> passed,
) {
  // Bài đã pass luôn mở, kể cả khi bài trước chưa pass (khớp ExerciseRow).
  if (passed.contains(exerciseId)) return true;
  for (final file in _allFiles(content)) {
    final index = file.exercises.indexWhere((e) => e.id == exerciseId);
    if (index < 0) continue;
    if (index == 0 || passed.contains(file.exercises[index - 1].id)) {
      return true;
    }
  }
  return false;
}

/// Bài kế tiếp trong cùng `CodeFile` ĐẦU TIÊN chứa [exerciseId]; null nếu là
/// bài cuối file (hoặc không tìm thấy).
Exercise? nextExerciseAfter(Content content, String exerciseId) {
  for (final file in _allFiles(content)) {
    final index = file.exercises.indexWhere((e) => e.id == exerciseId);
    if (index < 0) continue;
    return index + 1 < file.exercises.length ? file.exercises[index + 1] : null;
  }
  return null;
}
