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

  static String _e(String s) => Uri.encodeComponent(s);

  Future<List<SdDocSummary>> listDocs() async {
    final root = await _send(
      () => _http.get(_uri('/api/sd/docs')),
      200,
      'GET /api/sd/docs',
    );
    return [
      for (final e in (root['items'] as List? ?? const []))
        SdDocSummary.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<SdDoc> getDoc(String id) async {
    final root = await _send(
      () => _http.get(_uri('/api/sd/docs/${_e(id)}')),
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
    final root = await _send(
      () => _http.put(
        _uri('/api/sd/docs/${_e(docId)}/sections/${_e(sectionId)}/progress'),
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
    final root = await _send(
      () => _http.post(
        _uri('/api/sd/docs/${_e(docId)}/tasks/${_e(taskId)}/attempts'),
        headers: _json,
        body: jsonEncode({'answer': answer}),
      ),
      201,
      'POST attempts $docId/$taskId',
    );
    return SdAttempt.fromJson(root['attempt'] as Map<String, dynamic>);
  }

  /// Mới nhất trước.
  Future<List<SdAttempt>> listAttempts(
    String docId,
    String taskId, {
    int limit = 20,
  }) async {
    final root = await _send(
      () => _http.get(
        _uri('/api/sd/docs/${_e(docId)}/tasks/${_e(taskId)}/attempts', {
          'limit': '$limit',
        }),
      ),
      200,
      'GET attempts $docId/$taskId',
    );
    return [
      for (final e in (root['items'] as List? ?? const []))
        SdAttempt.fromJson(e as Map<String, dynamic>),
    ];
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
