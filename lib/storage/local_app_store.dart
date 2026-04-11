import 'dart:convert';
import 'dart:io';

import '../models/app_cache_document.dart';

abstract class LocalAppStore {
  Future<AppCacheDocument> read();

  Future<void> write(AppCacheDocument document);
}

class FileLocalAppStore implements LocalAppStore {
  FileLocalAppStore({
    File? file,
  }) : _file = file ?? _defaultFile();

  final File _file;

  @override
  Future<AppCacheDocument> read() async {
    if (!await _file.exists()) {
      return const AppCacheDocument.empty();
    }

    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return const AppCacheDocument.empty();
    }

    final payload = jsonDecode(raw);
    if (payload is! Map<String, dynamic>) {
      return const AppCacheDocument.empty();
    }
    return AppCacheDocument.fromJson(payload);
  }

  @override
  Future<void> write(AppCacheDocument document) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
    );
  }

  static File _defaultFile() {
    final directory = Directory(
      '${Directory.systemTemp.path}/ai_coding_coach_cache',
    );
    return File('${directory.path}/app_cache.json');
  }
}

class MemoryLocalAppStore implements LocalAppStore {
  MemoryLocalAppStore({
    AppCacheDocument initialDocument = const AppCacheDocument.empty(),
  }) : _document = initialDocument;

  AppCacheDocument _document;

  @override
  Future<AppCacheDocument> read() async => _document;

  @override
  Future<void> write(AppCacheDocument document) async {
    _document = document;
  }
}
