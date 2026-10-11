// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/data/auth_repository.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/data/progress_api.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/review/review_controller.dart';
import 'package:smart_coding_study/features/stats/activity.dart';

import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

final _now = DateTime(2026, 3, 10, 9);

const _serverBody = {
  'exercises': {
    'split-chunks': {
      'passed': false,
      'drafts': {'A': 'for i in range(0, len(text), size):'},
      'hints_used': {'A': 2},
      'solution_viewed': ['B'],
    },
    'clean-text': {
      'passed': true,
      'drafts': <String, String>{},
      'hints_used': <String, int>{},
      'solution_viewed': <String>[],
    },
    'not-in-content': {
      'passed': true,
      'drafts': <String, String>{},
      'hints_used': <String, int>{},
      'solution_viewed': <String>[],
    },
  },
  'state': {
    'review': {
      'clean-text-a': {
        'due': '2026-03-11T00:00:00.000',
        'interval_days': 1,
        'ease': 2.5,
        'reps': 1,
      },
      'broken': {'due': 'khong-phai-ngay'},
    },
    'activity': {'2026-03-09': 3, '2026-03-08': 1},
  },
};

class _Server {
  _Server({this.getStatus = 200, this.putStatus = 204});

  int getStatus;
  int putStatus;
  bool throwOnPut = false;
  Map<String, Object?> body = _serverBody;

  /// Có giá trị → GET chờ completer này trước khi trả lời.
  Completer<void>? getGate;
  final List<http.Request> puts = [];

  Future<http.Response> handle(http.Request req) async {
    if (req.method == 'GET') {
      await getGate?.future;
      return http.Response(jsonEncode(body), getStatus);
    }
    puts.add(req);
    if (throwOnPut) throw http.ClientException('mất mạng');
    return http.Response('', putStatus);
  }

  Map<String, dynamic> bodyOf(int i) =>
      jsonDecode(puts[i].body) as Map<String, dynamic>;
}

