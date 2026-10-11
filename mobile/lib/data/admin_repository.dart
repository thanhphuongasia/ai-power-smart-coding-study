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
  const AdminError(this.kind, [this.errors = const [], this.message]);

  final AdminErrorKind kind;

  /// Thông điệp hiển thị cho [AdminErrorKind.server] (413 / 5xx).
  final String? message;

  /// Danh sách lỗi từ server (chỉ có với [AdminErrorKind.invalid]).
  final List<String> errors;

  @override
  String toString() => 'AdminError: $kind $errors';
}

class AdminDocument {
  const AdminDocument({required this.version, required this.content});
  final String version;
  final Map<String, dynamic> content;
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

  /// Trả về version mới. 409 → conflict, 422 → invalid(errors).
  Future<String> save(String baseVersion, Map<String, dynamic> content) async {
    final r = await _send(
      () => _http.put(
        _baseUrl.resolve('/api/admin/content'),
        headers: _json,
        body: jsonEncode({'base_version': baseVersion, 'content': content}),
      ),
    );
    final version = _decode(r)['version'];
    if (version is! String) throw const AdminError(AdminErrorKind.network);
    return version;
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
      case 409:
        throw const AdminError(AdminErrorKind.conflict);
      case 422:
        Object? errors;
        try {
          errors = _tryDecode(r)['errors'];
        } catch (_) {}
        final list = _errors(errors);
        throw AdminError(
          AdminErrorKind.invalid,
          list.isEmpty ? const ['Server từ chối nội dung (422)'] : list,
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
