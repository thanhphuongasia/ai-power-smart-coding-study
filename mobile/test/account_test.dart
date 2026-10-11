/// Test tài khoản: nút admin theo vai trò, menu tài khoản trên Home (email,
/// đăng xuất), và màn đổi mật khẩu (validation, lỗi server, thành công).
/// Chạy qua app thật (appRouter) với auth giả — không có mạng.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_coding_study/app/auth_gate.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/data/auth_repository.dart';
import 'package:smart_coding_study/main.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

/// Auth giả ghi lại lệnh gọi; lỗi đổi mật khẩu lấy từ [_changeError].
class _RecordingAuth extends FakeAuthController {
  _RecordingAuth(super.session);

  @override
  Future<void> logout() async {
    _logouts++;
    await super.logout();
  }

  @override
  Future<void> login(String email, String password) async => _logins++;

  @override
  Future<void> changePassword(String current, String next) async {
    _changes.add((current, next));
    // Đi qua logic thật của AuthController (sessionExpired → expire()).
    await super.changePassword(current, next);
  }
}

/// Repo giả: chỉ changePassword, ném lỗi đặt trong [_changeError].
class _FakeRepo extends AuthRepository {
  _FakeRepo() : super(http.Client());

  @override
  Future<void> changePassword(String current, String next) async {
    final error = _changeError;
    if (error != null) throw error;
  }
}

int _logouts = 0;
int _logins = 0;
final List<(String, String)> _changes = [];
AuthError? _changeError;

Future<void> _pumpApp(
  WidgetTester tester, {
  Set<String> roles = const {'learner'},
  String location = '/',
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _logouts = 0;
  _logins = 0;
  _changes.clear();
  _changeError = null;
  appRouter.go(location);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...contentOverrides,
        authRepositoryProvider.overrideWithValue(_FakeRepo()),
        authControllerProvider.overrideWith(
          () => _RecordingAuth(fakeSession(roles: roles)),
        ),
      ],
      // Giống main.dart: AuthGate bọc app, nên logout đưa về LoginScreen.
      child: const AuthGate(child: SmartCodingStudyApp()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAccountMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('account-button')));
  await tester.pumpAndSettle();
}

