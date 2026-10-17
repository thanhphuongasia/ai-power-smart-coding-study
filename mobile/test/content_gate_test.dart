import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_coding_study/app/content_gate.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/app/theme_mode.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/data/content_repository.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/domain/models.dart';
import 'package:smart_coding_study/main.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

const fakeThemeName = 'Chủ đề giả từ máy chủ';

/// Nội dung fixture với tên theme đầu bị đổi: khác fixture (chứng minh override), nhưng vẫn
/// đủ id bài để tiến độ demo (seedPassedExercises/seedDrafts) tra được.
Content fakeContent() => Content(
  version: 'fake-1',
  themes: [
    StudyTheme(
      id: testContent.themes.first.id,
      name: fakeThemeName,
      description: testContent.themes.first.description,
      tags: testContent.themes.first.tags,
      topics: testContent.themes.first.topics,
    ),
    ...testContent.themes.skip(1),
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
    ...authOverrides(),
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

  group('giữ State khi đổi cache ↔ network (F1)', () {
    Widget probeApp(FakeRepo repo) => ProviderScope(
      overrides: [contentRepositoryProvider.overrideWithValue(repo)],
      child: const ContentGate(
        child: MaterialApp(home: Scaffold(body: _Probe())),
      ),
    );

    setUp(() => _Probe.inits = 0);

    testWidgets('Thử lại cache → network: chữ đang gõ còn, initState 1 lần', (
      tester,
    ) async {
      final repo = FakeRepo(() async => loaded(ContentSource.cache));
      await tester.pumpWidget(probeApp(repo));
      await tester.pumpAndSettle();
      expect(find.text(bannerText), findsOneWidget);
      expect(_Probe.inits, 1);

      await tester.enterText(find.byType(TextField), 'đang gõ dở');
      repo.handler = () async => loaded(ContentSource.network);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text(bannerText), findsNothing);
      expect(find.text('đang gõ dở'), findsOneWidget);
      expect(_Probe.inits, 1);
    });

    testWidgets('cả chiều ngược network → cache cũng không dựng lại', (
      tester,
    ) async {
      final repo = FakeRepo(() async => loaded(ContentSource.network));
      await tester.pumpWidget(probeApp(repo));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc');

      repo.handler = () async => loaded(ContentSource.cache);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ContentGate)),
      );
      await container.read(contentProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text(bannerText), findsOneWidget);
      expect(find.text('abc'), findsOneWidget);
      expect(_Probe.inits, 1);
    });
  });

  testWidgets('đang tải lại: nút Thử lại của banner tắt + spinner (F5)', (
    tester,
  ) async {
    final repo = FakeRepo(() async => loaded(ContentSource.cache));
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    final pending = Completer<ContentLoad>();
    repo.handler = () => pending.future;
    await tester.tap(find.text('Thử lại'));
    await tester.pump();

    expect(find.text('Thử lại'), findsNothing);
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.onPressed, isNull);
    // Banner + nút refresh của Home (issue #48) cùng hiện spinner khi contentProvider đang tải lại.
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(find.text(fakeThemeName), findsOneWidget); // vẫn thấy app

    pending.complete(loaded(ContentSource.cache));
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('màu banner (F3) và theme màn chờ (F4)', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final dark in [false, true]) {
      testWidgets('banner ${dark ? "tối" : "sáng"}: tương phản >= 4.5', (
        tester,
      ) async {
        final repo = FakeRepo(() async => loaded(ContentSource.cache));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...authOverrides(),
              contentRepositoryProvider.overrideWithValue(repo),
              contentIndexProvider.overrideWith(
                (ref) => ref.watch(contentProvider).requireValue.content,
              ),
              themeModeProvider.overrideWith(
                () => _FixedMode(dark ? ThemeMode.dark : ThemeMode.light),
              ),
            ],
            child: const ContentGate(child: SmartCodingStudyApp()),
          ),
        );
        await tester.pumpAndSettle();

        final p = dark ? AppPalette.dark : AppPalette.light;
        final text = tester.widget<Text>(find.text(bannerText));
        final bg = tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.text(bannerText),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        expect(bg, p.accent);
        expect(text.style!.color, p.onAccent);
        expect(contrast(bg, text.style!.color!), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('màn chờ theo themeModeProvider, không theo hệ thống', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final c = Completer<ContentLoad>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider.overrideWithValue(
              FakeRepo(() => c.future),
            ),
            themeModeProvider.overrideWith(() => _FixedMode(ThemeMode.dark)),
          ],
          child: const ContentGate(child: SizedBox()),
        ),
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
    });
  });
}

class _FixedMode extends ThemeModeController {
  _FixedMode(this.mode);
  final ThemeMode mode;
  @override
  ThemeMode build() => mode;
}

/// Widget có State: đếm initState và giữ chữ gõ trong TextField.
class _Probe extends StatefulWidget {
  const _Probe();
  static int inits = 0;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final controller = TextEditingController();
  @override
  void initState() {
    super.initState();
    _Probe.inits++;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: controller);
}
