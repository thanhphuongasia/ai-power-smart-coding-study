import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'support/content_fixture.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/review/review_controller.dart';
import 'package:smart_coding_study/features/stats/activity.dart';
import 'package:smart_coding_study/features/stats/stats_screen.dart';

void main() {
  final today = DateTime(2026, 3, 10);

  group('scheduleNext', () {
    test('thẻ mới: Khó 1 ngày, Được 1 ngày, Dễ 3 ngày', () {
      expect(
        scheduleNext(null, ReviewRating.hard, today).due,
        DateTime(2026, 3, 11),
      );
      expect(
        scheduleNext(null, ReviewRating.ok, today).due,
        DateTime(2026, 3, 11),
      );
      expect(
        scheduleNext(null, ReviewRating.easy, today).due,
        DateTime(2026, 3, 13),
      );
    });

    test('Được lần 2 → 3 ngày, lần 3 → interval × ease', () {
      final first = scheduleNext(null, ReviewRating.ok, today);
      final second = scheduleNext(first, ReviewRating.ok, today);
      expect(second.intervalDays, 3);
      final third = scheduleNext(second, ReviewRating.ok, today);
      expect(third.intervalDays, (3 * 2.5).round());
    });

    test('Khó đặt lại reps, giảm ease nhưng không dưới 1.3', () {
      var e = scheduleNext(null, ReviewRating.easy, today);
      for (var i = 0; i < 20; i++) {
        e = scheduleNext(e, ReviewRating.hard, today);
      }
      expect(e.reps, 0);
      expect(e.intervalDays, 1);
      expect(e.ease, closeTo(1.3, 1e-9));
    });
  });

  test('fillBlank ẩn từ vựng dài nhất có trong đáp án', () {
    final block = testContent.exerciseById('split-chunks').blocks[2];
    final blank = fillBlank(block)!;
    expect(block.acceptedAnswers.first.contains(blank.missing), isTrue);
    expect(blank.masked.contains('____'), isTrue);
    expect(blank.masked.contains(blank.missing), isFalse);
  });

  group('currentStreak', () {
    test('đếm ngược từ hôm nay', () {
      final a = {
        today: 1,
        addDays(today, -1): 2,
        addDays(today, -2): 1,
        addDays(today, -4): 1,
      };
      expect(currentStreak(a, today), 3);
    });

    test('hôm nay chưa làm thì tính từ hôm qua', () {
      final a = {addDays(today, -1): 1, addDays(today, -2): 1};
      expect(currentStreak(a, today), 2);
    });

    test('hôm qua và hôm nay đều trống → 0', () {
      expect(currentStreak({addDays(today, -2): 5}, today), 0);
    });
  });

  group('providers', () {
    late ProviderContainer c;
    setUp(() {
      c = ProviderContainer(
        overrides: [
          ...contentOverrides,
          clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
        ],
      );
    });
    tearDown(() => c.dispose());

    test('seed: chỉ bài đã passed (clean-text) có thẻ, hẹn ngày mai', () {
      expect(c.read(dueCardsProvider), isEmpty);
      final upcoming = c
          .read(upcomingCardsProvider)
          .map((s) => s.card.id)
          .toList();
      expect(upcoming, ['clean-text-a']);
    });

    test('bài chỉ có draft (split-chunks) chưa sinh thẻ nào', () {
      final ids = c.read(reviewCardsProvider).map((card) => card.id);
      expect(ids.where((id) => id.startsWith('split-chunks')), isEmpty);
    });

    test('pass bài ⇒ mọi ô thành thẻ đến hạn và ghi hoạt động', () {
      c.read(progressProvider.notifier).markPassed('split-chunks');
      expect(c.read(dueCardsProvider).map((s) => s.card.id), [
        'split-chunks-a',
        'split-chunks-b',
        'split-chunks-c',
      ]);
      expect(c.read(activityProvider)[DateTime(2026, 3, 10)], 1);
    });

    test('rate chuyển thẻ khỏi hàng đến hạn và ghi hoạt động hôm nay', () {
      c.read(progressProvider.notifier).markPassed('split-chunks');
      c
          .read(reviewScheduleProvider.notifier)
          .rate('split-chunks-a', ReviewRating.easy);
      expect(c.read(dueCardsProvider).map((s) => s.card.id), [
        'split-chunks-b',
        'split-chunks-c',
      ]);
      // 1 lần từ markPassed + 1 lần từ rate, cùng ngày.
      expect(c.read(activityProvider)[DateTime(2026, 3, 10)], 2);
    });

    test(
      'INV-07: ô đã xem lời giải bị kéo về lịch ôn gần nhất (≤ ngày mai)',
      () {
        final progress = c.read(progressProvider.notifier);
        progress.markPassed('split-chunks');
        progress.viewSolution('split-chunks', 'A');
        c
            .read(reviewScheduleProvider.notifier)
            .rate('split-chunks-a', ReviewRating.easy); // Dễ ⇒ 3 ngày
        c
            .read(reviewScheduleProvider.notifier)
            .rate('split-chunks-b', ReviewRating.easy); // ô sạch giữ 3 ngày

        DateTime dueOf(String id) => c
            .read(upcomingCardsProvider)
            .firstWhere((s) => s.card.id == id)
            .due;
        expect(dueOf('split-chunks-a'), DateTime(2026, 3, 11));
        expect(dueOf('split-chunks-b'), DateTime(2026, 3, 13));
      },
    );

    test('exercise dùng chung chỉ sinh thẻ một lần', () {
      final ids = c.read(reviewCardsProvider).map((card) => card.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  test('chunker.py dùng ở 2 theme, split_chunks là cùng một exercise', () {
    final usages = testContent.locateFilesNamed('chunker.py');
    expect(usages.map((u) => u.theme.id), ['rag', 'doc-system']);
    expect(
      identical(usages[0].file.exercises.first, usages[1].file.exercises.first),
      isTrue,
    );
  });

  testWidgets(
    'INV-07: Stats "không cần gợi ý" bỏ ô đã xem lời giải / dùng gợi ý',
    (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: contentOverrides,
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: buildAppTheme(),
                home: const StatsScreen(),
              );
            },
          ),
        ),
      );
      Finder tile(String key) => find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Text),
      );
      String noHint() => tester.widget<Text>(tile('stat-no-hint').first).data!;

      // Seed: chỉ clean-text (1 ô sạch) đã passed.
      expect(noHint(), '100%');

      final progress = container.read(progressProvider.notifier);
      // Bài chưa pass: gợi ý/lời giải của nó không ảnh hưởng.
      progress.viewSolution('split-chunks', 'A');
      await tester.pump();
      expect(noHint(), '100%');

      // Pass: 3 ô, A đã xem lời giải, B dùng gợi ý, C sạch ⇒ sạch 2/4 = 50%.
      progress.useHint('split-chunks', 'B');
      progress.markPassed('split-chunks');
      await tester.pump();
      expect(noHint(), '50%');
    },
  );
}
