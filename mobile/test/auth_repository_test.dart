import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_coding_study/data/auth_repository.dart';

AuthRepository repoWith(MockClientHandler h) => AuthRepository(
  MockClient(h),
  prefs: SharedPreferences.getInstance,
  baseUrl: Uri.parse('http://test'),
);

http.Response json(int code, Object body) => http.Response(
  jsonEncode(body),
  code,
  headers: {'content-type': 'application/json'},
);

final okLogin = {
  'token': 'tok-1',
  'user': {
    'email': 'a@b.c',
    'roles': ['learner', 'admin'],
  },
};

Future<AuthErrorKind> kindOf(Future<void> Function() f) async {
  try {
    await f();
  } on AuthError catch (e) {
    return e.kind;
  }
  throw StateError('không ném AuthError');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('login lưu token + user, gửi đúng body', () async {
    late http.Request seen;
    final repo = repoWith((req) async {
      seen = req;
      return json(200, okLogin);
    });
    final s = await repo.login('a@b.c', 'pw');
    expect(s.token, 'tok-1');
    expect(s.user.isAdmin, isTrue);
    expect(seen.url.path, '/api/auth/login');
    expect(jsonDecode(seen.body), {'email': 'a@b.c', 'password': 'pw'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth.token'), 'tok-1');
    expect(prefs.getString('auth.user'), contains('a@b.c'));
  });

  test('login: 401, 429, 500, lỗi mạng', () async {
    expect(
      await kindOf(
        () => repoWith(
          (_) async => json(401, {'detail': 'invalid_credentials'}),
        ).login('a', 'b'),
      ),
      AuthErrorKind.invalidCredentials,
    );
    expect(
      await kindOf(
        () => repoWith(
          (_) async => json(429, {'detail': 'too_many_attempts'}),
        ).login('a', 'b'),
      ),
      AuthErrorKind.tooManyAttempts,
    );
    expect(
      await kindOf(
        () => repoWith((_) async => http.Response('x', 500)).login('a', 'b'),
      ),
      AuthErrorKind.network,
    );
    expect(
      await kindOf(
        () => repoWith(
          (_) async => throw http.ClientException('down'),
        ).login('a', 'b'),
      ),
      AuthErrorKind.network,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('auth.token'),
      isNull,
    );
  });

  test('restore: không token → null, không gọi mạng', () async {
    final repo = repoWith((_) async => fail('không được gọi mạng'));
    expect(await repo.restore(), isNull);
  });

  test('restore: 200 làm mới user, gửi Bearer', () async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'tok-1',
      'auth.user': jsonEncode({'email': 'old@x', 'roles': []}),
    });
    String? auth;
    final repo = repoWith((req) async {
      auth = req.headers['authorization'];
      return json(200, {
        'email': 'new@x',
        'roles': ['admin'],
      });
    });
    final s = await repo.restore();
    expect(auth, 'Bearer tok-1');
    expect(s!.user.email, 'new@x');
    expect(s.user.isAdmin, isTrue);
  });

  test('restore: 401 xoá token + user, trả null', () async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'tok-1',
      'auth.user': jsonEncode({'email': 'a@b', 'roles': []}),
    });
    final repo = repoWith((_) async => json(401, {'detail': 'x'}));
    expect(await repo.restore(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth.token'), isNull);
    expect(prefs.getString('auth.user'), isNull);
  });

  test('restore: offline dùng phiên đã lưu', () async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'tok-1',
      'auth.user': jsonEncode({
        'email': 'cached@x',
        'roles': ['learner'],
      }),
    });
    final repo = repoWith((_) async => throw http.ClientException('down'));
    final s = await repo.restore();
    expect(s!.token, 'tok-1');
    expect(s.user.email, 'cached@x');
    expect(
      (await SharedPreferences.getInstance()).getString('auth.token'),
      'tok-1',
    );
  });

  test('logout gọi server và xoá local; server lỗi vẫn xoá', () async {
    SharedPreferences.setMockInitialValues({
      'auth.token': 'tok-1',
      'auth.user': '{}',
    });
    var called = false;
    await repoWith((req) async {
      called = req.url.path == '/api/auth/logout';
      return http.Response('', 204);
    }).logout();
    expect(called, isTrue);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth.token'), isNull);

    SharedPreferences.setMockInitialValues({'auth.token': 't'});
    await repoWith((_) async => throw http.ClientException('down')).logout();
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auth.token'), isNull);
  });

  test('changePassword: 204 ok, 400, 401 (hai loại), 429, lỗi mạng', () async {
    SharedPreferences.setMockInitialValues({'auth.token': 'tok-1'});
    String? auth;
    await repoWith((req) async {
      auth = req.headers['authorization'];
      expect(jsonDecode(req.body), {
        'current_password': 'old',
        'new_password': 'newnewnewnew',
      });
      return http.Response('', 204);
    }).changePassword('old', 'newnewnewnew');
    expect(auth, 'Bearer tok-1');

    expect(
      await kindOf(
        () => repoWith(
          (_) async => json(400, {'detail': 'weak_password'}),
        ).changePassword('o', 'n'),
      ),
      AuthErrorKind.weakPassword,
    );
    expect(
      await kindOf(
        () => repoWith(
          (_) async => json(401, {'detail': 'wrong_password'}),
        ).changePassword('o', 'n'),
      ),
      AuthErrorKind.wrongPassword,
    );
    expect(
      await kindOf(
        () => repoWith(
          (_) async => json(401, {'detail': 'not_authenticated'}),
        ).changePassword('o', 'n'),
      ),
      AuthErrorKind.sessionExpired,
    );
    expect(
      await kindOf(
        () => repoWith(
          (_) async => json(429, {'detail': 'too_many_attempts'}),
        ).changePassword('o', 'n'),
      ),
      AuthErrorKind.tooManyAttempts,
    );
    expect(
      await kindOf(
        () => repoWith(
          (_) async => http.Response('x', 502),
        ).changePassword('o', 'n'),
      ),
      AuthErrorKind.network,
    );
    expect(
      await kindOf(
        () => repoWith(
          (_) async => throw http.ClientException('x'),
        ).changePassword('o', 'n'),
      ),
      AuthErrorKind.network,
    );
  });

  test(
    'changePassword: không có token → sessionExpired, không gọi mạng',
    () async {
      final repo = repoWith((_) async => fail('không được gọi mạng'));
      expect(
        await kindOf(() => repo.changePassword('o', 'n')),
        AuthErrorKind.sessionExpired,
      );
    },
  );
}
