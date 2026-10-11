// Hợp đồng nội dung trên backend/content/content.json (nguồn thật):
//  - INV-05: marker `# TODO <label>` đúng một lần mỗi ô, thụt = 4 × indent_level.
//  - INV-04: ghép lời giải các ô vào template = judge.solution từng ký tự.
//  - INV-02/03 + quan hệ: sơ đồ lớp (theme.diagram) khớp code các bài.
// Thay cho seed_test.dart (luật nội dung) + judge_contract_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/domain/answer_checker.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/domain/merge.dart';
import 'package:smart_coding_study/domain/models.dart';

import 'support/content_fixture.dart';

/// Thân của `class [name]` (dòng bắt đầu ở cột 0) tới dòng kế tiếp không rỗng
/// nằm ở cột 0; null nếu code không có lớp đó.
String? _classBody(String code, String name) {
  final lines = code.split('\n');
  final head = RegExp('^class $name\\b');
  final start = lines.indexWhere(head.hasMatch);
  if (start < 0) return null;
  var end = start + 1;
  while (end < lines.length &&
      (lines[end].trim().isEmpty || lines[end].startsWith(RegExp(r'\s')))) {
    end++;
  }
  return lines.sublist(start, end).join('\n');
}

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
      for (final theme in testContent.themes) {
        for (final topic in theme.allTopics) {
          for (final f in topic.files) {
            for (final e in f.exercises) {
              expect(
                rawExercises.containsKey(e.id),
                isTrue,
                reason: 'file ${f.id} trỏ tới bài không có: ${e.id}',
              );
            }
          }
        }
      }
    });

    test('mọi theme có topic, mọi topic có ít nhất 1 exercise', () {
      for (final theme in testContent.themes) {
        expect(theme.topics, isNotEmpty, reason: 'theme ${theme.id}');
        for (final topic in theme.allTopics) {
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
        'flight-init',
        'flight-seats-left',
        'flight-is-full',
        'flight-service-add',
        'flight-service-search',
        'schedule-flights-on',
        'flight-controller-add',
        'flight-controller-delete',
        'booking-book',
        'booking-cancel',
        'reservation-cancel',
        'reservation-change-seats',
        'reservation-change-flight',
        'seat-map-assign',
      ]) {
        expect(rawExercises.containsKey(id), isTrue, reason: id);
      }
      expect(testContent.exerciseById('split-chunks').blocks.length, 3);
      expect(testContent.locateFilesNamed('chunker.py').length, 2);
    });

    test('theme airline đứng đầu, cây ≥ 2 cấp module, 14 bài method', () {
      final airline = testContent.themes.first;
      expect(airline.id, 'airline');
      expect(airline.topics.any((t) => t.modules.isNotEmpty), isTrue);
      expect(airline.allTopics.length, greaterThanOrEqualTo(4));
      final methods = allExercises.where((e) => e.className != null).toList();
      expect(methods.length, 14);
      for (final e in methods) {
        final judge = rawExercises[e.id]['judge'] as Map<String, dynamic>;
        expect(
          judge['solution'],
          contains('class ${e.className}'),
          reason: '${e.id}: solution thiếu class ${e.className}',
        );
        expect((judge['cases'] as List).length, inInclusiveRange(4, 7));
        expect(e.template, contains('class ${e.className}'));
        // Mọi case của method là dạng kịch bản (steps/call/expect).
        for (final c in judge['cases'] as List) {
          expect((c as Map).containsKey('call'), isTrue, reason: e.id);
        }
      }
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
        for (final topic in theme.allTopics) {
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
        // Constructor được gọi qua tên class (`Flight(...)`), không ai gõ `__init__`.
        final called = e.functionName == '__init__'
            ? e.className!
            : e.functionName;
        expect(c.statement, isNotEmpty, reason: e.id);
        expect(c.motivation, isNotEmpty, reason: e.id);
        for (final ex in [c.small, c.project]) {
          expect(ex.caption, isNotEmpty, reason: e.id);
          expect(ex.input, contains(called), reason: e.id);
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

    test('không có ô nào nằm sau return trong cùng nhánh (code chết)', () {
      // Ô kế tiếp chỉ chạy tới được nếu nhánh chứa `return` đã đóng: giữa hai
      // marker phải có dòng thụt ÍT hơn ô return (vd `except`, hết `if`), hoặc
      // ô kế thụt ít hơn hẳn (guard clause `if …: return` rồi code tiếp).
      final marker = RegExp(r'^(\s*)# TODO ([A-Z])\s*$');
      for (final exercise in allExercises) {
        final lines = exercise.template.split('\n');
        int lineOf(String label) => lines.indexWhere((l) {
          final m = marker.firstMatch(l);
          return m != null && m.group(2) == label;
        });
        int indentOf(String l) => l.length - l.trimLeft().length;
        final blocks = exercise.blocks;
        for (var i = 0; i + 1 < blocks.length; i++) {
          if (!blocks[i].acceptedAnswers.first.trim().startsWith('return')) {
            continue;
          }
          final from = lineOf(blocks[i].label);
          final to = lineOf(blocks[i + 1].label);
          final retIndent = indentOf(lines[from]);
          final closed =
              indentOf(lines[to]) < retIndent ||
              lines
                  .sublist(from + 1, to)
                  .any((l) => l.trim().isNotEmpty && indentOf(l) < retIndent);
          expect(
            closed,
            isTrue,
            reason:
                '${exercise.id}: ${blocks[i + 1].id} nằm sau return '
                '${blocks[i].id} trong cùng nhánh',
          );
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

  group('sơ đồ lớp (theme.diagram) khớp bài tập', () {
    final rawThemes = {
      for (final t in contentJson['themes'] as List)
        (t as Map<String, dynamic>)['id'] as String: t,
    };
    Map<String, dynamic> diagramOf(String themeId) =>
        rawThemes[themeId]!['diagram'] as Map<String, dynamic>;
    List<Map<String, dynamic>> classesOf(String themeId) => [
      for (final c in diagramOf(themeId)['classes'] as List)
        c as Map<String, dynamic>,
    ];
    String mergedCode(Exercise e) => mergeCells(e, {
      for (final b in e.blocks) b.label: b.acceptedAnswers.first,
    }).code;

    test(
      'INV-02: thuộc tính/phương thức trong sơ đồ có trong code bài của lớp',
      () {
        for (final theme in testContent.themes) {
          for (final cls in classesOf(theme.id)) {
            final name = cls['name'] as String;
            // Bài của lớp đó; thêm bản rút gọn `class Name` nằm trong file bài
            // khác (vd FlightService.remove_flight chỉ có trong bài controller).
            final themeCodes = [
              for (final e in allExercises)
                if (testContent.locateExercise(e.id).theme.id == theme.id)
                  (e: e, code: mergedCode(e)),
            ];
            // Thân `class Name` chính xác (không nhầm `class NameService`).
            final bodies = [
              for (final x in themeCodes) ?_classBody(x.code, name),
            ];
            final methods = (cls['methods'] as List).cast<String>();
            if (methods.isNotEmpty) {
              expect(
                bodies,
                isNotEmpty,
                reason: '$name: không bài nào chứa `class $name`',
              );
            }
            for (final a in cls['attributes'] as List) {
              final attr = (a as Map<String, dynamic>)['name'] as String;
              expect(
                bodies.any((c) => c.contains('self.$attr =')),
                isTrue,
                reason: '$name.$attr: không bài nào có "self.$attr ="',
              );
            }
            for (final m in cls['methods'] as List) {
              expect(
                bodies.any((c) => c.contains('def $m(')),
                isTrue,
                reason: '$name.$m(): không bài nào có "def $m("',
              );
            }
          }
        }
      },
    );

    test('INV-03: mọi bài có class_name đều có lớp đó trong sơ đồ theme', () {
      for (final e in allExercises) {
        final cn = e.className;
        if (cn == null) continue;
        final themeId = testContent.locateExercise(e.id).theme.id;
        expect(
          classesOf(themeId).any((c) => c['name'] == cn),
          isTrue,
          reason: '${e.id}: lớp $cn thiếu trong diagram của theme $themeId',
        );
      }
    });

    test('quan hệ trỏ tới lớp có thật và via ⊆ methods của from', () {
      for (final theme in testContent.themes) {
        final classes = {
          for (final c in classesOf(theme.id)) c['name'] as String: c,
        };
        for (final r in diagramOf(theme.id)['relations'] as List) {
          final rel = r as Map<String, dynamic>;
          final from = rel['from'] as String;
          final to = rel['to'] as String;
          expect(classes.containsKey(from), isTrue, reason: 'from $from');
          expect(classes.containsKey(to), isTrue, reason: 'to $to');
          final methods = (classes[from]!['methods'] as List).cast<String>();
          for (final v in rel['via'] as List) {
            expect(methods, contains(v), reason: '$from→$to via $v');
          }
        }
      }
    });
  });
}