/// Home → nút tài khoản → "Đổi mật khẩu" (không mở thẳng route).
Future<void> _openChangePassword(WidgetTester tester) async {
  await _pumpApp(tester);
  await _openAccountMenu(tester);
  await tester.tap(find.byKey(const Key('account-change-password')));
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmit(
  WidgetTester tester, {
  String current = 'old-pass',
  String next = 'new-pass-1234',
  String? confirm,
}) async {
  await tester.enterText(find.byKey(const Key('cp-current')), current);
  await tester.enterText(find.byKey(const Key('cp-new')), next);
  await tester.enterText(find.byKey(const Key('cp-confirm')), confirm ?? next);
  await tester.tap(find.byKey(const Key('cp-submit')));
  await tester.pumpAndSettle();
}

Future<void> _failWith(
  WidgetTester tester,
  AuthErrorKind kind,
  String message,
) async {
  await _openChangePassword(tester);
  _changeError = AuthError(kind);
  await _fillAndSubmit(tester);
  expect(_changes, [('old-pass', 'new-pass-1234')]);
  expect(find.text(message), findsOneWidget);
  expect(find.byKey(const Key('change-password-screen')), findsOneWidget);
}

void main() {
  testWidgets('learner không thấy nút admin trên Home', (tester) async {
    await _pumpApp(tester);

    expect(find.byKey(const Key('account-button')), findsOneWidget);
    expect(find.byKey(const Key('admin-button')), findsNothing);
  });

  testWidgets('admin thấy nút admin trên Home', (tester) async {
    await _pumpApp(tester, roles: const {'learner', 'admin'});

    expect(find.byKey(const Key('admin-button')), findsOneWidget);
  });

  testWidgets('menu tài khoản hiện email của người dùng hiện tại', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openAccountMenu(tester);

    expect(find.byKey(const Key('account-email')), findsOneWidget);
    expect(find.text('learner@example.com'), findsOneWidget);
    expect(find.byKey(const Key('account-change-password')), findsOneWidget);
    expect(find.byKey(const Key('account-logout')), findsOneWidget);
  });

  testWidgets('đăng xuất gọi controller và đưa về màn đăng nhập', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openAccountMenu(tester);

    await tester.tap(find.byKey(const Key('account-logout')));
    await tester.pumpAndSettle();

    expect(_logouts, 1);
    expect(find.byKey(const Key('login-screen')), findsOneWidget);
  });

  testWidgets('đăng nhập bỏ trống email/mật khẩu: báo lỗi, không gọi login', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openAccountMenu(tester);
    await tester.tap(find.byKey(const Key('account-logout')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập email và mật khẩu'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập email và mật khẩu'), findsOneWidget);
    expect(_logins, 0);
  });

  testWidgets('menu → Đổi mật khẩu mở màn /account/password', (tester) async {
    await _pumpApp(tester);
    await _openAccountMenu(tester);

    await tester.tap(find.byKey(const Key('account-change-password')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('change-password-screen')), findsOneWidget);
  });

  testWidgets('đổi mật khẩu: bỏ trống mật khẩu hiện tại thì báo lỗi', (
    tester,
  ) async {
    await _openChangePassword(tester);

    await tester.tap(find.byKey(const Key('cp-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Nhập mật khẩu hiện tại.'), findsOneWidget);
    expect(_changes, isEmpty);
  });

  testWidgets('đổi mật khẩu: mật khẩu mới dưới 10 ký tự thì báo lỗi', (
    tester,
  ) async {
    await _openChangePassword(tester);

    await _fillAndSubmit(tester, next: 'short');

    expect(find.text('Mật khẩu mới phải có ít nhất 10 ký tự.'), findsOneWidget);
    expect(_changes, isEmpty);
  });

  testWidgets('đổi mật khẩu: xác nhận không khớp thì báo lỗi', (tester) async {
    await _openChangePassword(tester);

    await _fillAndSubmit(tester, confirm: 'new-pass-9999');

    expect(find.text('Xác nhận mật khẩu không khớp.'), findsOneWidget);
    expect(_changes, isEmpty);
  });

  testWidgets('đổi mật khẩu: server báo sai mật khẩu hiện tại', (tester) async {
    await _failWith(
      tester,
      AuthErrorKind.wrongPassword,
      'Mật khẩu hiện tại không đúng.',
    );
  });

  testWidgets('đổi mật khẩu: server báo mật khẩu mới yếu', (tester) async {
    await _failWith(
      tester,
      AuthErrorKind.weakPassword,
      'Mật khẩu mới chưa đạt yêu cầu. Hãy chọn mật khẩu khác.',
    );
  });

  testWidgets('đổi mật khẩu: lỗi mạng', (tester) async {
    await _failWith(
      tester,
      AuthErrorKind.network,
      'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
    );
  });

  testWidgets('đổi mật khẩu: thử quá nhiều lần', (tester) async {
    await _failWith(
      tester,
      AuthErrorKind.tooManyAttempts,
      'Thử quá nhiều lần. Hãy đợi một lúc rồi thử lại.',
    );
  });

  testWidgets('đổi mật khẩu: phiên hết hạn thì về màn đăng nhập', (
    tester,
  ) async {
    await _openChangePassword(tester);
    _changeError = const AuthError(AuthErrorKind.sessionExpired);

    await _fillAndSubmit(tester);

    expect(_changes, [('old-pass', 'new-pass-1234')]);
    expect(find.byKey(const Key('login-screen')), findsOneWidget);
    expect(find.byKey(const Key('change-password-screen')), findsNothing);
  });

  testWidgets('đổi mật khẩu thành công: báo và đóng màn', (tester) async {
    await _openChangePassword(tester);

    await _fillAndSubmit(tester);

    expect(_changes, [('old-pass', 'new-pass-1234')]);
    expect(find.text('Đã đổi mật khẩu.'), findsOneWidget);
    expect(find.byKey(const Key('change-password-screen')), findsNothing);
    expect(find.byKey(const Key('account-button')), findsOneWidget);
  });
}
