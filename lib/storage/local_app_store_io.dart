import 'dart:convert';
import 'dart:io';

import '../models/app_cache_document.dart';
import 'local_app_store_base.dart';

class FileLocalAppStore implements LocalAppStore {
  FileLocalAppStore({
    File? file,
  }) : _file = file ?? _defaultFile();

  final File _file;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<AppCacheDocument> read() async {
    if (!await _file.exists()) {
      return const AppCacheDocument.empty();
    }

    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return const AppCacheDocument.empty();
    }

    try {
      final payload = jsonDecode(raw);
      if (payload is! Map<String, dynamic>) {
        await _quarantineCorruptCache(raw);
        return const AppCacheDocument.empty();
      }
      return AppCacheDocument.fromJson(payload);
    } on FormatException {
      await _quarantineCorruptCache(raw);
      return const AppCacheDocument.empty();
    }
  }

  @override
  Future<void> write(AppCacheDocument document) async {
    final encoded =
        const JsonEncoder.withIndent('  ').convert(document.toJson());
    _pendingWrite = _pendingWrite.then((_) async {
      await _file.parent.create(recursive: true);
      final tempFile = File('${_file.path}.tmp');
      await tempFile.writeAsString(encoded, flush: true);
      if (await _file.exists()) {
        await _file.delete();
      }
      await tempFile.rename(_file.path);
    });
    await _pendingWrite;
  }

  Future<void> _quarantineCorruptCache(String raw) async {
    await _file.parent.create(recursive: true);
    final corruptFile = File('${_file.path}.corrupt');
    await corruptFile.writeAsString(raw, flush: true);
    if (await _file.exists()) {
      await _file.delete();
    }
  }

  static File _defaultFile() {
    final directory = Directory(
      '${Directory.systemTemp.path}/ai_coding_coach_cache',
    );
    return File('${directory.path}/app_cache.json');
  }
}
