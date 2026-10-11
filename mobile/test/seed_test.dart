import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/domain/answer_checker.dart';
import 'package:smart_coding_study/domain/merge.dart';
import 'package:smart_coding_study/domain/models.dart';

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
      expect(splitChunks.blocks.length, 3);

      final preprocessorPy = chunking.files.firstWhere(
        (f) => f.id == 'rag-preprocessor-py',
      );
      expect(preprocessorPy.name, 'preprocessor.py');
      expect(preprocessorPy.exercises, isNotEmpty);
    });
  });

  group('seed tiến độ ban đầu', () {
    test('seedCompletedBlocks: split-chunks 0, clean-text = số block', () {
      expect(seedCompletedBlocks['split-chunks'], 0);
      final clean = exerciseById('clean-text');
      expect(seedCompletedBlocks['clean-text'], clean.blocks.length);
      expect(seedCompletedBlocks['overlap-chunks'], 0);
      expect(seedCompletedBlocks['save-document'], 0);
      expect(seedCompletedBlocks['like-post'], 0);
    });

    test('seedPassedExercises và seedDrafts', () {
      expect(seedPassedExercises, {'clean-text'});
      expect(seedDrafts, {
        'split-chunks': {'A': 'for i in range(0, len(text), size):'},
      });
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

    test('INV-01: mỗi block có đúng một marker # TODO <label> đúng thụt lề', () {
      final marker = RegExp(r'^(\s*)# TODO ([A-Z])\s*$');
      for (final exercise in allExercises) {
        final found = <String, List<int>>{};
        for (final line in exercise.template.split('\n')) {
          final m = marker.firstMatch(line);
          if (m != null) {
            found.putIfAbsent(m.group(2)!, () => []).add(m.group(1)!.length);
          }
        }
        expect(
          found.keys.toSet(),
          exercise.blocks.map((b) => b.label).toSet(),
          reason: 'exercise ${exercise.id}: marker thừa/thiếu',
        );
        for (final block in exercise.blocks) {
          expect(found[block.label], hasLength(1),
              reason: '${exercise.id} ô ${block.label}');
          expect(found[block.label]!.single, 4 * block.indentLevel,
              reason: '${exercise.id} ô ${block.label}: thụt lề marker');
        }
        expect(exercise.blocks.length, lessThanOrEqualTo(3),
            reason: 'exercise ${exercise.id}');
      }
    });

    test('block có label, explanation, id <exercise>-<label thường>', () {
      for (final exercise in allExercises) {
        for (final block in exercise.blocks) {
          expect(block.label, matches(RegExp(r'^[A-Z]$')));
          expect(block.id, '${exercise.id}-${block.label.toLowerCase()}');
          expect(block.explanation, isNotEmpty, reason: block.id);
        }
      }
    });

    test('challenge đủ nội dung cho mọi bài', () {
      for (final e in allExercises) {
        final c = e.challenge;
        expect(c.statement, isNotEmpty, reason: e.id);
        expect(c.motivation, isNotEmpty, reason: e.id);
        for (final ex in [c.small, c.project]) {
          expect(ex.caption, isNotEmpty, reason: e.id);
          expect(ex.input, contains(e.functionName), reason: e.id);
          expect(ex.output, isNotEmpty, reason: e.id);
        }
      }
    });

    test('ghép lời giải mọi ô ra đúng code tham chiếu (INV-02 phía mobile)', () {
      const expected = {
        'split-chunks': 'def split_chunks(text, size):\n'
            '    chunks = []\n'
            '    for i in range(0, len(text), size):\n'
            '        chunks.append(text[i:i + size])\n'
            '    return chunks',
        'overlap-chunks': 'def overlap_chunks(text, size, overlap):\n'
            '    chunks = []\n'
            '    for i in range(0, len(text), size - overlap):\n'
            '        chunks.append(text[i:i + size])\n'
            '    return chunks',
        'clean-text': 'def clean_text(text):\n'
            '    return text.strip()',
        'save-document': 'def save_document(store, document):\n'
            '    store.append(document)',
        'like-post': 'def like_post(post):\n'
            '    post["likes"] += 1',
      };
      expect(allExercises.map((e) => e.id).toSet(), expected.keys.toSet());
      for (final e in allExercises) {
        final merged = mergeCells(e, {
          for (final b in e.blocks) b.label: b.acceptedAnswers.first,
        });
        expect(merged.code, expected[e.id], reason: e.id);
        expect(merged.lineOrigin.length, merged.code.split('\n').length);
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
    test('split-chunks b0 chấp nhận: for i in range(0, len(text), size):', () {
      final a = exerciseById('split-chunks').blocks.first;
      expect(
        normalizeCode('for i in range(0, len(text), size):'),
        normalizeCode(a.acceptedAnswers.first),
      );
    });

    test('split-chunks có 3 ô A, B, C với indentLevel 1, 2, 1', () {
      final exercise = exerciseById('split-chunks');
      expect(exercise.blocks.map((b) => b.id).toList(),
          ['split-chunks-a', 'split-chunks-b', 'split-chunks-c']);
      expect(exercise.blocks.map((b) => b.indentLevel).toList(), [1, 2, 1]);
    });

    test('ví dụ nhỏ và ví dụ dự án của split-chunks', () {
      final c = exerciseById('split-chunks').challenge;
      expect(c.small.input, contains('split_chunks("hello world", 4)'));
      expect(c.small.output, "['hell', 'o wo', 'rld']");
      expect(c.project.input, contains('Nhân viên được nghỉ phép 12 ngày/năm.'));
      expect(c.project.input, contains(', 30)'));
    });
  });
}
