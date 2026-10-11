import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'content_repository.dart' show apiBaseUrl;

enum JudgeStatus { passed, failed, error, timeout, unavailable }

class JudgeError {
  const JudgeError({required this.kind, this.line, required this.message});

  /// 'syntax' | 'runtime'.
  final String kind;

  /// Dòng 1-based trong code đã gửi; null nếu không xác định.
  final int? line;
  final String message;
}

class JudgeTest {
  const JudgeTest({
    required this.call,
    required this.expected,
    this.actual,
    required this.passed,
  });

  final String call;
  final String expected;
  final String? actual;
  final bool passed;
}

class JudgeResult {
  const JudgeResult({
    required this.status,
    this.error,
    this.tests = const [],
    this.stdout = '',
    this.durationMs = 0,
    this.unavailableReason,
  });

  const JudgeResult.unavailable(String reason)
    : this(status: JudgeStatus.unavailable, unavailableReason: reason);

  final JudgeStatus status;
  final JudgeError? error;
  final List<JudgeTest> tests;
  final String stdout;
  final int durationMs;
  final String? unavailableReason;
}

/// Gọi backend `POST /run`. Mọi lỗi mạng/HTTP/JSON đều trả
/// [JudgeStatus.unavailable] chứ không ném exception.
class JudgeClient {
  JudgeClient({
    http.Client? httpClient,
    Uri? baseUrl,
    this._timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client(),
       _baseUrl = baseUrl ?? apiBaseUrl();

  final Duration _timeout;
  final http.Client _http;
  final Uri _baseUrl;

  Future<JudgeResult> run(String exerciseId, String code) async {
    try {
      final response = await _http
          .post(
            _baseUrl.resolve('/run'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'exercise_id': exerciseId, 'code': code}),
          )
          .timeout(_timeout);
      if (response.statusCode == 404) {
        return const JudgeResult.unavailable('Máy chấm chưa có bài này.');
      }
      if (response.statusCode != 200) {
        return const JudgeResult.unavailable(
          'Máy chấm đang bận hoặc lỗi, thử lại sau.',
        );
      }
      return _parse(utf8.decode(response.bodyBytes));
    } on TimeoutException {
      return const JudgeResult.unavailable(
        'Máy chấm không trả lời kịp (quá 20 giây).',
      );
    } on http.ClientException {
      return const JudgeResult.unavailable(
        'Không kết nối được máy chấm. Kiểm tra backend đã chạy chưa.',
      );
    } catch (_) {
      // SocketException (không phải ClientException trên mọi nền tảng),
      // hoặc lỗi bất ngờ: vẫn không để lọt ra UI.
      return const JudgeResult.unavailable('Không kết nối được máy chấm.');
    }
  }

  static JudgeResult _parse(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final status = switch (json['status']) {
        'passed' => JudgeStatus.passed,
        'failed' => JudgeStatus.failed,
        'error' => JudgeStatus.error,
        'timeout' => JudgeStatus.timeout,
        _ => throw const FormatException('status lạ'),
      };
      final err = json['error'] as Map<String, dynamic>?;
      return JudgeResult(
        status: status,
        error: err == null
            ? null
            : JudgeError(
                kind: err['kind'] as String,
                line: err['line'] as int?,
                message: err['message'] as String,
              ),
        tests: [
          for (final t in (json['tests'] as List).cast<Map<String, dynamic>>())
            JudgeTest(
              call: t['call'] as String,
              expected: t['expected'] as String,
              actual: t['actual'] as String?,
              passed: t['passed'] as bool,
            ),
        ],
        stdout: json['stdout'] as String? ?? '',
        durationMs: json['duration_ms'] as int? ?? 0,
      );
    } catch (_) {
      return const JudgeResult.unavailable(
        'Máy chấm trả dữ liệu không đọc được.',
      );
    }
  }
}

final judgeClientProvider = Provider<JudgeClient>((ref) => JudgeClient());
