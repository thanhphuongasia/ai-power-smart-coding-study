/// Test các màn phase 2 qua app thật: bottom nav, đổi sáng/tối, Ôn tập,
/// Tiến độ, File cross-cut, Admin.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/main.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  appRouter.go('/');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
      ],
      child: const SmartCodingStudyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byKey(const Key('bottom-nav')))).brightness;

void main() {
  testWidgets('nút giao diện: hệ thống (sáng) → sáng → tối → hệ thống', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _pumpApp(tester);

    expect(_brightness(tester), Brightness.light);
    final button = find.byKey(const Key('theme-mode-button'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.light);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.dark);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.light);
  });

  testWidgets('bottom nav chuyển qua 4 tab, badge Ôn tập hiện số thẻ', (
    tester,
  ) async {
    await _pumpApp(tester);
    expect(find.text('Luyện tập hôm nay'), findsOneWidget);

    await tester.tap(find.text('Luyện'));
    await tester.pumpAndSettle();
    expect(find.text('Đang dở · 1'), findsOneWidget);
    expect(find.byKey(const Key('practice-split-chunks')), findsOneWidget);

    await tester.tap(find.text('Tiến độ'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stats-heatmap')), findsOneWidget);

    // 2 thẻ split-chunks đến hạn trong seed.
    expect(
      find.descendant(
        of: find.byKey(const Key('bottom-nav')),
        matching: find.text('2'),
      ),
      findsWidgets,
    );
  });

  testWidgets('Ôn tập: lật thẻ, chấm Dễ → sang thẻ kế, hết thẻ → trống', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Ôn tập'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('review-card-split-chunks-b0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('review-reveal')));
    await tester.pumpAndSettle();
    expect(find.text('def split_chunks(text, size):'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rate-easy')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('review-card-split-chunks-b1')),
      findsOneWidget,
    );

    // Chế độ Gõ lại: gõ đúng → "Đúng".
    await tester.tap(find.text('Gõ lại'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('review-input')),
      'chunks = []',
    );
    await tester.tap(find.byKey(const Key('review-check')));
    await tester.pumpAndSettle();
    expect(find.text('Đúng'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rate-ok')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-empty')), findsOneWidget);
    expect(find.text('Sắp đến hạn'), findsOneWidget);
  });

  testWidgets('Tiến độ: số liệu từ seed', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Tiến độ'));
    await tester.pumpAndSettle();

    String tile(String key) => (tester.widget<Text>(
      find
          .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
          .first,
    )).data!;
    expect(tile('stat-blocks'), '4');
    expect(tile('stat-streak'), '6');
    expect(tile('stat-no-hint'), '100%');
    expect(tile('stat-due'), '2');
  });

  testWidgets('Topic → chunker.py → File cross-cut liệt kê 2 theme', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('theme-rag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-rag-chunking')));
    await tester.pumpAndSettle();

    expect(find.text('Dùng ở 2 theme'), findsOneWidget);
    await tester.tap(find.byKey(const Key('file-rag-chunker-py')));
    await tester.pumpAndSettle();

    expect(find.text('Semantic RAG system › Chunking'), findsOneWidget);
    expect(find.text('Document system › Text processing'), findsOneWidget);
    expect(
      find.byKey(const Key('crosscut-doc-chunker-py-split-chunks')),
      findsOneWidget,
    );
    // Exercise dùng chung hiện cùng trạng thái ở cả hai theme.
    expect(find.text('Đang dở'), findsNWidgets(2));
  });

  testWidgets('Admin: duyệt, từ chối, hoàn tác', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const Key('admin-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('3 chờ duyệt · 0 đã duyệt · 0 đã từ chối'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('approve-pending-fanout-write')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('reject-pending-url-shortener')),
      200,
    );
    await tester.tap(find.byKey(const Key('reject-pending-url-shortener')));
    await tester.pumpAndSettle();
    expect(
      find.text('1 chờ duyệt · 1 đã duyệt · 1 đã từ chối'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('undo-pending-fanout-write')),
      200,
    );
    await tester.tap(find.byKey(const Key('undo-pending-fanout-write')));
    await tester.pumpAndSettle();
    expect(
      find.text('2 chờ duyệt · 0 đã duyệt · 1 đã từ chối'),
      findsOneWidget,
    );
  });
}
