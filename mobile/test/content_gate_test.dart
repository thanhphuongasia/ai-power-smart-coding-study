import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_coding_study/app/content_gate.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/data/content_repository.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/domain/models.dart';
import 'package:smart_coding_study/main.dart';

const fakeThemeName = 'Chủ đề giả từ máy chủ';

/// Seed với tên theme đầu bị đổi: khác seed (chứng minh override), nhưng vẫn
/// đủ id bài để tiến độ demo (seedPassedExercises/seedDrafts) tra được.
Content fakeContent() => Content(
  version: 'fake-1',
  themes: [
    StudyTheme(
      id: seedThemes.first.id,
      name: fakeThemeName,
      description: seedThemes.first.description,
      tags: seedThemes.first.tags,
      topics: seedThemes.first.topics,
    ),
    ...seedThemes.skip(1),
  ],
);

class FakeRepo implements ContentRepository {
  FakeRepo(this.handler);
  Future<ContentLoad> Function() handler;
  @override
  Future<ContentLoad> load() => handler();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Giống main.dart: override ở gốc + ContentGate bọc app.
Widget app(FakeRepo repo) => ProviderScope(
  overrides: [
    contentRepositoryProvider.overrideWithValue(repo),
    contentIndexProvider.overrideWith(
      (ref) => ref.watch(contentProvider).requireValue.content,
    ),
  ],
  child: const ContentGate(child: SmartCodingStudyApp()),
);

ContentLoad loaded(ContentSource s) =>
    ContentLoad(content: fakeContent(), source: s);

const bannerText = 'Đang dùng nội dung đã lưu — không kết nối được máy chủ';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('đang tải: spinner, chưa có app', (tester) async {
    final c = Completer<ContentLoad>();
    await tester.pumpWidget(app(FakeRepo(() => c.future)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Đang tải nội dung'), findsOneWidget);
    expect(find.text(fakeThemeName), findsNothing);
  });

  testWidgets('lỗi: màn lỗi, Thử lại khi hồi phục vào Home với nội dung fake', (
    tester,
  ) async {
    final repo = FakeRepo(
      () async => throw const ContentUnavailable('Không có mạng, không cache'),
    );
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Không có mạng, không cache'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);

    repo.handler = () async => loaded(ContentSource.network);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    // INV-09: Home hiển thị nội dung của fake (khác seed) nhờ override gốc.
    expect(find.text(fakeThemeName), findsOneWidget);
    expect(find.text('Không có mạng, không cache'), findsNothing);
  });

  testWidgets('cache: có banner, vẫn thấy nội dung; bấm Thử lại → network', (
    tester,
  ) async {
    final repo = FakeRepo(() async => loaded(ContentSource.cache));
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    expect(find.text(bannerText), findsOneWidget);
    expect(find.text(fakeThemeName), findsOneWidget);

    repo.handler = () async => loaded(ContentSource.network);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text(bannerText), findsNothing);
    expect(find.text(fakeThemeName), findsOneWidget);
  });

  testWidgets('network: không banner', (tester) async {
    await tester.pumpWidget(
      app(FakeRepo(() async => loaded(ContentSource.network))),
    );
    await tester.pumpAndSettle();
    expect(find.text(bannerText), findsNothing);
    expect(find.text(fakeThemeName), findsOneWidget);
  });
}
