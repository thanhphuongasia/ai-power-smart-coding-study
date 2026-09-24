import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_powerd_mobile_code_assitant/models/app_cache_document.dart';
import 'package:ai_powerd_mobile_code_assitant/storage/local_app_store_io.dart';

void main() {
  test('recovers from a malformed local cache file', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'ai_coding_coach_cache_test_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final file = File('${tempDir.path}/app_cache.json');
    await file.writeAsString(
      '{"installId":"test-install","pendingEvents":[{"clientEventId":}arted-1345859762"}]}',
    );

    final store = FileLocalAppStore(file: file);
    final document = await store.read();

    expect(document.installId, isNull);
    expect(document.pendingEvents, isEmpty);
    expect(document.tracks, isEmpty);
    expect(await file.exists(), isFalse);
    expect(
      await File('${file.path}.corrupt').exists(),
      isTrue,
    );
  });

  test('serializes writes through a temp file swap', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'ai_coding_coach_cache_write_test_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final file = File('${tempDir.path}/app_cache.json');
    final store = FileLocalAppStore(file: file);

    await Future.wait(<Future<void>>[
      store.write(
        const AppCacheDocument.empty().copyWith(installId: 'first'),
      ),
      store.write(
        const AppCacheDocument.empty().copyWith(installId: 'second'),
      ),
    ]);

    final raw = await file.readAsString();
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    expect(payload['installId'], anyOf('first', 'second'));
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });
}