ProviderContainer _container(_Server server, {bool signedIn = true}) {
  final c = ProviderContainer(
    overrides: [
      // Không dùng contentOverrides: nó mang tiến độ demo + tắt đồng bộ.
      contentIndexProvider.overrideWithValue(testContent),
      if (signedIn) authControllerProvider.overrideWith(_SwitchAuth.new),
      progressApiProvider.overrideWithValue(
        ProgressApi(MockClient(server.handle), baseUrl: Uri.parse('http://t')),
      ),
      clockProvider.overrideWithValue(() => _now),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Đăng nhập + tải snapshot trong fakeAsync (Riverpod cần một tick timer để
/// chạy lại provider sau khi phiên đổi).
void _load(FakeAsync async, ProviderContainer c) {
  c.listen(progressSnapshotProvider, (_, _) {});
  c.listen(progressProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
}

void main() {
  test('snapshot server khởi tạo progress / review / activity', () async {
    final c = _container(_Server());
    await c.read(authControllerProvider.future);
    await c.read(progressSnapshotProvider.future);

    final progress = c.read(progressProvider);
    expect(progress['clean-text']!.passed, isTrue);
    expect(
      progress['clean-text']!.completedBlocks,
      testContent.exerciseById('clean-text').blocks.length,
    );
    final split = progress['split-chunks']!;
    expect(split.drafts['A'], 'for i in range(0, len(text), size):');
    expect(split.hintsUsed, {'A': 2});
    expect(split.solutionViewed, {'B'});
    expect(progress.containsKey('not-in-content'), isFalse);

    final review = c.read(reviewScheduleProvider);
    expect(review.keys, ['clean-text-a']); // dòng hỏng bị bỏ qua
    expect(review['clean-text-a']!.due, DateTime(2026, 3, 11));
    expect(review['clean-text-a']!.intervalDays, 1);

    final activity = c.read(activityProvider);
    expect(activity[DateTime(2026, 3, 9)], 3);
    expect(activity[DateTime(2026, 3, 8)], 1);
  });

  test('chưa đăng nhập → rỗng, không đẩy gì', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server, signedIn: false);
      _load(async, c);
      expect(c.read(progressProvider), isEmpty);
      c.read(progressProvider.notifier).saveDraft('split-chunks', 'A', 'x');
      c.read(progressProvider.notifier).useHint('split-chunks', 'A');
      async.elapse(const Duration(seconds: 2));
      expect(server.puts, isEmpty);
    });
  });

  test(
    'tải snapshot lỗi → app chạy rỗng và KHÔNG đẩy (không ghi đè server)',
    () {
      fakeAsync((async) {
        final server = _Server(getStatus: 500);
        final c = _container(server);
        _load(async, c);
        expect(c.read(progressProvider), isEmpty);
        c.read(progressProvider.notifier).useHint('split-chunks', 'A');
        c.read(progressProvider.notifier).viewSolution('split-chunks', 'A');
        async.elapse(const Duration(seconds: 2));
        expect(server.puts, isEmpty);
        // State cục bộ vẫn dùng được.
        expect(c.read(progressProvider)['split-chunks']!.hintsUsed['A'], 1);
      });
    },
  );

  test('saveDraft gom 800 ms: một PUT sau chuỗi gõ, mang bản mới nhất', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server);
      _load(async, c);
      final n = c.read(progressProvider.notifier);

      n.saveDraft('split-chunks', 'A', 'f');
      async.elapse(const Duration(milliseconds: 300));
      n.saveDraft('split-chunks', 'A', 'fo');
      async.elapse(const Duration(milliseconds: 300));
      n.saveDraft('split-chunks', 'A', 'for');
      async.elapse(const Duration(milliseconds: 799));
      expect(server.puts, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(server.puts, hasLength(1));
      final req = server.puts.single;
      expect(req.method, 'PUT');
      expect(req.url.path, '/api/progress/split-chunks');
      expect(server.bodyOf(0), {
        'drafts': {'A': 'for'},
        'hints_used': {'A': 2},
        'solution_viewed': ['B'],
      });
    });
  });

  test('draft của hai exercise debounce độc lập', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server);
      _load(async, c);
      final n = c.read(progressProvider.notifier);
      n.saveDraft('split-chunks', 'A', 'a');
      n.saveDraft('overlap-chunks', 'A', 'b');
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(server.puts.map((r) => r.url.path).toSet(), {
        '/api/progress/split-chunks',
        '/api/progress/overlap-chunks',
      });
    });
  });

  test('useHint / viewSolution PUT ngay đúng JSON', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server);
      _load(async, c);
      final n = c.read(progressProvider.notifier);

      expect(n.useHint('overlap-chunks', 'A'), 1);
      async.flushMicrotasks();
      expect(server.puts, hasLength(1));
      expect(server.puts[0].url.path, '/api/progress/overlap-chunks');
      expect(server.bodyOf(0), {
        'drafts': <String, String>{},
        'hints_used': {'A': 1},
        'solution_viewed': <String>[],
      });

      n.viewSolution('overlap-chunks', 'A');
      async.flushMicrotasks();
      expect(server.puts, hasLength(2));
      expect(server.bodyOf(1)['solution_viewed'], ['A']);

      // Đã tối đa 3 hint → không đổi gì → không PUT thêm.
      n.useHint('overlap-chunks', 'A');
      n.useHint('overlap-chunks', 'A');
      expect(n.useHint('overlap-chunks', 'A'), 3);
      async.flushMicrotasks();
      expect(server.puts, hasLength(4));
    });
  });

  test('markPassed chỉ đổi cục bộ; không PUT nào chứa "passed"', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server);
      _load(async, c);
      final n = c.read(progressProvider.notifier);

      n.markPassed('overlap-chunks');
      n.saveDraft('overlap-chunks', 'A', 'x');
      n.useHint('overlap-chunks', 'A');
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(c.read(progressProvider)['overlap-chunks']!.passed, isTrue);
      expect(server.puts, isNotEmpty);
      for (final r in server.puts) {
        expect(r.body.contains('passed'), isFalse, reason: r.url.path);
      }
      // Không có PUT exercise nào do chính markPassed; chỉ state hoạt động.
      expect(server.puts.first.url.path, '/api/progress/state');
    });
  });

  test(
    'PUT lỗi (500 hoặc mất mạng): giữ state, không ném, lần sau đẩy lại',
    () {
      fakeAsync((async) {
        final server = _Server(putStatus: 500);
        final c = _container(server);
        _load(async, c);
        final n = c.read(progressProvider.notifier);

        n.useHint('overlap-chunks', 'A');
        async.flushMicrotasks();
        expect(c.read(progressProvider)['overlap-chunks']!.hintsUsed['A'], 1);

        server.throwOnPut = true;
        n.saveDraft('overlap-chunks', 'A', 'code');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(c.read(progressProvider)['overlap-chunks']!.drafts['A'], 'code');

        server.throwOnPut = false;
        server.putStatus = 204;
        n.useHint('overlap-chunks', 'A');
        async.flushMicrotasks();
        // Lần đổi sau mang TOÀN BỘ trạng thái, gồm cả phần đã lỡ đẩy trước đó.
        expect(server.bodyOf(server.puts.length - 1), {
          'drafts': {'A': 'code'},
          'hints_used': {'A': 2},
          'solution_viewed': <String>[],
        });
      });
    },
  );

  test('rate: PUT /api/progress/state đủ review + activity', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server);
      _load(async, c);

      c
          .read(reviewScheduleProvider.notifier)
          .rate('clean-text-a', ReviewRating.ok);
      async.flushMicrotasks();

      expect(server.puts, hasLength(1));
      expect(server.puts[0].method, 'PUT');
      expect(server.puts[0].url.path, '/api/progress/state');
      // Server cũ: reps 1, ok → interval 3 ngày, reps 2.
      expect(server.bodyOf(0), {
        'review': {
          'clean-text-a': {
            'due': DateTime(2026, 3, 13).toIso8601String(),
            'interval_days': 3,
            'ease': 2.5,
            'reps': 2,
          },
        },
        'activity': {'2026-03-10': 1, '2026-03-09': 3, '2026-03-08': 1},
      });
    });
  });

  test('activity > 365 ngày: PUT chỉ gửi 365 ngày mới nhất', () {
    fakeAsync((async) {
      final server = _Server()
        ..body = {
          'exercises': <String, Object?>{},
          'state': {
            'review': <String, Object?>{},
            'activity': {
              for (var i = 0; i < 401; i++)
                _dayStr(DateTime(2026, 3, 9).subtract(Duration(days: i))): 1,
            },
          },
        };
      final c = _container(server);
      _load(async, c);
      expect(c.read(activityProvider), hasLength(401)); // hiển thị giữ đủ

      c
          .read(reviewScheduleProvider.notifier)
          .rate('clean-text-a', ReviewRating.ok);
      async.flushMicrotasks();

      final activity = server.bodyOf(0)['activity'] as Map<String, dynamic>;
      expect(activity.length, lessThanOrEqualTo(365));
      expect(activity, contains('2026-03-10')); // hôm nay vừa ghi
      expect(activity, contains('2026-03-09'));
      final oldest = DateTime(2026, 3, 9).subtract(const Duration(days: 400));
      expect(activity.containsKey(_dayStr(oldest)), isFalse);
    });
  });

  test('vừa đổi phiên (GET chưa xong): không PUT; xong thì là state của B', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server);
      _load(async, c);
      expect(c.read(loadedProgressProvider), isNotNull);

      // Đăng xuất rồi đăng nhập B với GET bị treo.
      final auth = c.read(authControllerProvider.notifier) as _SwitchAuth;
      server.getGate = Completer<void>();
      server.body = {
        'exercises': {
          'overlap-chunks': {
            'passed': true,
            'drafts': <String, String>{},
            'hints_used': <String, int>{},
            'solution_viewed': <String>[],
          },
        },
        'state': {'review': <String, Object?>{}, 'activity': <String, int>{}},
      };
      auth.setSession(null);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      auth.setSession(_sessionB);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(c.read(progressSnapshotProvider).isLoading, isTrue);
      expect(c.read(loadedProgressProvider), isNull);
      final n = c.read(progressProvider.notifier);
      n.useHint('split-chunks', 'A');
      c
          .read(reviewScheduleProvider.notifier)
          .rate('clean-text-a', ReviewRating.ok);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(server.puts, isEmpty);

      server.getGate!.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(c.read(loadedProgressProvider)!.token, 'tok-b');
      final progress = c.read(progressProvider);
      expect(progress.keys, ['overlap-chunks']);
      expect(progress['overlap-chunks']!.passed, isTrue);
      expect(c.read(reviewScheduleProvider), isEmpty);
    });
  });

  test('draft > 64KB hoặc có NUL: giữ cục bộ, không PUT', () {
    fakeAsync((async) {
      final server = _Server();
      final c = _container(server);
      _load(async, c);
      final n = c.read(progressProvider.notifier);

      n.saveDraft('overlap-chunks', 'A', 'a' * (64 * 1024 + 1));
      async.elapse(const Duration(seconds: 1));
      n.saveDraft('overlap-chunks', 'A', 'x\u0000y');
      async.elapse(const Duration(seconds: 1));
      // 22000 ký tự 3 byte = 66000 byte > 64KB dù chỉ 22000 ký tự.
      n.saveDraft('overlap-chunks', 'A', '€' * 22000);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(server.puts, isEmpty);
      expect(
        c.read(progressProvider)['overlap-chunks']!.drafts['A'],
        '€' * 22000,
      );

      n.saveDraft('overlap-chunks', 'A', 'ok');
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(server.puts, hasLength(1));
    });
  });

  test('GET/PUT quá hạn (timeout) thì ném TimeoutException', () {
    fakeAsync((async) {
      final api = ProgressApi(
        MockClient((_) => Completer<http.Response>().future),
        baseUrl: Uri.parse('http://t'),
        timeout: const Duration(seconds: 15),
      );
      Object? getErr, putErr;
      api.fetch().catchError((Object e) {
        getErr = e;
        return ProgressSnapshot.empty;
      });
      api.saveState({}, {}).catchError((Object e) => putErr = e);
      async.elapse(const Duration(seconds: 16));
      expect(getErr, isA<TimeoutException>());
      expect(putErr, isA<TimeoutException>());
    });
  });

  test(
    'nhãn ô không còn trong bài (admin đổi/xoá ô) bị bỏ khi nạp — PUT sau đó hợp lệ',
    () async {
      final server = _Server()
        ..body = {
          'exercises': {
            'split-chunks': {
              'passed': false,
              'drafts': {'A': 'x', 'Z': 'old label'},
              'hints_used': {'A': 1, 'Z': 3},
              'solution_viewed': ['Z'],
            },
          },
          'state': {
            'review': <String, Object?>{},
            'activity': <String, Object?>{},
          },
        };
      final c = _container(server);
      await c.read(authControllerProvider.future);
      await c.read(progressSnapshotProvider.future);
      final split = c.read(progressProvider)['split-chunks']!;
      expect(split.drafts, {'A': 'x'});
      expect(split.hintsUsed, {'A': 1});
      expect(split.solutionViewed, isEmpty);
      c.read(progressProvider.notifier).useHint('split-chunks', 'A');
      await Future<void>.delayed(Duration.zero);
      final sent = server.bodyOf(server.puts.length - 1);
      expect((sent['drafts'] as Map).keys, ['A']);
      expect((sent['hints_used'] as Map).keys, ['A']);
    },
  );
}

String _dayStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _sessionB = AuthSession(
  token: 'tok-b',
  user: AuthUser(email: 'b@example.com', roles: ['learner']),
);

class _SwitchAuth extends AuthController {
  @override
  Future<AuthSession?> build() async => fakeSession();

  void setSession(AuthSession? s) => state = AsyncData(s);
}
