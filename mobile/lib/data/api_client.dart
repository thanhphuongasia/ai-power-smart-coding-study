/// Client HTTP dùng chung cho các API cần đăng nhập: gắn Bearer, và khi server
/// trả 401 thì đăng xuất (AuthGate sẽ hiện màn đăng nhập).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_repository.dart';

/// Phiên hiện tại (null = chưa đăng nhập). Khởi tạo bằng restore() lúc mở app.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

final currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(authControllerProvider).value?.user,
);

/// Repository dùng client TRƠN (không qua [apiClientProvider]) để 401 của
/// login/đổi mật khẩu không bị hiểu nhầm là phiên hết hạn.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(http.Client(), prefs: SharedPreferences.getInstance),
);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() => ref.read(authRepositoryProvider).restore();

  Future<void> login(String email, String password) async {
    final session = await ref
        .read(authRepositoryProvider)
        .login(email, password);
    state = AsyncData(session);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  Future<void> changePassword(String current, String next) =>
      ref.read(authRepositoryProvider).changePassword(current, next);

  /// Server báo 401 cho token đang dùng: xoá phiên local, không gọi mạng.
  Future<void> expire() async {
    await ref.read(authRepositoryProvider).clearLocal();
    state = const AsyncData(null);
  }
}

class ApiClient extends http.BaseClient {
  ApiClient(this._ref, [http.Client? inner]) : _inner = inner ?? http.Client();

  final Ref _ref;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _ref.read(authControllerProvider).value?.token;
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    final response = await _inner.send(request);
    if (response.statusCode == 401 && token != null) {
      // Chỉ đăng xuất nếu token vừa bị từ chối vẫn là phiên hiện tại.
      if (_ref.read(authControllerProvider).value?.token == token) {
        await _ref.read(authControllerProvider.notifier).expire();
      }
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

final apiClientProvider = Provider<http.Client>((ref) {
  final client = ApiClient(ref);
  ref.onDispose(client.close);
  return client;
});
