import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_coding_study/app/auth_gate.dart';
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/data/auth_repository.dart';

const _appKey = Key('app-body');

class _Server {
  int loginStatus = 200;
  int apiStatus = 200;
  int meStatus = 200;

  Future<http.Response> handle(http.Request req) async {
    switch (req.url.path) {
      case '/api/auth/login':
        if (loginStatus != 200) return http.Response('{}', loginStatus);
        return http.Response(
          jsonEncode({
            'token': 'tok-1',
            'user': {
              'email': 'a@b.c',
              'roles': ['learner'],
            },
          }),
          200,
        );
      case '/api/me':
        return http.Response(
          jsonEncode({
            'email': 'a@b.c',
            'roles': ['learner'],
          }),
          meStatus,
        );
      default:
        return http.Response('{}', apiStatus);
    }
  }
}

Widget _app(_Server server) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(
      AuthRepository(
        MockClient(server.handle),
        prefs: SharedPreferences.getInstance,
        baseUrl: Uri.parse('http://test'),
      ),
    ),
  ],
  child: const AuthGate(
    child: MaterialApp(
      home: Scaffold(body: Text('APP', key: _appKey)),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('không token → màn đăng nhập', (tester) async {
    await tester.pumpWidget(_app(_Server()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-screen')), findsOneWidget);
    expect(find.byKey(_appKey), findsNothing);
  });

  testWidgets('sai mật khẩu hiện lỗi; đăng nhập đúng vào app', (tester) async {
    final server = _Server()..loginStatus = 401;
    await tester.pumpWidget(_app(server));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-email')), 'a@b.c');
    await tester.enterText(find.byKey(const Key('login-password')), 'bad');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);
    expect(find.byKey(_appKey), findsNothing);

    server.loginStatus = 429;
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('quá nhiều lần'), findsOneWidget);

    server.loginStatus = 200;
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);
    expect(find.byKey(const Key('login-screen')), findsNothing);
  });

  testWidgets('có token hợp lệ → thẳng vào app', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'tok-1',
      'auth.user': jsonEncode({'email': 'a@b.c', 'roles': []}),
    });
    await tester.pumpWidget(_app(_Server()));
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);
  });

  testWidgets('401 từ apiClient → đăng xuất, hiện đăng nhập', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'tok-1',
      'auth.user': jsonEncode({'email': 'a@b.c', 'roles': []}),
    });
    final server = _Server();
    await tester.pumpWidget(_app(server));
    await tester.pumpAndSettle();
    expect(find.byKey(_appKey), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(_appKey)),
    );
    // apiClient dùng client thật bên trong: thay bằng MockClient qua ApiClient.
    final api = ApiClient(
      container.read(_refProvider),
      MockClient((req) async {
        expect(req.headers['authorization'], 'Bearer tok-1');
        return http.Response('{}', 401);
      }),
    );
    await tester.runAsync(() => api.get(Uri.parse('http://test/progress')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-screen')), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('auth.token'),
      isNull,
    );
  });
}

final _refProvider = Provider<Ref>((ref) => ref);
