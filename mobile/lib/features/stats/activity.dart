/// Nhật ký hoạt động theo ngày (block làm đúng + thẻ đã ôn) — nguồn cho
/// chuỗi ngày và heatmap ở màn Tiến độ.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed.dart';
import '../exercise/session_providers.dart';

/// Nửa đêm của ngày chứa [t] (giờ địa phương).
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Ngày cách [day] [delta] ngày; dựng lại từ y/m/d để không lệch khi đổi
/// giờ mùa hè.
DateTime addDays(DateTime day, int delta) =>
    DateTime(day.year, day.month, day.day + delta);

class ActivityController extends Notifier<Map<DateTime, int>> {
  @override
  Map<DateTime, int> build() {
    final today = dayOf(ref.read(clockProvider)());
    return {
      for (final e in seedActivityDaysAgo.entries)
        addDays(today, -e.key): e.value,
    };
  }

  /// Ghi thêm 1 hoạt động vào hôm nay.
  void record() {
    final today = dayOf(ref.read(clockProvider)());
    state = {...state, today: (state[today] ?? 0) + 1};
  }
}

final activityProvider =
    NotifierProvider<ActivityController, Map<DateTime, int>>(
      ActivityController.new,
    );

/// Số ngày liên tiếp có hoạt động tính tới hôm nay. Hôm nay chưa làm gì thì
/// chuỗi vẫn giữ nếu hôm qua có làm (đếm từ hôm qua).
int currentStreak(Map<DateTime, int> activity, DateTime today) {
  var day = dayOf(today);
  if ((activity[day] ?? 0) == 0) day = addDays(day, -1);
  var streak = 0;
  while ((activity[day] ?? 0) > 0) {
    streak++;
    day = addDays(day, -1);
  }
  return streak;
}
