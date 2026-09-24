import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/review/review_controller.dart';
import 'package:smart_coding_study/features/stats/activity.dart';

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
    final block = splitChunksExercise.blocks[2];
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
          clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
        ],
      );
    });
    tearDown(() => c.dispose());

    test('seed: 2 block split-chunks đến hạn, 2 block clean-text sắp tới', () {
      final due = c.read(dueCardsProvider).map((s) => s.card.id).toList();
      expect(due, ['split-chunks-b0', 'split-chunks-b1']);
      final upcoming = c
          .read(upcomingCardsProvider)
          .map((s) => s.card.id)
          .toList();
      expect(upcoming, ['clean-text-b0', 'clean-text-b1']);
    });

    test('rate chuyển thẻ khỏi hàng đến hạn và ghi hoạt động hôm nay', () {
      c
          .read(reviewScheduleProvider.notifier)
          .rate('split-chunks-b0', ReviewRating.easy);
      expect(c.read(dueCardsProvider).map((s) => s.card.id), [
        'split-chunks-b1',
      ]);
      expect(c.read(activityProvider)[DateTime(2026, 3, 10)], 1);
    });

    test('block làm đúng thành thẻ mới và tăng hoạt động', () {
      c.read(progressProvider.notifier).markBlockPassed('split-chunks', 2);
      expect(
        c.read(dueCardsProvider).map((s) => s.card.id),
        contains('split-chunks-b2'),
      );
      expect(c.read(activityProvider)[DateTime(2026, 3, 10)], 1);
    });

    test('exercise dùng chung chỉ sinh thẻ một lần', () {
      final ids = c.read(reviewCardsProvider).map((card) => card.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  test('chunker.py dùng ở 2 theme, split_chunks là cùng một exercise', () {
    final usages = locateFilesNamed('chunker.py');
    expect(usages.map((u) => u.theme.id), ['rag', 'doc-system']);
    expect(
      identical(usages[0].file.exercises.first, usages[1].file.exercises.first),
      isTrue,
    );
  });
}
