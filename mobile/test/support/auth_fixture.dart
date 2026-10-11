// Phiên đăng nhập giả cho test toàn app (không mạng).
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/data/auth_repository.dart';

class FakeAuthController extends AuthController {
  FakeAuthController(this.session);
  final AuthSession? session;

  @override
  Future<AuthSession?> build() async => session;

  @override
  Future<void> logout() async => state = const AsyncData(null);

  @override
  Future<void> expire() async => state = const AsyncData(null);
}

AuthSession fakeSession({
  Set<String> roles = const {'learner'},
  bool open = false,
}) => AuthSession(
  token: open ? '' : 'fake-token',
  user: AuthUser(email: 'learner@example.com', roles: roles.toList()),
  open: open,
);

List<Override> authOverrides({
  Set<String> roles = const {'learner'},
  bool open = false,
}) => [
  authControllerProvider.overrideWith(
    () => FakeAuthController(fakeSession(roles: roles, open: open)),
  ),
];
