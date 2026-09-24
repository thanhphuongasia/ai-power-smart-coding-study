import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_powerd_mobile_code_assitant/services/sandbox_api_service.dart';

void main() {
  group('SandboxApiSettings.fromEnvironment', () {
    test('prefers explicit dart-define configuration', () {
      final settings = SandboxApiSettings.fromEnvironment(
        environmentBaseUrl: 'http://192.168.1.25:8787',
        enableDebugFallback: true,
        targetPlatform: TargetPlatform.iOS,
      );

      expect(settings.baseUrl, 'http://192.168.1.25:8787');
      expect(settings.usesDebugFallback, isFalse);
    });

    test('uses Android emulator fallback in debug mode', () {
      final settings = SandboxApiSettings.fromEnvironment(
        environmentBaseUrl: '',
        enableDebugFallback: true,
        targetPlatform: TargetPlatform.android,
      );

      expect(settings.baseUrl, 'http://10.0.2.2:8787');
      expect(settings.usesDebugFallback, isTrue);
    });

    test('uses localhost fallback on Apple simulators in debug mode', () {
      final settings = SandboxApiSettings.fromEnvironment(
        environmentBaseUrl: '',
        enableDebugFallback: true,
        targetPlatform: TargetPlatform.iOS,
      );

      expect(settings.baseUrl, 'http://127.0.0.1:8787');
      expect(settings.usesDebugFallback, isTrue);
    });

    test('stays unconfigured without dart-define in non-debug mode', () {
      final settings = SandboxApiSettings.fromEnvironment(
        environmentBaseUrl: '',
        enableDebugFallback: false,
        targetPlatform: TargetPlatform.iOS,
      );

      expect(settings.baseUrl, isEmpty);
      expect(settings.usesDebugFallback, isFalse);
    });
  });
}
