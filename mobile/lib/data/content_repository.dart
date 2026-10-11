import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/content.dart';

/// Địa chỉ backend (nội dung `/content` và máy chấm `/run`).
///
/// Một biến `API_URL` cho một server: `flutter run --dart-define=API_URL=http://host:8000`.
Uri apiBaseUrl() => Uri.parse(
  const String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  ),
);

enum ContentSource { network, cache }

class ContentLoad {
  const ContentLoad({required this.content, required this.source});
  final Content content;
  final ContentSource source;
}

/// Không tải được từ mạng và cũng không có cache dùng được.
class ContentUnavailable implements Exception {
  const ContentUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'ContentUnavailable: $reason';
}

/// Tải nội dung từ `GET /content`, cache lại bản tốt gần nhất để dùng offline.
///
/// Cache chỉ được ghi khi bản tải về parse được (INV-08): dữ liệu hỏng không
/// bao giờ ghi đè cache tốt.
class ContentRepository {
  ContentRepository({
    http.Client? httpClient,
    Uri? baseUrl,
    Future<SharedPreferences> Function()? prefs,
    this.timeout = const Duration(seconds: 5),
  }) : _http = httpClient ?? http.Client(),
       _baseUrl = baseUrl ?? apiBaseUrl(),
       _prefs = prefs ?? SharedPreferences.getInstance;

  static const bodyKey = 'content.cache.body';
  static const versionKey = 'content.cache.version';

  final http.Client _http;
  final Uri _baseUrl;
  final Future<SharedPreferences> Function() _prefs;
  final Duration timeout;

  Future<ContentLoad> load() async {
    final fromNet = await _fetch();
    if (fromNet != null) {
      return ContentLoad(content: fromNet, source: ContentSource.network);
    }
    final fromCache = await _readCache();
    if (fromCache != null) {
      return ContentLoad(content: fromCache, source: ContentSource.cache);
    }
    throw const ContentUnavailable(
      'Không tải được nội dung và chưa có bản đã lưu. Kiểm tra kết nối rồi thử lại.',
    );
  }

  Future<Content?> _fetch() async {
    try {
      final response = await _http
          .get(_baseUrl.resolve('/content'))
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = utf8.decode(response.bodyBytes);
      final content = Content.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      await _writeCache(body, content.version);
      return content;
    } catch (_) {
      // Mạng, timeout, HTTP ≠ 200, JSON/schema hỏng: đều rơi về cache.
      return null;
    }
  }

  Future<void> _writeCache(String body, String version) async {
    try {
      final p = await _prefs();
      await p.setString(bodyKey, body);
      await p.setString(versionKey, version);
    } catch (_) {
      // Không ghi được cache không được làm hỏng lần tải đang thành công.
    }
  }

  Future<Content?> _readCache() async {
    try {
      final p = await _prefs();
      final body = p.getString(bodyKey);
      if (body == null) return null;
      try {
        return Content.fromJson(jsonDecode(body) as Map<String, dynamic>);
      } catch (_) {
        await p.remove(bodyKey);
        await p.remove(versionKey);
        return null;
      }
    } catch (_) {
      return null;
    }
  }
}
