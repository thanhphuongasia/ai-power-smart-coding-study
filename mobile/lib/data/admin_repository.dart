/// API soạn nội dung (admin): tải, kiểm tra và lưu content.json trên server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'content_repository.dart' show apiBaseUrl;

enum AdminErrorKind { conflict, invalid, forbidden, network, server }

class AdminError implements Exception {
  const AdminError(
    this.kind, [
    this.errors = const [],
    this.message,
    this.detail,
  ]);

  final AdminErrorKind kind;

  /// Mã lỗi máy đọc của server (`version_conflict`, `item_conflict`,
  /// `dependency_missing`, `invalid`, `change_not_found`…). null nếu không có.
  final String? detail;

  /// Thông điệp hiển thị (tiếng Việt): 413 / 5xx, hoặc `message` của server
  /// ở lỗi duyệt (404/409/422).
  final String? message;

  /// Danh sách lỗi từ server (chỉ có với [AdminErrorKind.invalid]).
  final List<String> errors;

  @override
  String toString() => 'AdminError: $kind $detail $errors';
}

/// Một mục đang chờ duyệt (tóm tắt, từ GET /api/admin/content).
class PendingItem {
  const PendingItem({
    required this.id,
    required this.kind,
    required this.itemId,
    required this.action,
  });

  final int id;

  /// project | module | file | exercise
  final String kind;
  final String itemId;

  /// create | update | delete
  final String action;
}

class AdminDocument {
  const AdminDocument({
    required this.version,
    required this.content,
    this.pending = const [],
  });
  final String version;

  /// Bản NHÁP (live + các mục chờ duyệt).
  final Map<String, dynamic> content;
  final List<PendingItem> pending;
}

/// Kết quả PUT /api/admin/content.
class SaveResult {
  const SaveResult({required this.version, required this.pending});
  final String version;

  /// Số mục chờ duyệt sau lần gửi.
  final int pending;
}

