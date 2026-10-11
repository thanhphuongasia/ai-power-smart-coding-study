import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/data/judge_client.dart';

JudgeClient clientWith(MockClientHandler handler) => JudgeClient(
  httpClient: MockClient(handler),
  baseUrl: Uri.parse('http://x:1'),
);

http.Response json200(String body) => http.Response(
  body,
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// Chép nguyên văn ví dụ trong PLAN.md (mục Hợp đồng /run), union -> "passed".
const passedFixture = '''
{"status": "passed",
 "error": null,
 "tests": [{"call": "split_chunks('hello world', 4)", "expected": "['hell', 'o wo', 'rld']",
            "actual": "['hell', 'o wo', 'rld']", "passed": true}],
 "stdout": "...", "duration_ms": 812}
''';

void main() {
  test('passed: parse đủ field và gửi đúng request', () async {
    late http.Request sent;
    final client = clientWith((req) async {
      sent = req;
      return json200(passedFixture);
    });
    final r = await client.run('split-chunks', 'def f(): ...');
    expect(sent.method, 'POST');
    expect(sent.url.path, '/run');
    expect(jsonDecode(sent.body), {
      'exercise_id': 'split-chunks',
      'code': 'def f(): ...',
    });
    expect(r.status, JudgeStatus.passed);
    expect(r.error, isNull);
    expect(r.tests.single.call, "split_chunks('hello world', 4)");
    expect(r.tests.single.actual, "['hell', 'o wo', 'rld']");
    expect(r.tests.single.passed, isTrue);
    expect(r.stdout, '...');
    expect(r.durationMs, 812);
    expect(r.unavailableReason, isNull);
  });

  test('failed: actual null', () async {
    final client = clientWith(
      (_) async => json200(
        jsonEncode({
          'status': 'failed',
          'error': null,
          'tests': [
            {'call': 'f(1)', 'expected': '2', 'actual': null, 'passed': false},
          ],
          'stdout': '',
          'duration_ms': 5,
        }),
      ),
    );
    final r = await client.run('a', 'x');
    expect(r.status, JudgeStatus.failed);
    expect(r.tests.single.actual, isNull);
    expect(r.tests.single.passed, isFalse);
  });

  test('error syntax có line', () async {
    final client = clientWith(
      (_) async => json200(
        jsonEncode({
          'status': 'error',
          'error': {'kind': 'syntax', 'line': 3, 'message': 'invalid syntax'},
          'tests': [],
          'stdout': '',
          'duration_ms': 1,
        }),
      ),
    );
    final r = await client.run('a', 'x');
    expect(r.status, JudgeStatus.error);
    expect(r.error!.kind, 'syntax');
    expect(r.error!.line, 3);
    expect(r.error!.message, 'invalid syntax');
  });

  test('error runtime line null', () async {
    final client = clientWith(
      (_) async => json200(
        jsonEncode({
          'status': 'error',
          'error': {'kind': 'runtime', 'line': null, 'message': 'boom'},
          'tests': [],
          'stdout': '',
          'duration_ms': 1,
        }),
      ),
    );
    final r = await client.run('a', 'x');
    expect(r.error!.line, isNull);
  });

  test('status timeout của máy chấm được giữ nguyên', () async {
    final client = clientWith(
      (_) async => json200(
        jsonEncode({
          'status': 'timeout',
          'error': null,
          'tests': [],
          'stdout': '',
          'duration_ms': 2000,
        }),
      ),
    );
    expect((await client.run('a', 'x')).status, JudgeStatus.timeout);
  });

  test('HTTP timeout -> unavailable', () async {
    final client = JudgeClient(
      httpClient: MockClient((_) => Completer<http.Response>().future),
      baseUrl: Uri.parse('http://x:1'),
      timeout: const Duration(milliseconds: 20),
    );
    final r = await client.run('a', 'x');
    expect(r.status, JudgeStatus.unavailable);
    expect(r.unavailableReason, contains('không trả lời kịp'));
  });

  test('503 -> unavailable', () async {
    final client = clientWith(
      (_) async => http.Response('{"detail": "runner_unavailable"}', 503),
    );
    final r = await client.run('a', 'x');
    expect(r.status, JudgeStatus.unavailable);
    expect(r.unavailableReason, isNotEmpty);
  });

  test('404 -> unavailable', () async {
    final client = clientWith(
      (_) async => http.Response('{"detail": "exercise_not_found"}', 404),
    );
    final r = await client.run('zzz', 'x');
    expect(r.status, JudgeStatus.unavailable);
    expect(r.unavailableReason, contains('chưa có bài'));
  });

  test('mất mạng (ClientException / SocketException) -> unavailable', () async {
    for (final error in <Object>[
      http.ClientException('no route'),
      const SocketException('refused'),
    ]) {
      final client = clientWith((_) async => throw error);
      final r = await client.run('a', 'x');
      expect(r.status, JudgeStatus.unavailable, reason: '$error');
      expect(r.unavailableReason, isNotEmpty);
    }
  });

  test('JSON hỏng / thiếu field / status lạ -> unavailable', () async {
    for (final body in [
      'không phải json',
      '[]',
      '{"status": "passed"}',
      '{"status": "weird", "error": null, "tests": [], "stdout": "", "duration_ms": 1}',
    ]) {
      final client = clientWith((_) async => json200(body));
      final r = await client.run('a', 'x');
      expect(r.status, JudgeStatus.unavailable, reason: body);
      expect(r.unavailableReason, contains('không đọc được'));
    }
  });
}
