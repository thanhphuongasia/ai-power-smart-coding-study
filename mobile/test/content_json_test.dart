import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/domain/models.dart';

import 'support/content_fixture.dart';

Map<String, dynamic> roundTripJson() =>
    jsonDecode(jsonEncode(testContent.toJson())) as Map<String, dynamic>;

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
  nestedTests();
  group('Content index trên content.json', () {
    test('exerciseById', () {
      for (final e in testContent.uniqueExercises()) {
        expect(identical(testContent.exerciseById(e.id), e), isTrue);
      }
      expect(() => testContent.exerciseById('nope'), throwsStateError);
    });

    test('locateExercise: file tìm được thật sự chứa bài', () {
      for (final e in testContent.uniqueExercises()) {
        final loc = testContent.locateExercise(e.id);
        expect(loc.file.exercises.any((x) => identical(x, e)), isTrue);
        expect(loc.topic.files, contains(loc.file));
        expect(loc.theme.allTopics, contains(loc.topic));
      }
      expect(() => testContent.locateExercise('nope'), throwsStateError);
    });

    test('uniqueExercises: mỗi id một lần, đủ số bài của file', () {
      final ids = testContent.uniqueExercises().map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(
        ids.toSet(),
        (contentJson['exercises'] as Map<String, dynamic>).keys.toSet(),
      );
    });

    test('locateFilesNamed', () {
      final names = {
        for (final t in testContent.themes)
          for (final p in t.topics)
            for (final f in p.files) f.name,
      };
      for (final n in names) {
        final found = testContent.locateFilesNamed(n);
        expect(found, isNotEmpty, reason: n);
        for (final x in found) {
          expect(x.file.name, n);
        }
      }
      expect(testContent.locateFilesNamed('khong-co.py'), isEmpty);
    });
  });

  group('JSON', () {
    test('round-trip content.json về mọi field', () {
      final back = Content.fromJson(roundTripJson());
      expect(back.version, testContent.version);
      expect(back.themes.length, testContent.themes.length);
      for (var i = 0; i < back.themes.length; i++) {
        final a = back.themes[i], b = testContent.themes[i];
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
      expect(jsonEncode(back.toJson()), jsonEncode(testContent.toJson()));
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
      expect(multi, isNotEmpty, reason: 'content.json phải có bài dùng chung');
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

  test('contentIndexProvider không có mặc định: ném UnimplementedError', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(contentIndexProvider),
      throwsA(
        anyOf(
          isA<UnimplementedError>(),
          predicate((e) => '$e'.contains('override contentIndexProvider')),
        ),
      ),
    );
  });
}

/// Fixture lồng nhau: theme → topic "root" (file r.py) → module "mod" (file
/// m.py: bài a, b có class_name) → module "deep" (file d.py).
Map<String, dynamic> _ex(String id, String? cls) => {
  'id': id,
  'title': id,
  'function_name': 'fn_$id',
  'class_name': cls,
  'params': <String>[],
  'template': '',
  'challenge': {
    'statement': '',
    'motivation': '',
    'small': {'caption': '', 'input': '', 'output': '', 'note': null},
    'project': {'caption': '', 'input': '', 'output': '', 'note': null},
  },
  'blocks': <Map<String, dynamic>>[],
};

Map<String, dynamic> nestedJson() => {
  'version': 'n1',
  'themes': [
    {
      'id': 'th',
      'name': 'Theme',
      'description': '',
      'tags': <String>[],
      'topics': [
        {
          'id': 'root',
          'name': 'Root',
          'description': '',
          'files': [
            {
              'id': 'f-r',
              'name': 'r.py',
              'exercise_ids': ['r1'],
            },
          ],
          'modules': [
            {
              'id': 'mod',
              'name': 'Mod',
              'description': '',
              'files': [
                {
                  'id': 'f-m',
                  'name': 'm.py',
                  'exercise_ids': ['a', 'b'],
                },
              ],
              'modules': [
                {
                  'id': 'deep',
                  'name': 'Deep',
                  'description': '',
                  'files': [
                    {
                      'id': 'f-d',
                      'name': 'd.py',
                      'exercise_ids': ['d1'],
                    },
                  ],
                  'modules': <Map<String, dynamic>>[],
                },
              ],
            },
          ],
        },
        {
          'id': 'second',
          'name': 'Second',
          'description': '',
          'files': <Map<String, dynamic>>[],
          'modules': <Map<String, dynamic>>[],
        },
      ],
    },
  ],
  'exercises': {
    'r1': _ex('r1', null),
    'a': _ex('a', 'FlightService'),
    'b': _ex('b', 'FlightService'),
    'd1': _ex('d1', null),
  },
};

void nestedTests() {
  group('module lồng nhau + class_name', () {
    final c = Content.fromJson(nestedJson());

    test('allTopics preorder, allFiles, uniqueExercises', () {
      final th = c.themes.single;
      expect(th.allTopics.map((t) => t.id), ['root', 'mod', 'deep', 'second']);
      expect(th.allFiles.map((f) => f.id), ['f-r', 'f-m', 'f-d']);
      expect(th.topics.first.allFiles.map((f) => f.id), ['f-r', 'f-m', 'f-d']);
      expect(c.uniqueExercises().map((e) => e.id), ['r1', 'a', 'b', 'd1']);
      expect(c.exerciseById('d1').id, 'd1');
    });

    test('locateExercise: topic là module chứa trực tiếp file', () {
      final loc = c.locateExercise('b');
      expect(loc.topic.id, 'mod');
      expect(loc.file.id, 'f-m');
      expect(loc.theme.id, 'th');
      expect(c.locateExercise('d1').topic.id, 'deep');
      expect(c.locateFilesNamed('d.py').single.topic.id, 'deep');
    });

    test('locateTopic và modulePath', () {
      expect(c.locateTopic('deep')?.topic.id, 'deep');
      expect(c.locateTopic('deep')?.theme.id, 'th');
      expect(c.locateTopic('root')?.topic.id, 'root');
      expect(c.locateTopic('nope'), isNull);
      expect(c.modulePath('deep').map((t) => t.id), ['root', 'mod', 'deep']);
      expect(c.modulePath('root').map((t) => t.id), ['root']);
      expect(c.modulePath('second').map((t) => t.id), ['second']);
      expect(c.modulePath('nope'), isEmpty);
    });

    test('qualifiedName', () {
      expect(c.exerciseById('a').qualifiedName, 'FlightService.fn_a');
      expect(c.exerciseById('r1').className, isNull);
      expect(c.exerciseById('r1').qualifiedName, 'fn_r1');
    });

    test('toJson round trip giữ modules và class_name', () {
      final j = jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>;
      expect(jsonEncode(j), jsonEncode(nestedJson()));
      final back = Content.fromJson(j);
      expect(back.modulePath('deep').length, 3);
      expect(back.exerciseById('a').className, 'FlightService');
    });

    test('thiếu modules → FormatException nêu field', () {
      final j = nestedJson();
      (((j['themes'] as List).first as Map)['topics'] as List).first.remove(
        'modules',
      );
      expect(
        () => Content.fromJson(j),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('modules'),
          ),
        ),
      );
    });

    test('modules sai kiểu → FormatException', () {
      final j = nestedJson();
      (((j['themes'] as List).first as Map)['topics'] as List)
              .first['modules'] =
          'x';
      expect(() => Content.fromJson(j), throwsFormatException);
    });

    test('thiếu hoặc sai kiểu class_name → FormatException nêu field', () {
      final j = nestedJson();
      ((j['exercises'] as Map)['a'] as Map).remove('class_name');
      expect(
        () => Content.fromJson(j),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('class_name'),
          ),
        ),
      );
      final j2 = nestedJson();
      ((j2['exercises'] as Map)['a'] as Map)['class_name'] = 5;
      expect(
        () => Content.fromJson(j2),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('class_name'),
          ),
        ),
      );
    });
  });
}
