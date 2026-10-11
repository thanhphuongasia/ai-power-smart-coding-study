import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/domain/progression.dart';

void main() {
  group('isExerciseUnlocked', () {
    test('overlap-chunks khoá khi split-chunks chưa pass, mở khi đã pass', () {
      expect(isExerciseUnlocked('overlap-chunks', {}), isFalse);
      expect(isExerciseUnlocked('overlap-chunks', {'clean-text'}), isFalse);
      expect(isExerciseUnlocked('overlap-chunks', {'split-chunks'}), isTrue);
    });

    test('split-chunks luôn mở (bài đầu file doc-chunker-py)', () {
      expect(isExerciseUnlocked('split-chunks', {}), isTrue);
    });

    test('bài đầu mỗi file khác luôn mở', () {
      expect(isExerciseUnlocked('clean-text', {}), isTrue);
      expect(isExerciseUnlocked('save-document', {}), isTrue);
      expect(isExerciseUnlocked('like-post', {}), isTrue);
    });

    test('id không có trong seed → khoá', () {
      expect(isExerciseUnlocked('khong-co', {}), isFalse);
    });

    test('seed: mọi bài không đầu file đều khoá khi chưa pass gì', () {
      for (final theme in seedThemes) {
        for (final topic in theme.topics) {
          for (final file in topic.files) {
            for (var i = 1; i < file.exercises.length; i++) {
              final id = file.exercises[i].id;
              // Bài dùng chung có thể mở ở file khác — bỏ qua nếu đầu file nào đó.
              final firstElsewhere = seedThemes.any(
                (t) => t.topics.any(
                  (tp) => tp.files.any((f) => f.exercises.first.id == id),
                ),
              );
              if (firstElsewhere) continue;
              expect(isExerciseUnlocked(id, {}), isFalse, reason: id);
            }
          }
        }
      }
    });
  });

  group('nextExerciseAfter', () {
    test('next của split-chunks = overlap-chunks', () {
      expect(nextExerciseAfter('split-chunks')?.id, 'overlap-chunks');
    });

    test('bài cuối file → null', () {
      expect(nextExerciseAfter('overlap-chunks'), isNull);
    });

    test('id không tồn tại → null', () {
      expect(nextExerciseAfter('khong-co'), isNull);
    });
  });
}
