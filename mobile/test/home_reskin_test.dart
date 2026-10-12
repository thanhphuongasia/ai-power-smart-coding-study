/// Home reskin (T-03): thẻ ôn tập đến hạn, thẻ chủ đề gradient + lưới, ☰ không
/// kép ở màn con, bóng nút vô hiệu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/main.dart';
import 'package:smart_coding_study/shared/widgets.dart';
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

Future<void> _pass(WidgetTester tester, String id) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('theme-mode-button'))),
  );
  container.read(progressProvider.notifier).markPassed(id);
  await tester.pumpAndSettle();
}

final _menu = find.byKey(const Key('menu-button'));

void main() {
  testWidgets(
    '400px: không menu-button; due-card chỉ hiện khi có thẻ đến hạn',
    (tester) async {
      await _pumpApp(tester, 400);
      expect(_menu, findsNothing);
      // Seed: thẻ duy nhất đến hạn ngày mai.
      expect(find.byKey(const Key('due-card')), findsNothing);

      await _pass(tester, 'split-chunks');
      expect(find.byKey(const Key('due-card')), findsOneWidget);
      expect(find.textContaining('thẻ cần ôn'), findsOneWidget);

      await tester.tap(find.byKey(const Key('due-card')));
      await tester.pumpAndSettle();
      expect(_location(), '/review');
    },
  );

  testWidgets('800px qua AppShell: đúng 1 menu-button (của shell)', (
    tester,
  ) async {
    await _pumpApp(tester, 800);
    expect(find.byKey(const Key('shell-top-bar')), findsOneWidget);
    expect(_menu, findsOneWidget);
    appRouter.go('/stats');
    await tester.pumpAndSettle();
    expect(_menu, findsOneWidget);
  });

  testWidgets('màn con: 800px có đúng 1 ☰ (ScreenHeader), 400px không có', (
    tester,
  ) async {
    await _pumpApp(tester, 800);
    await tester.ensureVisible(find.byKey(const Key('theme-rag')));
    await tester.tap(find.byKey(const Key('theme-rag')));
    await tester.pumpAndSettle();
    expect(_location(), '/theme/rag');
    expect(_menu, findsOneWidget);
    expect(
      find.descendant(of: find.byType(ScreenHeader), matching: _menu),
      findsOneWidget,
    );

    await _pumpApp(tester, 400);
    await tester.ensureVisible(find.byKey(const Key('theme-rag')));
    await tester.tap(find.byKey(const Key('theme-rag')));
    await tester.pumpAndSettle();
    expect(_location(), '/theme/rag');
    expect(_menu, findsNothing);
  });

  testWidgets('thẻ chủ đề có nền gradient', (tester) async {
    await _pumpApp(tester, 400);
    final card = find.byKey(const Key('theme-rag'));
    expect(card, findsOneWidget);
    final box = tester.widget<DecoratedBox>(card);
    final deco = box.decoration as BoxDecoration;
    expect(deco.gradient, isNotNull);
    expect(AppGradients.all.map((g) => g.gradient), contains(deco.gradient));
  });

  testWidgets('lưới thẻ chủ đề: 1 cột <700, 2 cột ở 800, 3 cột ở 1000', (
    tester,
  ) async {
    Future<int> columns(double width) async {
      await _pumpApp(tester, width);
      final cards = find.byWidgetPredicate(
        (w) =>
            w.key.toString().startsWith("[<'theme-") &&
            w.key.toString() != "[<'theme-mode-button'>]",
      );
      final lefts = <double>{
        for (final e in cards.evaluate())
          (e.renderObject! as RenderBox)
              .localToGlobal(Offset.zero)
              .dx
              .roundToDouble(),
      };
      return lefts.length;
    }

    expect(await columns(400), 1);
    expect(await columns(800), 2);
    expect(await columns(1000), 3);
  });

  testWidgets('nút vô hiệu: bóng khác màu nền nút (theme sáng), vẫn là '
      'ElevatedButton/OutlinedButton với onPressed null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Column(
          children: [
            PrimaryButton(label: 'A'),
            GhostButton(label: 'B'),
            HintButton(used: 0),
          ],
        ),
      ),
    );
    final p = tester.element(find.byType(PrimaryButton)).palette;
    for (final type in [PrimaryButton, HintButton]) {
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(type),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.boxShadow!.single.color, isNot(p.outline));
    }
    expect(
      tester
          .widget<ElevatedButton>(find.byType(ElevatedButton).first)
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });
}
