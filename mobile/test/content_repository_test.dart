import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/data/content_repository.dart';

/// Dữ liệu thật từ content.json, bỏ `judge` như server /content.
String contentBody({String version = 'v1'}) {
  final raw =
      jsonDecode(File('../backend/content/content.json').readAsStringSync())
          as Map<String, dynamic>;
  final exercises = (raw['exercises'] as Map<String, dynamic>).map(
    (k, v) => MapEntry(k, {...(v as Map<String, dynamic>)}..remove('judge')),
  );
  return jsonEncode({...raw, 'version': version, 'exercises': exercises});
}

http.Response ok(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

ContentRepository repoWith(MockClientHandler handler) => ContentRepository(
  httpClient: MockClient(handler),
  baseUrl: Uri.parse('http://x:1'),
);

Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

Future<void> seedCache(String body, String version) async {
  SharedPreferences.setMockInitialValues({
    ContentRepository.bodyKey: body,
    ContentRepository.versionKey: version,
  });
}

Future<http.Response> offline(http.Request _) async =>
    throw http.ClientException('offline');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('online: dùng mạng, gọi /content và ghi cache', () async {
    late http.Request sent;
    final r = await repoWith((req) async {
      sent = req;
      return ok(contentBody());
    }).load();
    expect(sent.url.path, '/content');
    expect(r.source, ContentSource.network);
    expect(r.content.version, 'v1');
    expect(r.content.themes, isNotEmpty);
    final p = await prefs();
    expect(p.getString(ContentRepository.versionKey), 'v1');
    expect(p.getString(ContentRepository.bodyKey), contentBody());
  });

  test('offline có cache: dùng cache', () async {
    await seedCache(contentBody(version: 'old'), 'old');
    final r = await repoWith(offline).load();
    expect(r.source, ContentSource.cache);
    expect(r.content.version, 'old');
  });

  test('offline không cache: ContentUnavailable', () async {
    await expectLater(
      repoWith(offline).load(),
      throwsA(isA<ContentUnavailable>()),
    );
  });

  test('HTTP 500 có cache: dùng cache', () async {
    await seedCache(contentBody(version: 'old'), 'old');
    final r = await repoWith((_) async => http.Response('x', 500)).load();
    expect(r.source, ContentSource.cache);
  });

  test('timeout có cache: dùng cache', () async {
    await seedCache(contentBody(version: 'old'), 'old');
    final repo = ContentRepository(
      httpClient: MockClient(
        (_) => Future.delayed(
          const Duration(milliseconds: 200),
          () => ok(contentBody(version: 'late')),
        ),
      ),
      baseUrl: Uri.parse('http://x:1'),
      timeout: const Duration(milliseconds: 20),
    );
    final r = await repo.load();
    expect(r.source, ContentSource.cache);
    expect(r.content.version, 'old');
  });

  test('server trả JSON hỏng + có cache: giữ cache cũ, không ghi đè', () async {
    final good = contentBody(version: 'old');
    await seedCache(good, 'old');
    for (final bad in [
      '{not json',
      '{"version":"bad","themes":[],"exercises":5}',
    ]) {
      final r = await repoWith((_) async => ok(bad)).load();
      expect(r.source, ContentSource.cache);
      expect(r.content.version, 'old');
      final p = await prefs();
      expect(p.getString(ContentRepository.bodyKey), good);
      expect(p.getString(ContentRepository.versionKey), 'old');
    }
  });

  test('cache hỏng + offline: ContentUnavailable và cache bị xoá', () async {
    await seedCache('{hỏng', 'old');
    await expectLater(
      repoWith(offline).load(),
      throwsA(isA<ContentUnavailable>()),
    );
    final p = await prefs();
    expect(p.getString(ContentRepository.bodyKey), isNull);
    expect(p.getString(ContentRepository.versionKey), isNull);
  });

  test('INV-08: online sau cache cũ ghi version mới', () async {
    await seedCache(contentBody(version: 'old'), 'old');
    final r = await repoWith(
      (_) async => ok(contentBody(version: 'new')),
    ).load();
    expect(r.source, ContentSource.network);
    final p = await prefs();
    expect(p.getString(ContentRepository.versionKey), 'new');
    expect(p.getString(ContentRepository.bodyKey), contentBody(version: 'new'));
  });

  test('contentProvider.refresh(): từ cache sang network', () async {
    await seedCache(contentBody(version: 'old'), 'old');
    var online = false;
    final repo = repoWith(
      (_) async => online
          ? ok(contentBody(version: 'new'))
          : throw http.ClientException('off'),
    );
    final container = ProviderContainer(
      overrides: [contentRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final first = await container.read(contentProvider.future);
    expect(first.source, ContentSource.cache);
    online = true;
    final pending = container.read(contentProvider.notifier).refresh();
    final during = container.read(contentProvider);
    expect(during.isLoading, isTrue);
    expect(during.value?.content.version, 'old'); // giữ dữ liệu cũ khi tải
    await pending;
    final second = container.read(contentProvider).requireValue;
    expect(second.source, ContentSource.network);
    expect(second.content.version, 'new');
  });
}
