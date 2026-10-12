/// E2E của issue #29 (chạy bởi orchestrator): đi từ HOME qua mối nối
/// shell → drawer/continue-card → màn luyện → ô → tiến độ, ở 400 và 1280px.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/main.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

// split-chunks: demo progress đã có draft ô A, ô B đang mở, ô C khoá.
const _id = 'split-chunks';
const _answerB = 'chunks.append(text[i:i + size])';

Future<ProviderContainer> _pumpApp(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  appRouter.go('/');
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...contentOverrides,
        ...authOverrides(),
        clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
      ],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const SmartCodingStudyApp();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

String _location() =>
    appRouter.routerDelegate.currentConfiguration.last.matchedLocation;

IconData? _markOf(WidgetTester t, String l) => t
    .widgetList<Icon>(
      find.descendant(
        of: find.byKey(Key('step-$l')),
        matching: find.byType(Icon),
      ),
    )
    .firstOrNull
    ?.icon;

void main() {
  testWidgets('1280px: Home → ☰ → bài → chia đôi → gõ ô B → tiến độ', (
    tester,
  ) async {
    final c = await _pumpApp(tester, 1280);
    // Shell rộng: không bottom nav, có đúng một ☰ và một nút sáng/tối.
    expect(find.byKey(const Key('bottom-nav')), findsNothing);
    expect(find.byKey(const Key('menu-button')), findsOneWidget);
    expect(find.byKey(const Key('theme-mode-button')), findsOneWidget);

    // 2 chạm: ☰ rồi chạm bài.
    await tester.tap(find.byKey(const Key('menu-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('drawer-search')), 'split');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-exercise-$_id')).first);
    await tester.pumpAndSettle();
    expect(_location(), '/exercise/$_id');

    // Màn luyện: chia đôi, đúng một ☰ (không kép), không bottom nav.
    expect(find.byKey(const Key('exercise-split')), findsOneWidget);
    expect(find.byKey(const Key('exercise-tabs')), findsNothing);
    expect(find.byKey(const Key('menu-button')), findsOneWidget);
    expect(find.byKey(const Key('bottom-nav')), findsNothing);
    expect(_markOf(tester, 'A'), Icons.check);
    expect(_markOf(tester, 'C'), Icons.lock_outline);

    // Bất biến cũ qua tính năng mới: ô đúng → lưu draft → mở ô kế (INV-04/06).
    await tester.enterText(find.byKey(const Key('editor-field')), _answerB);
    await tester.pumpAndSettle();
    expect(c.read(progressProvider)[_id]!.drafts['B'], _answerB);
    expect(_markOf(tester, 'B'), Icons.check);
    expect(_markOf(tester, 'C'), isNull);
    expect(_location(), '/exercise/$_id'); // không push route editor
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('400px: Home → Tiếp tục → 3 tab → mở ô B qua route → tiến độ', (
    tester,
  ) async {
    final c = await _pumpApp(tester, 400);
    expect(find.byKey(const Key('bottom-nav')), findsOneWidget);
    expect(find.byKey(const Key('menu-button')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('continue-card')));
    await tester.tap(find.byKey(const Key('continue-card')));
    await tester.pumpAndSettle();
    expect(_location(), '/exercise/$_id');

    // Hẹp: ba tab như cũ, không ☰, không chia đôi.
    expect(find.byKey(const Key('exercise-tabs')), findsOneWidget);
    expect(find.byKey(const Key('exercise-split')), findsNothing);
    expect(find.byKey(const Key('menu-button')), findsNothing);

    await tester.tap(find.textContaining('Code '));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cell-B-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('editor-field')), _answerB);
    await tester.pumpAndSettle();
    expect(c.read(progressProvider)[_id]!.drafts['B'], _answerB);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
