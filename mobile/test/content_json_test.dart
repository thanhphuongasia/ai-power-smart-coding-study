import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/data/seed.dart' as seed;
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/domain/models.dart';

final seedContent = Content(version: 'seed', themes: seed.seedThemes);

Map<String, dynamic> roundTripJson() =>
    jsonDecode(jsonEncode(seedContent.toJson())) as Map<String, dynamic>;

void expectExample(Example a, Example b) {
  expect(a.caption, b.caption);
  expect(a.input, b.input);
  expect(a.output, b.output);
  expect(a.note, b.note);
}

void expectExercise(Exercise a, Exercise b) {
  expect(a.id, b.id);
  expect(a.title, b.title);
  expect(a.functionName, b.functionName);
  expect(a.params, b.params);
  expect(a.template, b.template);
  expect(a.challenge.statement, b.challenge.statement);
  expect(a.challenge.motivation, b.challenge.motivation);
  expectExample(a.challenge.small, b.challenge.small);
  expectExample(a.challenge.project, b.challenge.project);
  expect(a.blocks.length, b.blocks.length);
  for (var i = 0; i < a.blocks.length; i++) {
    final x = a.blocks[i], y = b.blocks[i];
    expect(x.id, y.id);
    expect(x.label, y.label);
    expect(x.title, y.title);
    expect(x.prompt, y.prompt);
    expect(x.indentLevel, y.indentLevel);
    expect(x.acceptedAnswers, y.acceptedAnswers);
    expect(x.expectedOutput, y.expectedOutput);
    expect(x.explanation, y.explanation);
    expect(x.hints, y.hints);
    expect(x.vocab, y.vocab);
  }
}

void main() {
  group('Content index khớp hàm seed', () {
    test('exerciseById', () {
      for (final e in seed.uniqueExercises()) {
        expect(
          identical(seedContent.exerciseById(e.id), seed.exerciseById(e.id)),
          isTrue,
        );
      }
      expect(() => seedContent.exerciseById('nope'), throwsStateError);
    });

    test('locateExercise', () {
      for (final e in seed.uniqueExercises()) {
        final a = seedContent.locateExercise(e.id);
        final b = seed.locateExercise(e.id);
        expect(identical(a.theme, b.theme), isTrue);
        expect(identical(a.topic, b.topic), isTrue);
        expect(identical(a.file, b.file), isTrue);
      }
      expect(() => seedContent.locateExercise('nope'), throwsStateError);
    });

    test('uniqueExercises', () {
      final a = seedContent.uniqueExercises();
      final b = seed.uniqueExercises();
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(identical(a[i], b[i]), isTrue);
      }
    });

    test('locateFilesNamed', () {
      final names = {
        for (final t in seed.seedThemes)
          for (final p in t.topics)
            for (final f in p.files) f.name,
        'khong-co.py',
      };
      for (final n in names) {
        final a = seedContent.locateFilesNamed(n);
        final b = seed.locateFilesNamed(n);
        expect(a.length, b.length, reason: n);
        for (var i = 0; i < a.length; i++) {
          expect(identical(a[i].file, b[i].file), isTrue);
          expect(identical(a[i].topic, b[i].topic), isTrue);
          expect(identical(a[i].theme, b[i].theme), isTrue);
        }
      }
    });
  });

  group('JSON', () {
    test('round-trip bằng seed về mọi field', () {
      final back = Content.fromJson(roundTripJson());
      expect(back.version, 'seed');
      expect(back.themes.length, seedContent.themes.length);
      for (var i = 0; i < back.themes.length; i++) {
        final a = back.themes[i], b = seedContent.themes[i];
        expect(a.id, b.id);
        expect(a.name, b.name);
        expect(a.description, b.description);
        expect(a.tags, b.tags);
        expect(a.topics.length, b.topics.length);
        for (var j = 0; j < a.topics.length; j++) {
          final ta = a.topics[j], tb = b.topics[j];
          expect(ta.id, tb.id);
          expect(ta.name, tb.name);
          expect(ta.description, tb.description);
          expect(ta.files.length, tb.files.length);
          for (var k = 0; k < ta.files.length; k++) {
            final fa = ta.files[k], fb = tb.files[k];
            expect(fa.id, fb.id);
            expect(fa.name, fb.name);
            expect(fa.exercises.length, fb.exercises.length);
            for (var m = 0; m < fa.exercises.length; m++) {
              expectExercise(fa.exercises[m], fb.exercises[m]);
            }
          }
        }
      }
      // toJson của bản parse lại bằng toJson gốc (bắt field bị rơi).
      expect(jsonEncode(back.toJson()), jsonEncode(seedContent.toJson()));
    });

    test('bài dùng chung là cùng một instance', () {
      final back = Content.fromJson(roundTripJson());
      final files = back.locateFilesNamed('chunker.py');
      final shared = <String, List<Exercise>>{};
      for (final f
          in back.themes.expand((t) => t.topics).expand((p) => p.files)) {
        for (final e in f.exercises) {
          shared.putIfAbsent(e.id, () => []).add(e);
        }
      }
      final multi = shared.values.where((l) => l.length > 1).toList();
      expect(multi, isNotEmpty, reason: 'seed phải có bài dùng chung');
      for (final l in multi) {
        for (final e in l) {
          expect(identical(e, l.first), isTrue);
        }
      }
      expect(files, isNotEmpty);
    });

    test('toJson không có key judge và note có thể null', () {
      final j = roundTripJson();
      expect(jsonEncode(j).contains('"judge"'), isFalse);
      final ex =
          (j['exercises'] as Map<String, dynamic>).values.first
              as Map<String, dynamic>;
      expect(ex['function_name'], isA<String>());
      expect((ex['blocks'] as List).first, contains('indent_level'));
      final small = (ex['challenge'] as Map)['small'] as Map;
      expect(small.containsKey('note'), isTrue);
    });

    test('note null parse được', () {
      final j = roundTripJson();
      final ex =
          (j['exercises'] as Map<String, dynamic>).values.first
              as Map<String, dynamic>;
      ((ex['challenge'] as Map)['small'] as Map)['note'] = null;
      final back = Content.fromJson(j);
      expect(back.uniqueExercises().first.challenge.small.note, isNull);
    });
  });

  group('FormatException', () {
    test('file trỏ tới exercise id không có', () {
      final j = roundTripJson();
      final file =
          (((j['themes'] as List).first as Map)['topics'] as List)
                  .first['files'][0]
              as Map;
      (file['exercise_ids'] as List).add('ghost-id');
      expect(
        () => Content.fromJson(j),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('ghost-id'),
          ),
        ),
      );
    });

    test('thiếu field bắt buộc', () {
      final j = roundTripJson();
      ((j['exercises'] as Map).values.first as Map).remove('function_name');
      expect(
        () => Content.fromJson(j),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('function_name'),
          ),
        ),
      );
      final j2 = roundTripJson()..remove('version');
      expect(() => Content.fromJson(j2), throwsFormatException);
    });

    test('sai kiểu', () {
      final j = roundTripJson();
      final block =
          (((j['exercises'] as Map).values.first as Map)['blocks'] as List)
                  .first
              as Map;
      block['indent_level'] = '1';
      expect(
        () => Content.fromJson(j),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('indent_level'),
          ),
        ),
      );
      final j2 = roundTripJson();
      j2['themes'] = 'x';
      expect(() => Content.fromJson(j2), throwsFormatException);
    });
  });

  test('contentIndexProvider mặc định = seed', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(contentIndexProvider);
    expect(c.version, 'seed');
    expect(identical(c.themes, seed.seedThemes), isTrue);
  });
}
