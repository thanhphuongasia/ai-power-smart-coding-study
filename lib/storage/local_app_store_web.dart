// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import '../models/app_cache_document.dart';
import 'local_app_store_base.dart';

class FileLocalAppStore implements LocalAppStore {
  FileLocalAppStore({
    String storageKey = _defaultStorageKey,
  }) : _storageKey = storageKey;

  static const String _defaultStorageKey = 'ai_coding_coach/app_cache.json';

  final String _storageKey;

  @override
  Future<AppCacheDocument> read() async {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.trim().isEmpty) {
      return const AppCacheDocument.empty();
    }

    try {
      final payload = jsonDecode(raw);
      if (payload is! Map<String, dynamic>) {
        _quarantineCorruptCache(raw);
        return const AppCacheDocument.empty();
      }
      return AppCacheDocument.fromJson(payload);
    } on FormatException {
      _quarantineCorruptCache(raw);
      return const AppCacheDocument.empty();
    }
  }

  @override
  Future<void> write(AppCacheDocument document) async {
    html.window.localStorage[_storageKey] =
        const JsonEncoder.withIndent('  ').convert(document.toJson());
  }

  void _quarantineCorruptCache(String raw) {
    html.window.localStorage['$_storageKey.corrupt'] = raw;
    html.window.localStorage.remove(_storageKey);
  }
}
