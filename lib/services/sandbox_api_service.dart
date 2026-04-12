import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/learning_models.dart';

enum SandboxExecutionAction { build, run }

class SandboxApiService {
  SandboxApiService({
    SandboxApiSettings? settings,
    http.Client? client,
  })  : _settings = settings ?? SandboxApiSettings.fromEnvironment(),
        _client = client ?? http.Client();

  final SandboxApiSettings _settings;
  final http.Client _client;

  bool get isConfigured => _settings.baseUrl.isNotEmpty;

  Future<SandboxExecutionResult> execute({
    required SandboxExecutionAction action,
    required LearningExercise exercise,
    required ExerciseLanguageVariant variant,
    required Map<String, String> fileContents,
    required String entryFilePath,
  }) async {
    if (!isConfigured) {
      return const SandboxExecutionResult(
        success: false,
        summary: 'Sandbox API is not configured yet.',
        output:
            'Add --dart-define=SANDBOX_API_BASE_URL=http://your-backend-host before using Build or Run.',
        report: null,
      );
    }

    late final http.Response response;
    try {
      response = await _client.post(
        _settings.uri.resolve('/api/sandbox/execute'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{
          'action': action.name,
          'entryFilePath': entryFilePath,
          'fileContents': fileContents,
          'exerciseId': exercise.id,
          'languageVariant': <String, Object?>{
            'languageId': variant.languageId,
            'languageLabel': variant.languageLabel,
            'runCommand': variant.runCommand,
            'entryFilePath': variant.entryFilePath,
            'demoFilePath': variant.demoFilePath,
            'harnessTemplate': variant.sandboxHarnessTemplate,
            'testCases': variant.testCases
                .map((testCase) => <String, Object?>{
                      'id': testCase.id,
                      'label': testCase.label,
                      'body': testCase.body,
                      'expectedOutput': testCase.expectedOutput,
                    })
                .toList(),
          },
        }),
      );
    } catch (error) {
      throw StateError(
        'Could not reach the sandbox API at ${_settings.baseUrl}. '
        'Start the local proxy with "cd server && npm start" '
        'or override SANDBOX_API_BASE_URL. Original error: $error',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Sandbox API request failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw StateError('Sandbox API returned an unexpected response body.');
    }

    return SandboxExecutionResult(
      success: payload['success'] == true,
      summary: payload['summary'] as String? ?? 'Sandbox execution finished.',
      output: payload['output'] as String? ?? '',
      report: _parseReport(payload['report']),
    );
  }

  ExecutionReport? _parseReport(Object? rawReport) {
    if (rawReport is! Map<String, dynamic>) {
      return null;
    }

    final rawSections = rawReport['sections'];
    final sections = rawSections is List
        ? rawSections
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => ExecutionOutputSection(
                id: item['id'] as String? ?? 'section',
                title: item['title'] as String? ?? 'Output',
                content: item['content'] as String? ?? '',
              ),
            )
            .toList(growable: false)
        : const <ExecutionOutputSection>[];

    final rawCases = rawReport['caseResults'];
    final caseResults = rawCases is List
        ? rawCases
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => ExecutionCaseResult(
                id: item['id'] as String? ?? 'case',
                label: item['label'] as String? ?? 'Test case',
                passed: item['passed'] == true,
                statusLabel: item['statusLabel'] as String? ?? 'Unknown',
                expectedOutput: item['expectedOutput'] as String? ?? '',
                actualOutput: item['actualOutput'] as String? ?? '',
                stdout: item['stdout'] as String? ?? '',
                stderr: item['stderr'] as String? ?? '',
                compileOutput: item['compileOutput'] as String? ?? '',
                message: item['message'] as String? ?? '',
              ),
            )
            .toList(growable: false)
        : const <ExecutionCaseResult>[];

    return ExecutionReport(
      engineLabel: rawReport['engineLabel'] as String? ?? 'Sandbox API',
      statusLabel: rawReport['statusLabel'] as String? ?? 'Unknown',
      passedCaseCount: rawReport['passedCaseCount'] as int? ?? 0,
      totalCaseCount: rawReport['totalCaseCount'] as int? ?? caseResults.length,
      programResult: _parseProgramResult(rawReport['programResult']),
      sections: sections,
      caseResults: caseResults,
    );
  }

  ExecutionProgramResult? _parseProgramResult(Object? rawProgramResult) {
    if (rawProgramResult is! Map<String, dynamic>) {
      return null;
    }

    return ExecutionProgramResult(
      label: rawProgramResult['label'] as String? ?? 'Program run',
      passed: rawProgramResult['passed'] == true,
      statusLabel: rawProgramResult['statusLabel'] as String? ?? 'Unknown',
      actualOutput: rawProgramResult['actualOutput'] as String? ?? '',
      stdout: rawProgramResult['stdout'] as String? ?? '',
      stderr: rawProgramResult['stderr'] as String? ?? '',
      compileOutput: rawProgramResult['compileOutput'] as String? ?? '',
      message: rawProgramResult['message'] as String? ?? '',
    );
  }
}

class SandboxApiSettings {
  const SandboxApiSettings({
    required this.baseUrl,
    this.usesDebugFallback = false,
  });

  factory SandboxApiSettings.fromEnvironment({
    String environmentBaseUrl =
        const String.fromEnvironment('SANDBOX_API_BASE_URL'),
    bool enableDebugFallback = kDebugMode,
    TargetPlatform? targetPlatform,
  }) {
    final trimmedBaseUrl = environmentBaseUrl.trim();
    if (trimmedBaseUrl.isNotEmpty) {
      return SandboxApiSettings(baseUrl: trimmedBaseUrl);
    }

    final fallbackBaseUrl = enableDebugFallback
        ? _debugFallbackBaseUrlFor(targetPlatform ?? defaultTargetPlatform)
        : '';

    return SandboxApiSettings(
      baseUrl: fallbackBaseUrl,
      usesDebugFallback: fallbackBaseUrl.isNotEmpty,
    );
  }

  final String baseUrl;
  final bool usesDebugFallback;

  Uri get uri => Uri.parse(
        baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
      );

  static String _debugFallbackBaseUrlFor(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8787';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return 'http://127.0.0.1:8787';
    }
  }
}

class SandboxExecutionResult {
  const SandboxExecutionResult({
    required this.success,
    required this.summary,
    required this.output,
    required this.report,
  });

  final bool success;
  final String summary;
  final String output;
  final ExecutionReport? report;
}
