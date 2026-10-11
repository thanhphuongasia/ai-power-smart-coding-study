/// Đăng nhập email + mật khẩu, token Bearer lưu trong SharedPreferences.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'content_repository.dart' show apiBaseUrl;

class AuthUser {
  const AuthUser({required this.email, required this.roles});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    email: json['email'] as String,
    roles: [for (final r in json['roles'] as List) r as String],
  );

  final String email;
  final List<String> roles;

  bool get isAdmin => roles.contains('admin');

  Map<String, dynamic> toJson() => {'email': email, 'roles': roles};
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
    this.open = false,
  });
  final String token;
  final AuthUser user;

  /// Server chạy chế độ mở: không cần token, [token] rỗng, không lưu prefs.
  final bool open;
}

enum AuthErrorKind {
  invalidCredentials,
  tooManyAttempts,
  wrongPassword,
  weakPassword,
  sessionExpired,
  network,
}

class AuthError implements Exception {
  const AuthError(this.kind);
  final AuthErrorKind kind;

  @override
  String toString() => 'AuthError: $kind';
}

class AuthRepository {
  AuthRepository(
    http.Client client, {
    Future<SharedPreferences> Function()? prefs,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 8),
  }) : _http = client,
       _prefs = prefs ?? SharedPreferences.getInstance,
       _baseUrl = baseUrl ?? apiBaseUrl();

  static const tokenKey = 'auth.token';
  static const userKey = 'auth.user';

  final http.Client _http;
  final Future<SharedPreferences> Function() _prefs;
  final Uri _baseUrl;
  final Duration timeout;

  Map<String, String> _bearer(String token) => {
    'authorization': 'Bearer $token',
  };

  /// Khôi phục phiên: 401 → xoá và trả null; lỗi mạng → dùng bản đã lưu.
  Future<AuthSession?> restore() async {
    final prefs = await _prefs();
    final token = prefs.getString(tokenKey);
    if (token == null) return _restoreOpen();
    final cached = _readCachedUser(prefs);
    try {
      final r = await _http
          .get(_baseUrl.resolve('/api/me'), headers: _bearer(token))
          .timeout(timeout);
      if (r.statusCode == 401) {
        await clearLocal();
        return null;
      }
      if (r.statusCode == 200) {
        final json =
            jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final user = AuthUser.fromJson(json);
        if (json['open'] == true) {
          // Token cũ không còn ý nghĩa: server đang mở, vào bằng phiên mở.
          await clearLocal();
          return AuthSession(token: '', user: user, open: true);
        }
        await prefs.setString(userKey, jsonEncode(user.toJson()));
        return AuthSession(token: token, user: user);
      }
    } catch (_) {
      // mạng hỏng / phản hồi lạ: rơi xuống bản đã lưu
    }
    return cached == null ? null : AuthSession(token: token, user: cached);
  }

  /// Không có token đã lưu: hỏi /api/me không kèm Authorization. Chỉ khi server
  /// báo `open: true` mới vào thẳng; mọi trường hợp khác → null (màn đăng nhập).
  Future<AuthSession?> _restoreOpen() async {
    try {
      final r = await _http.get(_baseUrl.resolve('/api/me')).timeout(timeout);
      if (r.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (json['open'] != true) return null;
      return AuthSession(token: '', user: AuthUser.fromJson(json), open: true);
    } catch (_) {
      return null;
    }
  }

  AuthUser? _readCachedUser(SharedPreferences prefs) {
    final raw = prefs.getString(userKey);
    if (raw == null) return null;
    try {
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<AuthSession> login(String email, String password) async {
    final http.Response r;
    try {
      r = await _http
          .post(
            _baseUrl.resolve('/api/auth/login'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(timeout);
    } catch (_) {
      throw const AuthError(AuthErrorKind.network);
    }
    if (r.statusCode == 401) {
      throw const AuthError(AuthErrorKind.invalidCredentials);
    }
    if (r.statusCode == 429) {
      throw const AuthError(AuthErrorKind.tooManyAttempts);
    }
    if (r.statusCode != 200) throw const AuthError(AuthErrorKind.network);
    final AuthSession session;
    try {
      final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      session = AuthSession(
        token: json['token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
    } catch (_) {
      throw const AuthError(AuthErrorKind.network);
    }
    final prefs = await _prefs();
    await prefs.setString(tokenKey, session.token);
    await prefs.setString(userKey, jsonEncode(session.user.toJson()));
    return session;
  }

  /// Best-effort gọi server, luôn xoá dữ liệu local.
  Future<void> logout() async {
    try {
      final token = (await _prefs()).getString(tokenKey);
      if (token != null) {
        await _http
            .post(_baseUrl.resolve('/api/auth/logout'), headers: _bearer(token))
            .timeout(timeout);
      }
    } catch (_) {
      // bỏ qua: đăng xuất local vẫn phải xong
    }
    await clearLocal();
  }

  Future<void> clearLocal() async {
    final prefs = await _prefs();
    await prefs.remove(tokenKey);
    await prefs.remove(userKey);
  }

  Future<void> changePassword(String current, String next) async {
    final token = (await _prefs()).getString(tokenKey);
    if (token == null) throw const AuthError(AuthErrorKind.sessionExpired);
    final http.Response r;
    try {
      r = await _http
          .post(
            _baseUrl.resolve('/api/auth/password'),
            headers: {..._bearer(token), 'content-type': 'application/json'},
            body: jsonEncode({
              'current_password': current,
              'new_password': next,
            }),
          )
          .timeout(timeout);
    } catch (_) {
      throw const AuthError(AuthErrorKind.network);
    }
    if (r.statusCode == 204 || r.statusCode == 200) return;
    if (r.statusCode == 400) throw const AuthError(AuthErrorKind.weakPassword);
    if (r.statusCode == 401) {
      switch (_detail(r)) {
        case 'wrong_password':
          throw const AuthError(AuthErrorKind.wrongPassword);
        case 'not_authenticated':
          throw const AuthError(AuthErrorKind.sessionExpired);
      }
    }
    if (r.statusCode == 429) {
      throw const AuthError(AuthErrorKind.tooManyAttempts);
    }
    throw const AuthError(AuthErrorKind.network);
  }

  /// Giá trị `detail` trong body lỗi của server; null nếu body không đọc được.
  static String? _detail(http.Response r) {
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      final detail = body is Map ? body['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }
}
