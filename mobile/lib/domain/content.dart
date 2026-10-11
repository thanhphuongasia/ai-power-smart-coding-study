/// Nội dung học hiện hành: cây theme → topic → file → exercise + các hàm
/// tra cứu. Thay cho hàm toàn cục trong seed; parse/xuất JSON theo hợp đồng
/// `GET /content`.
library;

import 'models.dart';

class Content {
  const Content({required this.version, required this.themes});

  final String version;
  final List<StudyTheme> themes;

  /// Bài dùng chung giữa nhiều file sau khi parse là CÙNG một instance.
  factory Content.fromJson(Map<String, dynamic> json) {
    const w = 'content';
    final rawExercises = jsonField<Map<String, dynamic>>(json, 'exercises', w);
    final exercises = <String, Exercise>{};
    for (final entry in rawExercises.entries) {
      final raw = entry.value;
      if (raw is! Map<String, dynamic>) {
        throw FormatException('exercises["${entry.key}"] không phải object');
      }
      final exercise = Exercise.fromJson(raw);
      if (exercise.id != entry.key) {
        throw FormatException(
          'exercises["${entry.key}"] có id khác key: "${exercise.id}"',
        );
      }
      exercises[entry.key] = exercise;
    }
    return Content(
      version: jsonField<String>(json, 'version', w),
      themes: [
        for (final t in jsonObjects(json, 'themes', w))
          StudyTheme.fromJson(t, exercises),
      ],
    );
  }

  /// Đúng shape `/content` (không có `judge`).
  Map<String, dynamic> toJson() => {
    'version': version,
    'themes': [for (final t in themes) t.toJson()],
    'exercises': {for (final e in uniqueExercises()) e.id: e.toJson()},
  };

  /// Throw [StateError] nếu không có.
  Exercise exerciseById(String id) {
    for (final theme in themes) {
      for (final file in theme.allFiles) {
        for (final exercise in file.exercises) {
          if (exercise.id == id) return exercise;
        }
      }
    }
    throw StateError('Không tìm thấy exercise với id: $id');
  }

  /// Tìm theme/topic/file chứa exercise [exerciseId]. `topic` là module chứa
  /// trực tiếp file. Throw [StateError].
  ({StudyTheme theme, Topic topic, CodeFile file}) locateExercise(
    String exerciseId,
  ) {
    for (final theme in themes) {
      for (final topic in theme.allTopics) {
        for (final file in topic.files) {
          for (final exercise in file.exercises) {
            if (exercise.id == exerciseId) {
              return (theme: theme, topic: topic, file: file);
            }
          }
        }
      }
    }
    throw StateError('Không tìm thấy exercise với id: $exerciseId');
  }

  /// Tìm topic/module ở mọi độ sâu; null nếu không có.
  ({StudyTheme theme, Topic topic})? locateTopic(String topicId) {
    for (final theme in themes) {
      for (final topic in theme.allTopics) {
        if (topic.id == topicId) return (theme: theme, topic: topic);
      }
    }
    return null;
  }

  /// Chuỗi từ topic cấp trên cùng xuống [topicId] (gồm cả hai đầu); rỗng nếu
  /// không tìm thấy.
  List<Topic> modulePath(String topicId) {
    List<Topic>? walk(Topic t, List<Topic> path) {
      final here = [...path, t];
      if (t.id == topicId) return here;
      for (final m in t.modules) {
        final found = walk(m, here);
        if (found != null) return found;
      }
      return null;
    }

    for (final theme in themes) {
      for (final top in theme.topics) {
        final found = walk(top, const []);
        if (found != null) return found;
      }
    }
    return const [];
  }

  /// Mỗi id một lần, theo thứ tự theme → topic (preorder) → file.
  List<Exercise> uniqueExercises() {
    final seen = <String>{};
    return [
      for (final theme in themes)
        for (final file in theme.allFiles)
          for (final exercise in file.exercises)
            if (seen.add(exercise.id)) exercise,
    ];
  }

  /// Mọi nơi dùng file tên [fileName], theo thứ tự theme.
  List<({StudyTheme theme, Topic topic, CodeFile file})> locateFilesNamed(
    String fileName,
  ) {
    return [
      for (final theme in themes)
        for (final topic in theme.allTopics)
          for (final file in topic.files)
            if (file.name == fileName) (theme: theme, topic: topic, file: file),
    ];
  }
}
