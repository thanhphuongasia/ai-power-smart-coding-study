/// Test các màn phase 2 qua app thật: bottom nav, đổi sáng/tối, Ôn tập,
/// Tiến độ, File cross-cut, Admin.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/data/admin_repository.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/main.dart';
import 'admin_controller_test.dart' show jsonResponse;
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  appRouter.go('/');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...contentOverrides,
        ...authOverrides(),
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
      ],
      child: const SmartCodingStudyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Đánh dấu bài [id] đã passed ngay trong app đang chạy (bài passed sinh thẻ
/// ôn cho từng ô; seed chỉ có clean-text passed, thẻ của nó đến hạn ngày mai).
Future<void> _pass(WidgetTester tester, String id) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('bottom-nav'))),
  );
  container.read(progressProvider.notifier).markPassed(id);
  await tester.pumpAndSettle();
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.byKey(const Key('bottom-nav')))).brightness;

void main() {
  testWidgets('nút giao diện: mặc định sáng → tối → hệ thống → sáng', (
    tester,
  ) async {
    // Nền tảng đang tối: mặc định vẫn phải sáng (không theo hệ thống).
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _pumpApp(tester);

    expect(_brightness(tester), Brightness.light);
    final button = find.byKey(const Key('theme-mode-button'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.dark);
    await tester.tap(button);
    await tester.pumpAndSettle();
    // Theo hệ thống: nền tảng đang tối.
    expect(_brightness(tester), Brightness.dark);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.light);
  });

  testWidgets('Home: chip streak hiện số ngày, chạm mở chi tiết tuần', (
    tester,
  ) async {
    await _pumpApp(tester);
    // Seed: 6 ngày liên tiếp tới hôm qua, hôm nay (T3 10/3) chưa làm gì.
    final count = tester.widget<Text>(find.byKey(const Key('streak-count')));
    expect(count.data, '6');

    await tester.tap(find.byKey(const Key('streak-chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('streak-detail')), findsOneWidget);
    expect(find.text('Làm 1 block hôm nay để giữ chuỗi'), findsOneWidget);
    expect(find.text('CN'), findsOneWidget);
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

    // Seed chưa có thẻ nào đến hạn → badge ẩn. Pass split-chunks (3 ô) → 3
    // thẻ đến hạn hôm nay.
    expect(
      find.descendant(
        of: find.byKey(const Key('bottom-nav')),
        matching: find.text('3'),
      ),
      findsNothing,
    );
    await _pass(tester, 'split-chunks');
    expect(
      find.descendant(
        of: find.byKey(const Key('bottom-nav')),
        matching: find.text('3'),
      ),
      findsWidgets,
    );
  });

  testWidgets('bottom nav có tab Design ở cuối; chạm vào /design và 4 tab '
      'cũ vẫn đúng màn', (tester) async {
    await _pumpApp(tester);
    final nav = find.byKey(const Key('bottom-nav'));
    Future<void> tapTab(String label) async {
      await tester.tap(find.descendant(of: nav, matching: find.text(label)));
      await tester.pumpAndSettle();
    }

    expect(
      find.descendant(of: nav, matching: find.text('Design')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sd-docs-screen')), findsNothing);
    await tapTab('Design');
    expect(find.byKey(const Key('sd-docs-screen')), findsOneWidget);

    await tapTab('Luyện');
    expect(find.byKey(const Key('practice-split-chunks')), findsOneWidget);
    await tapTab('Design');
    await tapTab('Ôn tập');
    expect(find.byKey(const Key('review-empty')), findsOneWidget);
    await tapTab('Design');
    await tapTab('Tiến độ');
    expect(find.byKey(const Key('stats-heatmap')), findsOneWidget);
    await tapTab('Home');
    expect(find.text('Luyện tập hôm nay'), findsOneWidget);
    expect(find.byKey(const Key('sd-docs-screen')), findsNothing);
  });

  testWidgets('Ôn tập: seed chưa có thẻ đến hạn; lật thẻ, chấm → hết thẻ', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Ôn tập'));
    await tester.pumpAndSettle();

    // Seed: chỉ clean-text passed, thẻ của nó đến hạn ngày mai.
    expect(find.byKey(const Key('review-empty')), findsOneWidget);
    expect(find.text('Sắp đến hạn'), findsOneWidget);

    // Pass split-chunks → thẻ A, B, C đến hạn hôm nay.
    await _pass(tester, 'split-chunks');
    expect(find.byKey(const Key('review-card-split-chunks-a')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-reveal')));
    await tester.pumpAndSettle();
    expect(find.text('for i in range(0, len(text), size):'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rate-easy')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-card-split-chunks-b')), findsOneWidget);

    // Chế độ Gõ lại: gõ đúng → "Đúng".
    await tester.tap(find.text('Gõ lại'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('review-input')),
      'chunks.append(text[i:i + size])',
    );
    await tester.tap(find.byKey(const Key('review-check')));
    await tester.pumpAndSettle();
    expect(find.text('Đúng'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rate-ok')));
    await tester.pumpAndSettle();

    // Thẻ C cuối cùng.
    expect(find.byKey(const Key('review-card-split-chunks-c')), findsOneWidget);
    await tester.tap(find.text('Thẻ'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-reveal')));
    await tester.pumpAndSettle();
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
    // Seed: chỉ clean-text passed (1 ô), thẻ của nó đến hạn ngày mai.
    expect(tile('stat-blocks'), '1');
    expect(tile('stat-streak'), '6');
    expect(tile('stat-no-hint'), '100%');
    expect(tile('stat-due'), '0');
  });

  testWidgets('Topic → chunker.py → File cross-cut liệt kê 2 theme', (
    tester,
  ) async {
    await _pumpApp(tester);
    // Airline đứng đầu + streak chip → card RAG có thể nằm dưới mép màn hình.
    await tester.ensureVisible(find.byKey(const Key('theme-rag')));
    await tester.pumpAndSettle();
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

  testWidgets('Admin: nút Admin mở màn soạn nội dung (cây nội dung)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    appRouter.go('/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...contentOverrides,
          ...authOverrides(roles: {'learner', 'admin'}),
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(
              MockClient(
                (r) async => jsonResponse(
                  jsonEncode({
                    'version': 'v1',
                    'content': {
                      'version': 'x',
                      'themes': [
                        {
                          'id': 'tt',
                          'name': 'Theme thử',
                          'description': '',
                          'tags': <String>[],
                          'topics': <dynamic>[],
                        },
                      ],
                      'exercises': <String, dynamic>{},
                    },
                  }),
                  200,
                ),
              ),
              baseUrl: Uri.parse('http://x'),
            ),
          ),
        ],
        child: const SmartCodingStudyApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-tree')), findsOneWidget);
    expect(find.text('Theme thử'), findsOneWidget);
    expect(find.byKey(const Key('admin-validate')), findsOneWidget);
    expect(find.byKey(const Key('admin-save')), findsOneWidget);
  });
}
