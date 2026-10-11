// Tiến độ DEMO cho test (trước đây là demo_seed.dart trong lib/). Production
// lấy tiến độ từ server; test cần dữ liệu có sẵn thì dùng demoProgressOverrides.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/data/progress_api.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/review/review_controller.dart';
import 'package:smart_coding_study/features/stats/activity.dart';

/// Bài đã chạy đúng toàn bộ unit test khi mở app.
final Set<String> seedPassedExercises = {'clean-text'};

/// Nháp có sẵn: exerciseId → (nhãn ô → code đã gõ). split-chunks đang làm dở.
final Map<String, Map<String, String>> seedDrafts = {
  'split-chunks': {'A': 'for i in range(0, len(text), size):'},
};

/// Hoạt động 4 tuần gần nhất, theo số ngày trước hôm nay. Chuỗi hiện tại: 6
/// ngày liên tiếp tới hôm qua.
final Map<int, int> seedActivityDaysAgo = {
  1: 3,
  2: 2,
  3: 4,
  4: 1,
  5: 2,
  6: 3,
  8: 2,
  9: 1,
  11: 3,
  12: 4,
  13: 2,
  15: 1,
  16: 2,
  18: 3,
  20: 1,
  22: 2,
  23: 4,
  25: 1,
  26: 2,
  27: 1,
};

/// Lịch ôn có sẵn cho vài block đã xong, theo số ngày tính từ hôm nay.
final Map<String, int> seedReviewDueInDays = {'clean-text-a': 1};

/// Snapshot demo, tính ngày theo [today].
ProgressSnapshot demoProgressSnapshot(DateTime today) {
  final day = dayOf(today);
  return ProgressSnapshot(
    exercises: {
      for (final id in {...seedPassedExercises, ...seedDrafts.keys})
        id: ExerciseSnapshot(
          passed: seedPassedExercises.contains(id),
          drafts: Map.of(seedDrafts[id] ?? const {}),
        ),
    },
    review: {
      for (final e in seedReviewDueInDays.entries)
        e.key: ReviewEntry(
          due: addDays(day, e.value),
          intervalDays: e.value,
          ease: 2.5,
          reps: 1,
        ),
    },
    activity: {
      for (final e in seedActivityDaysAgo.entries)
        addDays(day, -e.key): e.value,
    },
  );
}

/// Override mặc định cho test cần tiến độ demo: snapshot đã tải (theo
/// `clockProvider` của scope). Đẩy lên server TẮT (không mạng, không Timer
/// debounce treo cuối test); test đồng bộ tự bật lại, xem progress_sync_test.
List<Override> demoProgressOverrides() => [
  loadedProgressProvider.overrideWith(
    (ref) => demoProgressSnapshot(ref.read(clockProvider)()),
  ),
  // AuthGate chờ snapshot của ĐÚNG phiên: trả snapshot demo gắn token hiện tại.
  progressSnapshotProvider.overrideWith((ref) async {
    final token = ref.watch(
      authControllerProvider.select((a) => a.value?.token),
    );
    if (token == null) return ProgressSnapshot.empty;
    return demoProgressSnapshot(ref.read(clockProvider)()).forToken(token);
  }),
  progressSyncEnabledProvider.overrideWithValue(false),
];
