import '../models/app_cache_document.dart';

abstract class LocalAppStore {
  Future<AppCacheDocument> read();

  Future<void> write(AppCacheDocument document);
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