/// Một thay đổi trong hàng chờ (GET /api/admin/changes).
class ContentChange {
  const ContentChange({
    required this.id,
    required this.kind,
    required this.itemId,
    required this.action,
    this.before,
    this.after,
    this.status = 'pending',
    this.author,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String kind;
  final String itemId;
  final String action;

  /// null khi action = create.
  final Map<String, dynamic>? before;

  /// null khi action = delete.
  final Map<String, dynamic>? after;
  final String status;
  final String? author;
  final String? createdAt;
  final String? updatedAt;

  factory ContentChange.fromJson(Map<String, dynamic> j) => ContentChange(
    id: j['id'] as int,
    kind: j['kind'] as String,
    itemId: j['item_id'] as String,
    action: j['action'] as String,
    before: _mapOrNull(j['before']),
    after: _mapOrNull(j['after']),
    status: (j['status'] as String?) ?? 'pending',
    author: j['author'] as String?,
    createdAt: j['created_at'] as String?,
    updatedAt: j['updated_at'] as String?,
  );
}

Map<String, dynamic>? _mapOrNull(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

/// Kết quả approve/reject.
class ChangeResult {
  const ChangeResult({
    required this.id,
    required this.status,
    required this.version,
    this.also = const [],
  });
  final int id;

  /// approved | rejected
  final String status;
  final String version;

  /// Id các mục được duyệt/bỏ kèm theo (phụ thuộc lẫn nhau).
  final List<int> also;
}

class ValidationResult {
  const ValidationResult({required this.ok, required this.errors});
  final bool ok;
  final List<String> errors;
}

class AdminRepository {
  AdminRepository(
    http.Client client, {
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 60),
  }) : _http = client,
       _baseUrl = baseUrl ?? apiBaseUrl();

  final http.Client _http;
  final Uri _baseUrl;
  final Duration timeout;

  static const _json = {'content-type': 'application/json'};

  Future<AdminDocument> load() async {
    final r = await _send(
      () => _http.get(_baseUrl.resolve('/api/admin/content')),
    );
    final body = _decode(r);
    try {
      return AdminDocument(
        version: body['version'] as String,
        content: Map<String, dynamic>.from(body['content'] as Map),
        pending: [
          for (final p in (body['pending'] as List? ?? const []))
            PendingItem(
              id: (p as Map)['id'] as int,
              kind: p['kind'] as String,
              itemId: p['item_id'] as String,
              action: p['action'] as String,
            ),
        ],
      );
    } catch (_) {
      throw const AdminError(AdminErrorKind.network);
    }
  }

  Future<ValidationResult> validate(Map<String, dynamic> content) async {
    final r = await _send(
      () => _http.post(
        _baseUrl.resolve('/api/admin/validate'),
        headers: _json,
        body: jsonEncode({'content': content}),
      ),
    );
    final body = _decode(r);
    return ValidationResult(
      ok: body['ok'] == true,
      errors: _errors(body['errors']),
    );
  }

  /// Gửi duyệt: version mới + số mục chờ. 409 → conflict, 422 → invalid(errors).
  Future<SaveResult> save(
    String baseVersion,
    Map<String, dynamic> content,
  ) async {
    final r = await _send(
      () => _http.put(
        _baseUrl.resolve('/api/admin/content'),
        headers: _json,
        body: jsonEncode({'base_version': baseVersion, 'content': content}),
      ),
    );
    final body = _decode(r);
    final version = body['version'];
    if (version is! String) throw const AdminError(AdminErrorKind.network);
    final pending = body['pending'];
    return SaveResult(version: version, pending: pending is int ? pending : 0);
  }

  /// Hàng chờ duyệt (before/after đầy đủ).
  Future<List<ContentChange>> changes() async {
    final r = await _send(
      () => _http.get(_baseUrl.resolve('/api/admin/changes')),
    );
    final body = _decode(r);
    try {
      return [
        for (final c in (body['changes'] as List))
          ContentChange.fromJson(Map<String, dynamic>.from(c as Map)),
      ];
    } catch (_) {
      throw const AdminError(AdminErrorKind.network);
    }
  }

  /// Duyệt một mục. Lỗi 404/409/422 mang `detail` + `message` của server.
  Future<ChangeResult> approve(int id) => _decide(id, 'approve');

  Future<ChangeResult> reject(int id) => _decide(id, 'reject');

  Future<ChangeResult> _decide(int id, String verb) async {
    final r = await _send(
      () => _http.post(_baseUrl.resolve('/api/admin/changes/$id/$verb')),
    );
    final body = _decode(r);
    final status = body['status'];
    final version = body['version'];
    if (body['id'] is! int || status is! String || version is! String) {
      throw const AdminError(AdminErrorKind.network);
    }
    return ChangeResult(
      id: body['id'] as int,
      status: status,
      version: version,
      also: [
        if (body['also'] is List)
          for (final a in body['also'] as List)
            if (a is int) a,
      ],
    );
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    final http.Response r;
    try {
      r = await call().timeout(timeout);
    } catch (_) {
      throw const AdminError(AdminErrorKind.network);
    }
    switch (r.statusCode) {
      case 200:
        return r;
      case 401 || 403:
        throw const AdminError(AdminErrorKind.forbidden);
      case 404:
        // Chỉ lỗi nghiệp vụ có `detail` (change_not_found) mới là lỗi server;
        // 404 trơn (sai URL/proxy) vẫn là network như trước.
        final b = _bodyOrEmpty(r);
        final d = _str(b['detail']);
        final m = _str(b['message']);
        if (d != 'change_not_found' && m == null) {
          throw const AdminError(AdminErrorKind.network);
        }
        throw AdminError(
          AdminErrorKind.server,
          const [],
          m ?? 'Không tìm thấy mục này',
          d,
        );
      case 409:
        final b = _bodyOrEmpty(r);
        throw AdminError(
          AdminErrorKind.conflict,
          _errors(b['errors']),
          _str(b['message']),
          _str(b['detail']),
        );
      case 422:
        final b = _bodyOrEmpty(r);
        final list = _errors(b['errors']);
        throw AdminError(
          AdminErrorKind.invalid,
          list.isEmpty ? const ['Server từ chối nội dung (422)'] : list,
          _str(b['message']),
          _str(b['detail']),
        );
      case 413:
        throw const AdminError(
          AdminErrorKind.server,
          [],
          'Nội dung quá lớn (giới hạn 4MB)',
        );
      default:
        if (r.statusCode >= 500) {
          throw const AdminError(AdminErrorKind.server, [], 'Lỗi máy chủ');
        }
        throw const AdminError(AdminErrorKind.network);
    }
  }

  Map<String, dynamic> _bodyOrEmpty(http.Response r) {
    try {
      return _tryDecode(r);
    } catch (_) {
      return const {};
    }
  }

  String? _str(Object? v) => v is String ? v : null;

  Map<String, dynamic> _tryDecode(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  Map<String, dynamic> _decode(http.Response r) {
    try {
      return _tryDecode(r);
    } catch (_) {
      throw const AdminError(AdminErrorKind.network);
    }
  }

  List<String> _errors(Object? raw) => [
    if (raw is List)
      for (final e in raw) e.toString(),
  ];
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(apiClientProvider)),
);
