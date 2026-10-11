/// Quy tắc khoá bài (INV-08): một nơi duy nhất cho ExerciseRow, nút
/// "Bài tiếp theo" và việc mở thẳng route.
///
/// Bài k trong một `CodeFile` mở khi k = 0 hoặc bài k-1 (cùng file) đã passed.
/// Bài nằm ở nhiều file (vd split-chunks) mở nếu mở ở BẤT KỲ file nào chứa nó.
/// Không khoá xuyên file/topic.
library;

import '../data/seed.dart';
import 'models.dart';

Iterable<CodeFile> _allFiles() sync* {
  for (final theme in seedThemes) {
    for (final topic in theme.topics) {
      yield* topic.files;
    }
  }
}

/// Bài [exerciseId] đã mở chưa, biết tập bài đã passed [passed].
/// Id không có trong seed thì coi là khoá.
bool isExerciseUnlocked(String exerciseId, Set<String> passed) {
  for (final file in _allFiles()) {
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
Exercise? nextExerciseAfter(String exerciseId) {
  for (final file in _allFiles()) {
    final index = file.exercises.indexWhere((e) => e.id == exerciseId);
    if (index < 0) continue;
    return index + 1 < file.exercises.length ? file.exercises[index + 1] : null;
  }
  return null;
}
