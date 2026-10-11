import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/domain/models.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/domain/progression.dart';
import 'support/content_fixture.dart';

final content = testContent;

void main() {
  nestedProgressionTests();
  group('isExerciseUnlocked', () {
    test('overlap-chunks khoá khi split-chunks chưa pass, mở khi đã pass', () {
      expect(isExerciseUnlocked(content, 'overlap-chunks', {}), isFalse);
      expect(
        isExerciseUnlocked(content, 'overlap-chunks', {'clean-text'}),
        isFalse,
      );
      expect(
        isExerciseUnlocked(content, 'overlap-chunks', {'split-chunks'}),
        isTrue,
      );
    });

    test('bài đã passed luôn mở dù bài trước chưa pass (INV-08)', () {
      expect(
        isExerciseUnlocked(content, 'overlap-chunks', {'overlap-chunks'}),
        isTrue,
      );
    });

    test('split-chunks luôn mở (bài đầu file doc-chunker-py)', () {
      expect(isExerciseUnlocked(content, 'split-chunks', {}), isTrue);
    });

    test('bài đầu mỗi file khác luôn mở', () {
      expect(isExerciseUnlocked(content, 'clean-text', {}), isTrue);
      expect(isExerciseUnlocked(content, 'save-document', {}), isTrue);
      expect(isExerciseUnlocked(content, 'like-post', {}), isTrue);
    });

    test('id không có trong nội dung → khoá', () {
      expect(isExerciseUnlocked(content, 'khong-co', {}), isFalse);
    });

    test('mọi bài không đầu file đều khoá khi chưa pass gì', () {
      for (final theme in content.themes) {
        for (final topic in theme.topics) {
          for (final file in topic.files) {
            for (var i = 1; i < file.exercises.length; i++) {
              final id = file.exercises[i].id;
              // Bài dùng chung có thể mở ở file khác — bỏ qua nếu đầu file nào đó.
              final firstElsewhere = content.themes.any(
                (t) => t.topics.any(
                  (tp) => tp.files.any((f) => f.exercises.first.id == id),
                ),
              );
              if (firstElsewhere) continue;
              expect(isExerciseUnlocked(content, id, {}), isFalse, reason: id);
            }
          }
        }
      }
    });
  });

  group('nextExerciseAfter', () {
    test('next của split-chunks = overlap-chunks', () {
      expect(nextExerciseAfter(content, 'split-chunks')?.id, 'overlap-chunks');
    });

    test('bài cuối file → null', () {
      expect(nextExerciseAfter(content, 'overlap-chunks'), isNull);
    });

    test('id không tồn tại → null', () {
      expect(nextExerciseAfter(content, 'khong-co'), isNull);
    });
  });

  group('contentIndexProvider (INV-07, INV-10)', () {
    const newBlock = Block(
      id: 'nb-a',
      title: 'A',
      prompt: 'p',
      indentLevel: 0,
      acceptedAnswers: ['x'],
      expectedOutput: '',
      hints: [],
      vocab: [],
      label: 'A',
    );
    const newExercise = Exercise(
      id: 'brand-new',
      title: 'Brand new',
      functionName: 'brand_new',
      params: [],
      blocks: [newBlock],
    );

    // Seed + một bài mới nối sau clean-text (bài đầu file, đã passed trong seed).
    Content withNewExercise() {
      var added = false;
      final themes = [
        for (final t in content.themes)
          StudyTheme(
            id: t.id,
            name: t.name,
            description: t.description,
            tags: t.tags,
            topics: [
              for (final tp in t.topics)
                Topic(
                  id: tp.id,
                  name: tp.name,
                  description: tp.description,
                  files: [
                    for (final f in tp.files)
                      if (!added && f.exercises.first.id == 'clean-text')
                        () {
                          added = true;
                          return CodeFile(
                            id: f.id,
                            name: f.name,
                            exercises: [...f.exercises, newExercise],
                          );
                        }()
                      else
                        f,
                  ],
                ),
            ],
          ),
      ];
      return Content(version: 'v2', themes: themes);
    }

    test('override content có bài mới → unlocked/inProgress thấy bài mới', () {
      final container = ProviderContainer(
        overrides: [contentIndexProvider.overrideWithValue(withNewExercise())],
      );
      addTearDown(container.dispose);

      // clean-text passed trong seed → bài ngay sau nó mở.
      expect(container.read(exerciseUnlockedProvider('brand-new')), isTrue);

      container.read(progressProvider.notifier).markPassed('split-chunks');
      container
          .read(progressProvider.notifier)
          .saveDraft('brand-new', 'A', 'x = 1');
      expect(container.read(inProgressExerciseProvider)?.id, 'brand-new');
    });

    test('nội dung gốc không có bài mới → khoá', () {
      final container = testContainer();
      addTearDown(container.dispose);
      expect(container.read(exerciseUnlockedProvider('brand-new')), isFalse);
    });

    test('đổi content không xoá tiến độ đã markPassed (INV-10)', () {
      final container = ProviderContainer(
        overrides: [contentIndexProvider.overrideWithValue(content)],
      );
      addTearDown(container.dispose);

      container.read(progressProvider.notifier).markPassed('split-chunks');
      container
          .read(progressProvider.notifier)
          .saveDraft('overlap-chunks', 'A', 'draft');
      expect(container.read(progressProvider)['split-chunks']?.passed, isTrue);

      container.updateOverrides([
        contentIndexProvider.overrideWithValue(withNewExercise()),
      ]);

      final progress = container.read(progressProvider);
      expect(progress['split-chunks']?.passed, isTrue);
      expect(progress['clean-text']?.passed, isTrue);
      expect(progress['overlap-chunks']?.drafts['A'], 'draft');
      expect(container.read(exerciseUnlockedProvider('brand-new')), isTrue);
    });
  });
}

// Module lồng nhau: bài trong sub-module khoá/mở theo quy tắc per-file.
void nestedProgressionTests() {
  Exercise ex(String id) => Exercise(
    id: id,
    title: id,
    functionName: 'fn_$id',
    className: 'Svc',
    params: const [],
    blocks: const [],
  );
  final a = ex('a'), b = ex('b'), c = ex('c');
  final nested = Content(
    version: 'n',
    themes: [
      StudyTheme(
        id: 't',
        name: 't',
        description: '',
        tags: const [],
        topics: [
          Topic(
            id: 'root',
            name: 'root',
            description: '',
            files: const [],
            modules: [
              Topic(
                id: 'mod',
                name: 'mod',
                description: '',
                files: [
                  CodeFile(id: 'f', name: 'f.py', exercises: [a, b, c]),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  group('bài trong sub-module', () {
    test('isExerciseUnlocked theo thứ tự trong file', () {
      expect(isExerciseUnlocked(nested, 'a', {}), isTrue);
      expect(isExerciseUnlocked(nested, 'b', {}), isFalse);
      expect(isExerciseUnlocked(nested, 'b', {'a'}), isTrue);
      expect(isExerciseUnlocked(nested, 'c', {'a'}), isFalse);
    });

    test('nextExerciseAfter', () {
      expect(nextExerciseAfter(nested, 'a')?.id, 'b');
      expect(nextExerciseAfter(nested, 'c'), isNull);
    });
  });
}
