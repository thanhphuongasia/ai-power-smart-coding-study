/// Đồng bộ tiến độ học với server: `GET /api/progress`,
/// `PUT /api/progress/{exercise_id}`, `PUT /api/progress/state`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../features/exercise/session_controller.dart' show ExerciseProgress;
import '../features/review/review_controller.dart' show ReviewEntry;
import '../features/stats/activity.dart' show dayOf;
import 'api_client.dart';
import 'content_repository.dart' show apiBaseUrl;

/// Server trả mã lỗi (hoặc body không đọc được).
class ProgressApiException implements Exception {
  const ProgressApiException(this.message);
  final String message;
  @override
  String toString() => 'ProgressApiException: $message';
}

/// Tiến độ một exercise như server lưu (chưa gắn `totalBlocks` — cái đó lấy từ
/// nội dung).
class ExerciseSnapshot {
  const ExerciseSnapshot({
    this.passed = false,
    this.drafts = const {},
    this.hintsUsed = const {},
    this.solutionViewed = const {},
  });

  final bool passed;
  final Map<String, String> drafts;
  final Map<String, int> hintsUsed;
  final Set<String> solutionViewed;
}

/// Toàn bộ tiến độ của người dùng đang đăng nhập.
class ProgressSnapshot {
  const ProgressSnapshot({
    this.exercises = const {},
    this.review = const {},
    this.activity = const {},
    this.token,
  });

  static const empty = ProgressSnapshot();

  final Map<String, ExerciseSnapshot> exercises;
  final Map<String, ReviewEntry> review;
  final Map<DateTime, int> activity;

  /// Token của phiên mà snapshot này được tải cho (null = không gắn phiên).
  final String? token;

  ProgressSnapshot forToken(String token) => ProgressSnapshot(
    exercises: exercises,
    review: review,
    activity: activity,
    token: token,
  );
}

/// Server chỉ nhận tối đa 400 ngày hoạt động; gửi 365 ngày gần nhất.
const maxSyncedActivityDays = 365;

/// Giữ [maxSyncedActivityDays] ngày mới nhất của [activity].
Map<DateTime, int> recentActivity(Map<DateTime, int> activity) {
  if (activity.length <= maxSyncedActivityDays) return activity;
  final days = activity.keys.toList()..sort();
  return {
    for (final d in days.sublist(days.length - maxSyncedActivityDays))
      d: activity[d]!,
  };
}

/// Giới hạn server cho tổng draft của một exercise.
const maxDraftBytes = 64 * 1024;

/// Draft có đẩy được lên server không (≤64KB UTF-8 tổng, không có NUL).
bool draftsPushable(Map<String, String> drafts) {
  var total = 0;
  for (final e in drafts.entries) {
    if (e.key.contains('\u0000') || e.value.contains('\u0000')) return false;
    total += utf8.encode(e.value).length;
  }
  return total <= maxDraftBytes;
}

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// JSON của lịch ôn: `{due, interval_days, ease, reps}`.
Map<String, Object> reviewEntryToJson(ReviewEntry e) => {
  'due': e.due.toIso8601String(),
  'interval_days': e.intervalDays,
  'ease': e.ease,
  'reps': e.reps,
};

/// Parse một dòng, bỏ qua dòng hỏng (server/phiên bản lệch) thay vì hỏng cả
/// snapshot.
T? _tolerant<T>(T Function() parse) {
  try {
    return parse();
  } catch (_) {
    return null;
  }
}

