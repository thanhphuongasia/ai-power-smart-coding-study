// Hợp đồng nội dung trên backend/content/content.json (nguồn thật):
//  - INV-05: marker `# TODO <label>` đúng một lần mỗi ô, thụt = 4 × indent_level.
//  - INV-04: ghép lời giải các ô vào template = judge.solution từng ký tự.
// Thay cho seed_test.dart (luật nội dung) + judge_contract_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/domain/answer_checker.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/domain/merge.dart';

import 'support/content_fixture.dart';

void main() {
  final rawExercises = contentJson['exercises'] as Map<String, dynamic>;
  final allExercises = testContent.uniqueExercises();
  final allBlocks = [for (final e in allExercises) ...e.blocks];

  group('parse content.json', () {
    test('Content.fromJson đọc được file (bỏ qua judge, version source)', () {
      expect(contentJson['version'], 'source');
      final c = Content.fromJson(contentJson);
      expect(c.themes, isNotEmpty);
      expect(c.uniqueExercises().length, rawExercises.length);
      // toJson (shape /content) không lộ judge.
      final out = c.toJson()['exercises'] as Map<String, dynamic>;
      for (final e in out.values) {
        expect((e as Map).containsKey('judge'), isFalse);
      }
    });

    test('mọi exercise_ids của file tồn tại trong exercises', () {
      for (final t in contentJson['themes'] as List) {
        for (final tp in (t as Map)['topics'] as List) {
          for (final f in (tp as Map)['files'] as List) {
            for (final id in (f as Map)['exercise_ids'] as List) {
              expect(
                rawExercises.containsKey(id),
                isTrue,
                reason: 'file ${f['id']} trỏ tới bài không có: $id',
              );
            }
          }
        }
      }
    });

    test('mọi theme có topic, mọi topic có ít nhất 1 exercise', () {
      for (final theme in testContent.themes) {
        expect(theme.topics, isNotEmpty, reason: 'theme ${theme.id}');
        for (final topic in theme.topics) {
          final count = topic.files.fold<int>(
            0,
            (sum, f) => sum + f.exercises.length,
          );
          expect(count, greaterThanOrEqualTo(1), reason: 'topic ${topic.id}');
        }
      }
    });

    test('bài mà các test khác dựa vào có trong content.json', () {
      for (final id in [
        'split-chunks',
        'overlap-chunks',
        'clean-text',
        'save-document',
        'like-post',
      ]) {
        expect(rawExercises.containsKey(id), isTrue, reason: id);
      }
      expect(testContent.exerciseById('split-chunks').blocks.length, 3);
      expect(testContent.locateFilesNamed('chunker.py').length, 2);
    });
  });

  group('INV-05: marker TODO khớp ô', () {
    test(
      'mỗi ô đúng một marker, thụt = 4 × indent_level, không marker thừa',
      () {
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
            expect(
              found[block.label],
              hasLength(1),
              reason: '${exercise.id} ô ${block.label}',
            );
            expect(
              found[block.label]!.single,
              4 * block.indentLevel,
              reason: '${exercise.id} ô ${block.label}: thụt lề marker',
            );
          }
          expect(
            exercise.blocks.length,
            lessThanOrEqualTo(3),
            reason: 'exercise ${exercise.id}',
          );
        }
      },
    );
  });

  group('INV-04: lời giải các ô = judge.solution', () {
    test('mọi bài có judge.solution và cases', () {
      for (final e in allExercises) {
        final judge = rawExercises[e.id]['judge'] as Map<String, dynamic>?;
        expect(judge, isNotNull, reason: '${e.id} thiếu judge');
        expect(judge!['solution'], isA<String>(), reason: e.id);
        expect(judge['cases'], isA<List>(), reason: e.id);
        expect(judge['cases'] as List, isNotEmpty, reason: e.id);
        expect(
          judge['solution'],
          contains('def ${e.functionName}('),
          reason: '${e.id}: solution không định nghĩa functionName',
        );
      }
    });

    test('mergeCells(đáp án đầu của từng ô) == judge.solution từng ký tự', () {
      for (final e in allExercises) {
        final solution =
            (rawExercises[e.id]['judge'] as Map<String, dynamic>)['solution'];
        final merged = mergeCells(e, {
          for (final b in e.blocks) b.label: b.acceptedAnswers.first,
        });
        expect(merged.code, solution, reason: 'Lệch ở bài ${e.id}');
        expect(
          merged.lineOrigin.length,
          merged.code.split('\n').length,
          reason: e.id,
        );
      }
    });
  });

  group('luật nội dung', () {
    test('mọi ID duy nhất toàn cục', () {
      final ids = <String>[];
      for (final theme in testContent.themes) {
        ids.add(theme.id);
        for (final topic in theme.topics) {
          ids.add(topic.id);
          for (final file in topic.files) {
            ids.add(file.id);
          }
        }
      }
      for (final e in allExercises) {
        ids.add(e.id);
        ids.addAll(e.blocks.map((b) => b.id));
      }
      final seen = <String>{};
      for (final id in ids) {
        expect(seen.add(id), isTrue, reason: 'ID trùng: $id');
      }
    });

    test('mọi block có tối đa 2 dòng cho mỗi đáp án', () {
      for (final block in allBlocks) {
        for (final answer in block.acceptedAnswers) {
          expect(
            answer.split('\n').length,
            lessThanOrEqualTo(2),
            reason: 'block ${block.id}',
          );
        }
      }
    });

    test('tổng số dòng đáp án đầu tiên của mỗi exercise ≤ 10', () {
      for (final exercise in allExercises) {
        final total = exercise.blocks.fold<int>(
          0,
          (sum, b) => sum + b.acceptedAnswers.first.split('\n').length,
        );
        expect(total, lessThanOrEqualTo(10), reason: 'exercise ${exercise.id}');
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

    test(
      'không có 2 block trong cùng exercise trùng đáp án đầu sau normalize',
      () {
        for (final exercise in allExercises) {
          final seen = <String, String>{};
          for (final block in exercise.blocks) {
            final n = normalizeCode(block.acceptedAnswers.first);
            expect(
              seen.containsKey(n),
              isFalse,
              reason: '${exercise.id}: ${block.id} trùng ${seen[n]}',
            );
            seen[n] = block.id;
          }
        }
      },
    );

    test('block sau một block bắt đầu bằng return phải thụt sâu hơn', () {
      for (final exercise in allExercises) {
        for (var i = 0; i < exercise.blocks.length; i++) {
          final block = exercise.blocks[i];
          if (!block.acceptedAnswers.first.trim().startsWith('return')) {
            continue;
          }
          for (var j = i + 1; j < exercise.blocks.length; j++) {
            expect(
              exercise.blocks[j].indentLevel > block.indentLevel,
              isTrue,
              reason:
                  '${exercise.id}: ${exercise.blocks[j].id} sau return '
                  '${block.id}',
            );
          }
        }
      }
    });
  });

  group('split-chunks', () {
    final ex = testContent.exerciseById('split-chunks');

    test('ô A chấp nhận for i in range(0, len(text), size):', () {
      expect(
        normalizeCode('for i in range(0, len(text), size):'),
        normalizeCode(ex.blocks.first.acceptedAnswers.first),
      );
    });

    test('3 ô A, B, C với indentLevel 1, 2, 1', () {
      expect(ex.blocks.map((b) => b.id).toList(), [
        'split-chunks-a',
        'split-chunks-b',
        'split-chunks-c',
      ]);
      expect(ex.blocks.map((b) => b.indentLevel).toList(), [1, 2, 1]);
    });

    test('ví dụ nhỏ và ví dụ dự án', () {
      final c = ex.challenge;
      expect(c.small.input, contains('split_chunks("hello world", 4)'));
      expect(c.small.output, "['hell', 'o wo', 'rld']");
      expect(
        c.project.input,
        contains('Nhân viên được nghỉ phép 12 ngày/năm.'),
      );
      expect(c.project.input, contains(', 30)'));
    });
  });
}
