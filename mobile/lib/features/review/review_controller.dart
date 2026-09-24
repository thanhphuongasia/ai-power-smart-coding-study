/// Ôn tập kiểu flashcard: mỗi block đã làm đúng thành một thẻ, lịch ôn tính
/// theo đánh giá Khó / Được / Dễ (SM-2 rút gọn), lưu trong bộ nhớ.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed.dart';
import '../../domain/models.dart';
import '../exercise/session_providers.dart';
import '../stats/activity.dart';

enum ReviewRating { hard, ok, easy }

/// Lịch ôn của một thẻ.
class ReviewEntry {
  const ReviewEntry({
    required this.due,
    required this.intervalDays,
    required this.ease,
    required this.reps,
  });

  final DateTime due;
  final int intervalDays;

  /// Hệ số giãn khoảng cách, tối thiểu 1.3 như SM-2.
  final double ease;

  /// Số lần đã ôn (Khó đặt lại về 0).
  final int reps;
}

const double _initialEase = 2.5;
const double _minEase = 1.3;

/// Lịch kế tiếp sau khi ôn thẻ vào ngày [today] với đánh giá [rating].
/// [prev] null = thẻ chưa ôn lần nào.
ReviewEntry scheduleNext(
  ReviewEntry? prev,
  ReviewRating rating,
  DateTime today,
) {
  final ease = prev?.ease ?? _initialEase;
  final reps = prev?.reps ?? 0;
  final interval = prev?.intervalDays ?? 0;

  final (int nextInterval, double nextEase, int nextReps) = switch (rating) {
    ReviewRating.hard => (1, (ease - 0.2).clamp(_minEase, 5.0), 0),
    ReviewRating.ok => (
      reps == 0 ? 1 : (reps == 1 ? 3 : (interval * ease).round()),
      ease,
      reps + 1,
    ),
    ReviewRating.easy => (
      reps == 0 ? 3 : (interval * ease * 1.3).round(),
      ease + 0.15,
      reps + 1,
    ),
  };

  return ReviewEntry(
    due: addDays(dayOf(today), nextInterval),
    intervalDays: nextInterval,
    ease: nextEase,
    reps: nextReps,
  );
}

/// Một thẻ ôn = một block đã làm đúng.
class ReviewCard {
  const ReviewCard({required this.exercise, required this.blockIndex});

  final Exercise exercise;
  final int blockIndex;

  Block get block => exercise.blocks[blockIndex];
  String get id => block.id;
}

class ReviewController extends Notifier<Map<String, ReviewEntry>> {
  @override
  Map<String, ReviewEntry> build() {
    final today = dayOf(ref.read(clockProvider)());
    return {
      for (final e in seedReviewDueInDays.entries)
        e.key: ReviewEntry(
          due: addDays(today, e.value),
          intervalDays: e.value,
          ease: _initialEase,
          reps: 1,
        ),
    };
  }

  void rate(String cardId, ReviewRating rating) {
    final today = ref.read(clockProvider)();
    state = {...state, cardId: scheduleNext(state[cardId], rating, today)};
    ref.read(activityProvider.notifier).record();
  }
}

final reviewScheduleProvider =
    NotifierProvider<ReviewController, Map<String, ReviewEntry>>(
      ReviewController.new,
    );

/// Mọi thẻ hiện có: các block đã xong của từng exercise.
final reviewCardsProvider = Provider<List<ReviewCard>>((ref) {
  final progress = ref.watch(progressProvider);
  return [
    for (final exercise in uniqueExercises())
      for (
        var i = 0;
        i <
            (progress[exercise.id]?.completedBlocks ?? 0).clamp(
              0,
              exercise.blocks.length,
            );
        i++
      )
        ReviewCard(exercise: exercise, blockIndex: i),
  ];
});

/// Thẻ kèm ngày đến hạn; thẻ chưa có lịch coi như đến hạn hôm nay.
typedef ScheduledCard = ({ReviewCard card, DateTime due});

List<ScheduledCard> _scheduled(Ref ref) {
  final cards = ref.watch(reviewCardsProvider);
  final schedule = ref.watch(reviewScheduleProvider);
  final today = dayOf(ref.read(clockProvider)());
  final list = [
    for (final card in cards)
      (card: card, due: schedule[card.id]?.due ?? today),
  ];
  list.sort((a, b) => a.due.compareTo(b.due));
  return list;
}

/// Thẻ đến hạn (hôm nay hoặc quá hạn), quá hạn lâu nhất trước.
final dueCardsProvider = Provider<List<ScheduledCard>>((ref) {
  final today = dayOf(ref.read(clockProvider)());
  return [
    for (final s in _scheduled(ref))
      if (!s.due.isAfter(today)) s,
  ];
});

/// Thẻ chưa đến hạn, gần nhất trước.
final upcomingCardsProvider = Provider<List<ScheduledCard>>((ref) {
  final today = dayOf(ref.read(clockProvider)());
  return [
    for (final s in _scheduled(ref))
      if (s.due.isAfter(today)) s,
  ];
});

/// Đáp án của block dạng "điền chỗ trống": ẩn từ vựng dài nhất có trong đáp
/// án. Trả về null nếu không có từ nào để ẩn.
({String masked, String missing})? fillBlank(Block block) {
  final answer = block.acceptedAnswers.first;
  final words = [...block.vocab]..sort((a, b) => b.length.compareTo(a.length));
  for (final word in words) {
    final match = RegExp('\\b${RegExp.escape(word)}\\b').firstMatch(answer);
    if (match != null) {
      return (
        masked: answer.replaceRange(match.start, match.end, '____'),
        missing: word,
      );
    }
  }
  return null;
}
