/// Shell theo bề rộng + drawer: <700 bottom nav, >=700 top bar ☰ và drawer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/shell/app_drawer.dart';
import 'package:smart_coding_study/main.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

Future<void> _pumpApp(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
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

String _location() =>
    appRouter.routerDelegate.currentConfiguration.last.matchedLocation;

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('menu-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('400px: có bottom-nav, không có menu-button', (tester) async {
    await _pumpApp(tester, 400);
    expect(find.byKey(const Key('bottom-nav')), findsOneWidget);
    expect(find.byKey(const Key('menu-button')), findsNothing);
  });

  testWidgets('đúng ngưỡng AppBreakpoint.nav: không bottom-nav, có ☰', (
    tester,
  ) async {
    await _pumpApp(tester, AppBreakpoint.nav);
    expect(find.byKey(const Key('bottom-nav')), findsNothing);
    expect(find.byKey(const Key('menu-button')), findsOneWidget);
    await _pumpApp(tester, AppBreakpoint.nav - 1);
    expect(find.byKey(const Key('bottom-nav')), findsOneWidget);
    expect(find.byKey(const Key('menu-button')), findsNothing);
  });

  testWidgets('800px: không bottom-nav, có ☰; chưa mở thì không có drawer', (
    tester,
  ) async {
    await _pumpApp(tester, 800);
    expect(find.byKey(const Key('bottom-nav')), findsNothing);
    expect(find.byKey(const Key('menu-button')), findsOneWidget);
    expect(find.byKey(const Key('app-drawer')), findsNothing);
    expect(find.byKey(const Key('drawer-search')), findsNothing);
    expect(find.text('Luyện'), findsNothing);
  });

  testWidgets('☰ mở drawer; gõ tìm lọc bài không phân biệt hoa thường', (
    tester,
  ) async {
    await _pumpApp(tester, 800);
    await _openDrawer(tester);
    expect(find.byKey(const Key('drawer-search')), findsOneWidget);
    final all = find.byWidgetPredicate(
      (w) => w.key.toString().contains('drawer-exercise-'),
    );
    final before = all.evaluate().length;
    expect(before, greaterThan(1));

    await tester.enterText(find.byKey(const Key('drawer-search')), 'SPLIT');
    await tester.pumpAndSettle();
    final after = all.evaluate().length;
    expect(after, greaterThan(0));
    expect(after, lessThan(before));
    // Bài dùng chung có thể xuất hiện ở nhiều topic.
    expect(find.byKey(const Key('drawer-exercise-split-chunks')), findsWidgets);

    await tester.enterText(find.byKey(const Key('drawer-search')), 'zzzqqq');
    await tester.pumpAndSettle();
    expect(find.text('Không có bài khớp'), findsOneWidget);
  });

  testWidgets('chạm mục điều hướng đổi route và đóng drawer', (tester) async {
    await _pumpApp(tester, 800);
    await _openDrawer(tester);
    await tester.tap(find.byKey(const Key('drawer-nav-1')));
    await tester.pumpAndSettle();
    expect(_location(), '/practice');
    expect(find.byKey(const Key('app-drawer')), findsNothing);
  });

  testWidgets('từ Home: ☰ → chạm bài = vào bài trong 2 chạm', (tester) async {
    await _pumpApp(tester, 800);
    await _openDrawer(tester);
    // Gõ lọc để bài nằm trong viewport (danh sách dựng lười), rồi chạm.
    await tester.enterText(find.byKey(const Key('drawer-search')), 'clean');
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('drawer-exercise-clean-text')).first;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(_location(), '/exercise/clean-text');
    expect(find.byKey(const Key('app-drawer')), findsNothing);
  });

  testWidgets('drawer mở được từ màn con (ngoài shell)', (tester) async {
    await _pumpApp(tester, 800);
    appRouter.go('/exercise/clean-text');
    await tester.pumpAndSettle();
    // Màn con chưa có ☰ riêng (T-03/T-05b); mở bằng API công khai.
    final ctx = tester.element(find.byType(Scaffold).first);
    showAppDrawer(ctx);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawer-search')), findsOneWidget);
  });

  testWidgets('800px từ Home: đúng một nút sáng/tối (không trùng top bar)', (
    tester,
  ) async {
    await _pumpApp(tester, 800);
    expect(find.byKey(const Key('theme-mode-button')), findsOneWidget);
  });

  testWidgets('400px từ Home: vẫn đúng một nút sáng/tối', (tester) async {
    await _pumpApp(tester, 400);
    expect(find.byKey(const Key('theme-mode-button')), findsOneWidget);
  });

  testWidgets('hàng đổi giao diện ở chân drawer đổi theme', (tester) async {
    await _pumpApp(tester, 800);
    await _openDrawer(tester);
    final before = Theme.of(
      tester.element(find.byKey(const Key('app-drawer'))),
    ).brightness;
    await tester.tap(find.byKey(const Key('drawer-theme-toggle')));
    await tester.pumpAndSettle();
    final after = Theme.of(
      tester.element(find.byKey(const Key('app-drawer'))),
    ).brightness;
    expect(before, Brightness.light);
    expect(after, Brightness.dark);
  });
}
