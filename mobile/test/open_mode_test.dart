// ignore_for_file: depend_on_referenced_packages
/// Chế độ mở của server (AUTH_OPEN_AS): vào app không cần đăng nhập.
library;

import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_coding_study/app/auth_gate.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/data/auth_repository.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/data/progress_api.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/main.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

http.Response _json(int code, Object body) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json'},
);

class _CountingAuth extends FakeAuthController {
  _CountingAuth(super.session);
  int expires = 0;

  @override
  Future<void> expire() async {
    expires++;
    await super.expire();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'restore không token + /api/me open:true → phiên mở, không gửi Authorization',
    () async {
      final seen = <http.BaseRequest>[];
      final repo = AuthRepository(
        MockClient((req) async {
          seen.add(req);
          return _json(200, {
            'email': 'o@x.y',
            'roles': ['learner', 'admin'],
            'open': true,
          });
        }),
        baseUrl: Uri.parse('http://test'),
      );
      final s = await repo.restore();
      expect(s, isNotNull);
      expect(s!.open, isTrue);
      expect(s.token, '');
      expect(s.user.isAdmin, isTrue);
      expect(seen.single.headers.containsKey('authorization'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AuthRepository.tokenKey), isNull);
      expect(prefs.getString(AuthRepository.userKey), isNull);
    },
  );

  test('restore không token + 401 → null', () async {
    final repo = AuthRepository(
      MockClient((_) async => _json(401, {'detail': 'not_authenticated'})),
      baseUrl: Uri.parse('http://test'),
    );
    expect(await repo.restore(), isNull);
  });

  test('restore không token + open:false hoặc lỗi mạng → null', () async {
    final notOpen = AuthRepository(
      MockClient(
        (_) async => _json(200, {'email': 'a@b.c', 'roles': [], 'open': false}),
      ),
      baseUrl: Uri.parse('http://test'),
    );
    expect(await notOpen.restore(), isNull);
    final down = AuthRepository(
      MockClient((_) async => throw http.ClientException('down')),
      baseUrl: Uri.parse('http://test'),
    );
    expect(await down.restore(), isNull);
  });

  test(
    'ApiClient token rỗng: không gửi Authorization, 401 không expire',
    () async {
      final auth = _CountingAuth(fakeSession(open: true));
      final container = ProviderContainer(
        overrides: [authControllerProvider.overrideWith(() => auth)],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      http.BaseRequest? seen;
      final client = ApiClient(
        container.read(Provider((ref) => ref)),
        MockClient((req) async {
          seen = req;
          return http.Response('', 401);
        }),
      );
      final r = await client.get(Uri.parse('http://test/api/progress'));
      expect(r.statusCode, 401);
      expect(seen!.headers.containsKey('authorization'), isFalse);
      expect(auth.expires, 0);
      expect(container.read(authControllerProvider).value, isNotNull);
    },
  );

  testWidgets(
    'Home phiên mở: nhãn Chế độ mở, không đăng xuất/đổi mật khẩu, có nút admin',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      appRouter.go('/');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...contentOverrides,
            ...authOverrides(roles: {'learner', 'admin'}, open: true),
          ],
          child: const AuthGate(child: SmartCodingStudyApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-open-mode')), findsOneWidget);
      expect(find.text('Chế độ mở'), findsOneWidget);
      expect(find.byKey(const Key('account-email')), findsOneWidget);
      expect(find.byKey(const Key('account-logout')), findsNothing);
      expect(find.byKey(const Key('account-change-password')), findsNothing);
    },
  );

  test('restore token cũ + /api/me open:true → phiên mở, xoá prefs', () async {
    SharedPreferences.setMockInitialValues({
      AuthRepository.tokenKey: 'stale',
      AuthRepository.userKey: jsonEncode({'email': 'a@b.c', 'roles': []}),
    });
    final repo = AuthRepository(
      MockClient(
        (_) async => _json(200, {
          'email': 'o@x.y',
          'roles': ['learner'],
          'open': true,
        }),
      ),
      baseUrl: Uri.parse('http://test'),
    );
    final s = await repo.restore();
    expect(s, isNotNull);
    expect(s!.open, isTrue);
    expect(s.token, '');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AuthRepository.tokenKey), isNull);
    expect(prefs.getString(AuthRepository.userKey), isNull);
  });

  test('ApiClient token KHÔNG rỗng + 401 vẫn expire()', () async {
    final auth = _CountingAuth(fakeSession());
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(() => auth)],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    http.BaseRequest? seen;
    final client = ApiClient(
      container.read(Provider((ref) => ref)),
      MockClient((req) async {
        seen = req;
        return http.Response('', 401);
      }),
    );
    await client.get(Uri.parse('http://test/api/progress'));
    expect(seen!.headers['authorization'], 'Bearer fake-token');
    expect(auth.expires, 1);
    expect(container.read(authControllerProvider).value, isNull);
  });

  testWidgets('phiên mở + tải tiến độ lỗi: có Thử lại, không có Đăng xuất', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...authOverrides(open: true),
          progressSnapshotProvider.overrideWith(
            (ref) async => throw const ProgressApiException('500'),
          ),
        ],
        child: const AuthGate(child: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-load-error')), findsOneWidget);
    expect(find.byKey(const Key('progress-retry')), findsOneWidget);
    expect(find.byKey(const Key('progress-logout')), findsNothing);
  });

  test('đồng bộ tiến độ phiên mở: GET rồi PUT không có Authorization', () {
    fakeAsync((async) {
      final seen = <http.Request>[];
      final c = ProviderContainer(
        overrides: [
          contentIndexProvider.overrideWithValue(testContent),
          ...authOverrides(open: true),
          apiClientProvider.overrideWith(
            (ref) => ApiClient(
              ref,
              MockClient((req) async {
                seen.add(req);
                if (req.method == 'GET') {
                  return _json(200, {
                    'exercises': <String, Object?>{},
                    'state': {
                      'review': <String, Object?>{},
                      'activity': <String, int>{},
                    },
                  });
                }
                return http.Response('', 204);
              }),
            ),
          ),
          progressApiProvider.overrideWith(
            (ref) => ProgressApi(
              ref.watch(apiClientProvider),
              baseUrl: Uri.parse('http://t'),
            ),
          ),
          clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(progressSnapshotProvider, (_, _) {});
      c.listen(progressProvider, (_, _) {});
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(c.read(loadedProgressProvider), isNotNull);
      expect(c.read(loadedProgressProvider)!.token, '');

      c.read(progressProvider.notifier).useHint('split-chunks', 'A');
      async.flushMicrotasks();
      final puts = seen.where((r) => r.method == 'PUT').toList();
      expect(puts, isNotEmpty);
      expect(puts.first.url.path, '/api/progress/split-chunks');
      for (final r in seen) {
        expect(r.headers.containsKey('authorization'), isFalse);
      }
    });
  });
}
