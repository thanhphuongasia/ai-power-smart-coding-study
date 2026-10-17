/// API chế độ System Design: `/api/sd/docs...`. Cần đăng nhập — client là
/// [apiClientProvider] (đã gắn Bearer); chưa đăng nhập server trả 401.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../domain/sd_models.dart';
import 'api_client.dart';
import 'content_repository.dart' show apiBaseUrl;

/// Server trả mã lỗi. [detail] lấy từ body `{"detail": "..."}` nếu có, vd
/// `section_locked`, `task_locked`, `attempt_limit`.
class SdApiException implements Exception {
  const SdApiException(this.statusCode, this.detail);
  final int statusCode;
  final String? detail;
  @override
  String toString() => 'SdApiException($statusCode, $detail)';
}

/// Lỗi có thể ném ra từ MỌI hàm của lớp này (người gọi phải bắt rộng, cùng hợp
/// đồng với ProgressApi):
/// - [SdApiException]: server trả status không như mong đợi;
/// - [FormatException]: JSON sai hình dạng (kể cả `items`/`attempt` sai kiểu);
/// - lỗi mạng/timeout thô: `TimeoutException`, `SocketException`,
///   `http.ClientException` — KHÔNG được bọc lại.
/// Ngoài ra id (docId, sectionId, taskId) rỗng, '.' hoặc '..' bị từ chối ngay
/// bằng [ArgumentError], không gửi request nào.
class SdRepository {
  SdRepository(
    this._http, {
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl ?? apiBaseUrl();

  final http.Client _http;
  final Uri _baseUrl;
  final Duration timeout;

  static const _json = {'content-type': 'application/json'};

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = _baseUrl.resolve(path);
    return query == null ? u : u.replace(queryParameters: query);
  }

  /// Mã hoá id để ghép vào path. `Uri.encodeComponent` không mã hoá dấu chấm và
  /// `Uri.resolve` chuẩn hoá '..' → path trượt lên cấp trên; nên chặn từ đầu.
  static String _e(String name, String id) {
    if (id.isEmpty || id == '.' || id == '..') {
      throw ArgumentError.value(id, name, 'id không hợp lệ cho path');
    }
    return Uri.encodeComponent(id);
  }

  /// Đọc `items` thành list object. Thiếu/null → rỗng; sai kiểu → FormatException.
  static List<Map<String, dynamic>> _items(
    Map<String, dynamic> root,
    String what,
  ) {
    final raw = root['items'];
    if (raw == null) return const [];
    if (raw is! List) throw FormatException('$what: "items" không phải list');
    return [
      for (var i = 0; i < raw.length; i++)
        switch (raw[i]) {
          final Map<String, dynamic> m => m,
          _ => throw FormatException('$what: items[$i] không phải object'),
        },
    ];
  }

  Future<List<SdDocSummary>> listDocs() async {
    const what = 'GET /api/sd/docs';
    final root = await _send(() => _http.get(_uri('/api/sd/docs')), 200, what);
    // Server cũ không gửi `courses`/`course_id` → không course, list phẳng.
    // Course chỉ là thông tin nhóm: dữ liệu lệch thì bỏ qua, không làm lỗi cả list.
    final rawCourses = root['courses'];
    final byId = <String, SdCourse>{};
    if (rawCourses is List) {
      for (final c in rawCourses) {
        final course = SdCourse.tryFromJson(c);
        if (course != null) byId[course.id] = course;
      }
    }
    return [
      for (final e in _items(root, what))
        () {
          final d = SdDocSummary.fromJson(e);
          return d.courseId == null ? d : d.withCourse(byId[d.courseId]);
        }(),
    ];
  }

  Future<SdDoc> getDoc(String id) async {
    final doc = _e('docId', id);
    final root = await _send(
      () => _http.get(_uri('/api/sd/docs/$doc')),
      200,
      'GET /api/sd/docs/$id',
    );
    return SdDoc.fromJson(root);
  }

  /// Gửi toàn bộ id thẻ đã đọc của section (server lấy hợp, không bớt).
  Future<SdProgressResult> putProgress(
    String docId,
    String sectionId,
    List<String> readCards,
  ) async {
    final doc = _e('docId', docId);
    final section = _e('sectionId', sectionId);
    final root = await _send(
      () => _http.put(
        _uri('/api/sd/docs/$doc/sections/$section/progress'),
        headers: _json,
        body: jsonEncode({'read_cards': readCards}),
      ),
      200,
      'PUT progress $docId/$sectionId',
    );
    return SdProgressResult.fromJson(root);
  }

  Future<SdAttempt> submitAttempt(
    String docId,
    String taskId,
    String answer,
  ) async {
    final doc = _e('docId', docId);
    final task = _e('taskId', taskId);
    final root = await _send(
      () => _http.post(
        _uri('/api/sd/docs/$doc/tasks/$task/attempts'),
        headers: _json,
        body: jsonEncode({'answer': answer}),
      ),
      201,
      'POST attempts $docId/$taskId',
    );
    final attempt = root['attempt'];
    if (attempt is! Map<String, dynamic>) {
      throw const FormatException('POST attempts: "attempt" không phải object');
    }
    return SdAttempt.fromJson(attempt);
  }

  /// Mới nhất trước.
  Future<List<SdAttempt>> listAttempts(
    String docId,
    String taskId, {
    int limit = 20,
  }) async {
    final doc = _e('docId', docId);
    final task = _e('taskId', taskId);
    const what = 'GET attempts';
    final root = await _send(
      () => _http.get(
        _uri('/api/sd/docs/$doc/tasks/$task/attempts', {'limit': '$limit'}),
      ),
      200,
      '$what $docId/$taskId',
    );
    return [for (final e in _items(root, what)) SdAttempt.fromJson(e)];
  }

  /// Gọi [call] với timeout, kiểm status, trả body JSON object. Body hỏng ở
  /// status thành công → FormatException (không nuốt).
  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() call,
    int expected,
    String what,
  ) async {
    final response = await call().timeout(timeout);
    if (response.statusCode != expected) {
      throw SdApiException(response.statusCode, _detailOf(response));
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw FormatException('$what: body không phải object');
    }
    return body;
  }

  /// `detail` chỉ nhận khi là chuỗi (422 của FastAPI trả list → bỏ qua).
  static String? _detailOf(http.Response r) {
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {}
    return null;
  }
}

final sdRepositoryProvider = Provider<SdRepository>(
  (ref) => SdRepository(ref.watch(apiClientProvider)),
);

/// Riverpod 3 mặc định thử lại ngầm lỗi `Exception` (tới 10 lần, backoff) và trong lúc đó trạng thái vẫn
/// là "đang tải": 401/404/5xx của server sẽ làm màn hình quay mãi thay vì báo lỗi. Lỗi HTTP từ server
/// (`SdApiException`) hiện ngay để người dùng bấm "Thử lại"; lỗi mạng/timeout vẫn theo retry mặc định.
Duration? sdRetry(int retryCount, Object error) => error is SdApiException
    ? null
    : ProviderContainer.defaultRetry(retryCount, error);

final sdDocsProvider = FutureProvider.autoDispose<List<SdDocSummary>>(
  (ref) => ref.watch(sdRepositoryProvider).listDocs(),
  retry: sdRetry,
);

final sdDocProvider = FutureProvider.autoDispose.family<SdDoc, String>(
  (ref, id) => ref.watch(sdRepositoryProvider).getDoc(id),
  retry: sdRetry,
);
