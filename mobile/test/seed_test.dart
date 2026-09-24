import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/domain/models.dart';
import 'package:smart_coding_study/domain/answer_checker.dart';

void main() {
  group('seedThemes cấu trúc chung', () {
    test('có đúng 3 theme: rag, doc-system, twitter-feed', () {
      final ids = seedThemes.map((t) => t.id).toList();
      expect(ids, ['rag', 'doc-system', 'twitter-feed']);
    });

    test('mọi theme có ít nhất 1 topic, mỗi topic có ít nhất 1 exercise', () {
      for (final theme in seedThemes) {
        expect(theme.topics, isNotEmpty, reason: 'theme ${theme.id}');
        for (final topic in theme.topics) {
          final exerciseCount = topic.files.fold<int>(
            0,
            (sum, f) => sum + f.exercises.length,
          );
          expect(
            exerciseCount,
            greaterThanOrEqualTo(1),
            reason: 'topic ${topic.id}',
          );
        }
      }
    });

    test('theme rag có topic rag-chunking với file chunker.py và preprocessor.py', () {
      final rag = seedThemes.firstWhere((t) => t.id == 'rag');
      final chunking = rag.topics.firstWhere((t) => t.id == 'rag-chunking');
      final fileIds = chunking.files.map((f) => f.id).toList();
      expect(fileIds, contains('rag-chunker-py'));
      expect(fileIds, contains('rag-preprocessor-py'));

      final chunkerPy = chunking.files.firstWhere(
        (f) => f.id == 'rag-chunker-py',
      );
      expect(chunkerPy.name, 'chunker.py');
      final exerciseIds = chunkerPy.exercises.map((e) => e.id).toList();
      expect(exerciseIds, containsAll(['split-chunks', 'overlap-chunks']));

      final splitChunks = chunkerPy.exercises.firstWhere(
        (e) => e.id == 'split-chunks',
      );
      expect(splitChunks.blocks.length, 5);

      final preprocessorPy = chunking.files.firstWhere(
        (f) => f.id == 'rag-preprocessor-py',
      );
      expect(preprocessorPy.name, 'preprocessor.py');
      expect(preprocessorPy.exercises, isNotEmpty);
    });
  });

  group('seedCompletedBlocks', () {
    test('split-chunks đang dở với 2 block đã xong', () {
      expect(seedCompletedBlocks['split-chunks'], 2);
    });

    test('exercise preprocessor (clean-text) đã xong hẳn', () {
      final clean = exerciseById('clean-text');
      expect(seedCompletedBlocks['clean-text'], clean.blocks.length);
    });

    test('exercise còn lại là 0', () {
      expect(seedCompletedBlocks['overlap-chunks'], 0);
      expect(seedCompletedBlocks['save-document'], 0);
      expect(seedCompletedBlocks['like-post'], 0);
    });
  });

  group('exerciseById và locateExercise', () {
    test('exerciseById trả đúng exercise', () {
      final exercise = exerciseById('split-chunks');
      expect(exercise.functionName, 'split_chunks');
    });

    test('exerciseById throw StateError khi không tìm thấy', () {
      expect(() => exerciseById('khong-ton-tai'), throwsStateError);
    });

    test('locateExercise trả đúng theme/topic/file', () {
      final located = locateExercise('split-chunks');
      expect(located.theme.id, 'rag');
      expect(located.topic.id, 'rag-chunking');
      expect(located.file.id, 'rag-chunker-py');
    });

    test('locateExercise throw StateError khi không tìm thấy', () {
      expect(() => locateExercise('khong-ton-tai'), throwsStateError);
    });
  });

  group('ràng buộc dữ liệu block trên toàn bộ seed', () {
    final allBlocks = <Block>[];
    final allExercises = <Exercise>[];
    final allIds = <String>[];
    final sharedExercises = Set<Exercise>.identity();

    setUpAll(() {
      for (final theme in seedThemes) {
        allIds.add(theme.id);
        for (final topic in theme.topics) {
          allIds.add(topic.id);
          for (final file in topic.files) {
            allIds.add(file.id);
            for (final exercise in file.exercises) {
              // Exercise dùng chung giữa nhiều file (cross-cut) là cùng một
              // instance — chỉ đếm id của nó một lần.
              if (!sharedExercises.add(exercise)) continue;
              allIds.add(exercise.id);
              allExercises.add(exercise);
              for (final block in exercise.blocks) {
                allIds.add(block.id);
                allBlocks.add(block);
              }
            }
          }
        }
      }
    });

    test('mọi ID duy nhất toàn cục', () {
      final seen = <String>{};
      for (final id in allIds) {
        expect(seen.contains(id), isFalse, reason: 'ID trùng: $id');
        seen.add(id);
      }
    });

    test('mọi block có tối đa 2 dòng cho mỗi đáp án', () {
      for (final block in allBlocks) {
        for (final answer in block.acceptedAnswers) {
          final lineCount = answer.split('\n').length;
          expect(
            lineCount,
            lessThanOrEqualTo(2),
            reason: 'block ${block.id}',
          );
        }
      }
    });

    test('tổng số dòng đáp án đầu tiên của mỗi exercise ≤ 10', () {
      for (final exercise in allExercises) {
        final totalLines = exercise.blocks.fold<int>(
          0,
          (sum, b) => sum + b.acceptedAnswers.first.split('\n').length,
        );
        expect(
          totalLines,
          lessThanOrEqualTo(10),
          reason: 'exercise ${exercise.id}',
        );
      }
    });

    test('mỗi block có đúng 3 hint', () {
      for (final block in allBlocks) {
        expect(block.hints.length, 3, reason: 'block ${block.id}');
      }
    });

    test('mỗi block có vocab không rỗng', () {
      for (final block in allBlocks) {
        expect(block.vocab, isNotEmpty, reason: 'block ${block.id}');
      }
    });

    test('block index 0 của mỗi exercise là dòng def', () {
      for (final exercise in allExercises) {
        final firstBlock = exercise.blocks.first;
        final firstAnswer = firstBlock.acceptedAnswers.first;
        expect(
          firstAnswer.trimLeft().startsWith('def '),
          isTrue,
          reason: 'exercise ${exercise.id} block 0: $firstAnswer',
        );
      }
    });

    test('không có 2 block trong cùng exercise có acceptedAnswers[0] trùng sau normalizeCode', () {
      for (final exercise in allExercises) {
        final normalizedAnswers = <String, String>{};
        for (final block in exercise.blocks) {
          final normalized = normalizeCode(block.acceptedAnswers.first);
          if (normalizedAnswers.containsKey(normalized)) {
            fail(
              'exercise ${exercise.id}: block ${block.id} và '
              '${normalizedAnswers[normalized]} có acceptedAnswers[0] trùng sau normalize',
            );
          }
          normalizedAnswers[normalized] = block.id;
        }
      }
    });

    test('không block nào đứng sau block có đáp án bắt đầu bằng return mà indentLevel ≤ return block', () {
      for (final exercise in allExercises) {
        for (int i = 0; i < exercise.blocks.length; i++) {
          final block = exercise.blocks[i];
          final answer = block.acceptedAnswers.first.trim();
          if (answer.startsWith('return')) {
            // Kiểm các block sau nó
            for (int j = i + 1; j < exercise.blocks.length; j++) {
              final nextBlock = exercise.blocks[j];
              expect(
                nextBlock.indentLevel > block.indentLevel,
                isTrue,
                reason:
                    'exercise ${exercise.id}: block ${nextBlock.id} (indentLevel ${nextBlock.indentLevel}) '
                    'đứng sau block ${block.id} (indentLevel ${block.indentLevel}) có đáp án bắt đầu bằng return',
              );
            }
          }
        }
      }
    });
  });

  group('split-chunks exercise validation', () {
    test('split-chunks b2 chấp nhận: for i in range(0, len(text), size):', () {
      final exercise = exerciseById('split-chunks');
      final b2 = exercise.blocks.firstWhere((b) => b.id == 'split-chunks-b2');

      final testCode = 'for i in range(0, len(text), size):';
      final normalizedTest = normalizeCode(testCode);
      final normalizedAccepted = normalizeCode(b2.acceptedAnswers.first);

      expect(
        normalizedTest,
        normalizedAccepted,
        reason: 'split-chunks-b2 phải chấp nhận: $testCode',
      );
    });

    test('split-chunks có đúng 5 block (b0..b4)', () {
      final exercise = exerciseById('split-chunks');
      expect(exercise.blocks.length, 5);
      final ids = exercise.blocks.map((b) => b.id).toList();
      expect(
        ids,
        [
          'split-chunks-b0',
          'split-chunks-b1',
          'split-chunks-b2',
          'split-chunks-b3',
          'split-chunks-b4',
        ],
      );
    });

    test('split-chunks b3 (append) có indentLevel 2', () {
      final exercise = exerciseById('split-chunks');
      final b3 = exercise.blocks.firstWhere((b) => b.id == 'split-chunks-b3');
      expect(b3.indentLevel, 2);
    });

    test('split-chunks b2 (loop) có indentLevel 1', () {
      final exercise = exerciseById('split-chunks');
      final b2 = exercise.blocks.firstWhere((b) => b.id == 'split-chunks-b2');
      expect(b2.indentLevel, 1);
    });
  });
}