class ProgressApi {
  ProgressApi(
    this._http, {
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl ?? apiBaseUrl();

  final http.Client _http;
  final Uri _baseUrl;
  final Duration timeout;

  static const _json = {'content-type': 'application/json'};

  Future<ProgressSnapshot> fetch() async {
    final response = await _http
        .get(_baseUrl.resolve('/api/progress'))
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw ProgressApiException('GET /api/progress → ${response.statusCode}');
    }
    final root =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final exercises = <String, ExerciseSnapshot>{};
    for (final e in ((root['exercises'] as Map?) ?? const {}).entries) {
      final parsed = _tolerant(() {
        final m = e.value as Map;
        return ExerciseSnapshot(
          passed: m['passed'] == true,
          drafts: {
            for (final d in ((m['drafts'] as Map?) ?? const {}).entries)
              d.key as String: d.value as String,
          },
          hintsUsed: {
            for (final h in ((m['hints_used'] as Map?) ?? const {}).entries)
              h.key as String: (h.value as num).toInt(),
          },
          solutionViewed: {
            for (final s in (m['solution_viewed'] as List?) ?? const [])
              s as String,
          },
        );
      });
      if (parsed != null) exercises[e.key as String] = parsed;
    }

    final state = (root['state'] as Map?) ?? const {};
    final review = <String, ReviewEntry>{};
    for (final e in ((state['review'] as Map?) ?? const {}).entries) {
      final parsed = _tolerant(() {
        final m = e.value as Map;
        var due = DateTime.parse(m['due'] as String);
        if (due.isUtc) due = due.toLocal();
        return ReviewEntry(
          due: due,
          intervalDays: (m['interval_days'] as num).toInt(),
          ease: (m['ease'] as num).toDouble(),
          reps: (m['reps'] as num).toInt(),
        );
      });
      if (parsed != null) review[e.key as String] = parsed;
    }
    final activity = <DateTime, int>{};
    for (final e in ((state['activity'] as Map?) ?? const {}).entries) {
      final parsed = _tolerant(
        () =>
            (dayOf(DateTime.parse(e.key as String)), (e.value as num).toInt()),
      );
      if (parsed != null) activity[parsed.$1] = parsed.$2;
    }
    return ProgressSnapshot(
      exercises: exercises,
      review: review,
      activity: activity,
    );
  }

  /// Không gửi `passed`: server tự ghi khi `/run` báo pass.
  Future<void> saveExercise(String id, ExerciseProgress p) async {
    final response = await _http
        .put(
          _baseUrl.resolve('/api/progress/${Uri.encodeComponent(id)}'),
          headers: _json,
          body: jsonEncode({
            'drafts': p.drafts,
            'hints_used': p.hintsUsed,
            'solution_viewed': p.solutionViewed.toList()..sort(),
          }),
        )
        .timeout(timeout);
    _expect204(response, 'PUT /api/progress/$id');
  }

  Future<void> saveState(
    Map<String, ReviewEntry> review,
    Map<DateTime, int> activity,
  ) async {
    final response = await _http
        .put(
          _baseUrl.resolve('/api/progress/state'),
          headers: _json,
          body: jsonEncode({
            'review': {
              for (final e in review.entries) e.key: reviewEntryToJson(e.value),
            },
            'activity': {
              for (final e in recentActivity(activity).entries)
                _dayKey(e.key): e.value,
            },
          }),
        )
        .timeout(timeout);
    _expect204(response, 'PUT /api/progress/state');
  }

  void _expect204(http.Response r, String what) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ProgressApiException('$what → ${r.statusCode}');
    }
  }
}

final progressApiProvider = Provider<ProgressApi>(
  (ref) => ProgressApi(ref.watch(apiClientProvider)),
);

/// Tiến độ của phiên hiện tại: tải lại khi đổi người dùng; chưa đăng nhập →
/// rỗng. Lỗi mạng → `AsyncError` (controller coi như chưa tải được).
final progressSnapshotProvider = FutureProvider<ProgressSnapshot>((ref) async {
  final token = ref.watch(authControllerProvider.select((a) => a.value?.token));
  if (token == null) return ProgressSnapshot.empty;
  final snapshot = await ref.read(progressApiProvider).fetch();
  return snapshot.forToken(token);
});

/// Snapshot ĐÃ tải xong cho một phiên đăng nhập; null = chưa có (đang tải, lỗi,
/// hoặc chưa đăng nhập). Controller đọc cái này (đồng bộ) và chỉ đẩy lên server
/// khi nó khác null — tránh ghi đè dữ liệu server bằng state cục bộ rỗng khi
/// tải lỗi. Test override provider này bằng một snapshot dựng sẵn.
final loadedProgressProvider = Provider<ProgressSnapshot?>((ref) {
  final token = ref.watch(authControllerProvider.select((a) => a.value?.token));
  if (token == null) return null;
  final async = ref.watch(progressSnapshotProvider);
  // Đang tải/tải lại: `value` có thể còn là của phiên trước → không dùng.
  if (async.isLoading) return null;
  final snapshot = async.value;
  if (snapshot == null || snapshot.token != token) return null;
  return snapshot;
});

/// Bật/tắt đẩy tiến độ lên server. Luôn bật ở production; test widget tắt đi
/// để không còn Timer debounce treo khi test kết thúc.
final progressSyncEnabledProvider = Provider<bool>((ref) => true);

/// True nếu được phép đẩy: sync bật VÀ đã tải xong tiến độ từ server (tránh
/// ghi đè dữ liệu server bằng state cục bộ rỗng khi tải lỗi).
bool canPushProgress(Ref ref) =>
    ref.read(progressSyncEnabledProvider) &&
    ref.read(loadedProgressProvider) != null;
