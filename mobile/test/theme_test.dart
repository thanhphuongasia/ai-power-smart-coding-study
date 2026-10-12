import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/shared/widgets.dart';

void main() {
  group('AppColors', () {
    test('surface color is correct', () {
      expect(AppColors.surface, const Color(0xFF0F1522));
    });

    test('surfaceRaised color is correct', () {
      expect(AppColors.surfaceRaised, const Color(0xFF171F31));
    });

    test('outline color is correct', () {
      expect(AppColors.outline, const Color(0xFF27314A));
    });

    test('ink color is correct', () {
      expect(AppColors.ink, const Color(0xFFE8ECF4));
    });

    test('inkMuted color is correct', () {
      expect(AppColors.inkMuted, const Color(0xFF9AA6BA));
    });

    test('primary color is correct', () {
      expect(AppColors.primary, const Color(0xFF6C9DF0));
    });

    test('onPrimary color is correct', () {
      expect(AppColors.onPrimary, const Color(0xFF0F1522));
    });

    test('accent color is correct', () {
      expect(AppColors.accent, const Color(0xFFFF8A00));
    });

    test('onAccent color is correct', () {
      expect(AppColors.onAccent, const Color(0xFF2a1a00));
    });

    test('danger color is correct', () {
      expect(AppColors.danger, const Color(0xFFE5484D));
    });
  });

  group('AppPalette', () {
    test('light has The Coach tokens', () {
      const p = AppPalette.light;
      expect(p.primary, const Color(0xFF4A86E8));
      expect(p.primaryDark, const Color(0xFF2F6BCB));
      expect(p.primarySoft, const Color(0xFFE8F0FB));
      expect(p.surface, const Color(0xFFF7F8FA));
      expect(p.surfaceRaised, const Color(0xFFFFFFFF));
      expect(p.outline, const Color(0xFFE5E7EB));
      expect(p.ink, const Color(0xFF14213D));
      expect(p.inkMuted, const Color(0xFF6B7280));
      expect(p.accent, const Color(0xFFFF8A00));
      expect(p.success, const Color(0xFF58A700));
      expect(p.successDark, const Color(0xFF3F7D00));
      expect(p.successSoft, const Color(0xFFE4F0D5));
      expect(p.danger, const Color(0xFFE5484D));
      expect(p.codeSurface, const Color(0xFF1E2230));
      expect(p.codeInk, const Color(0xFFE6E9F2));
    });

    test('dark has The Coach tokens', () {
      const p = AppPalette.dark;
      expect(p.primary, const Color(0xFF6C9DF0));
      expect(p.primaryDark, const Color(0xFF3E6FC8));
      expect(p.primarySoft, const Color(0xFF1D2A47));
      expect(p.successSoft, const Color(0xFF1C3314));
      expect(p.codeSurface, const Color(0xFF0C111C));
      expect(p.codeInk, const Color(0xFFE6E9F2));
    });

    test('copyWith and lerp cover every new field', () {
      const a = AppPalette.dark;
      const b = AppPalette.light;
      final c = a.copyWith(
        primaryDark: b.primaryDark,
        primarySoft: b.primarySoft,
        success: b.success,
        successDark: b.successDark,
        successSoft: b.successSoft,
        codeSurface: b.codeSurface,
        codeInk: b.codeInk,
      );
      expect(c.primaryDark, b.primaryDark);
      expect(c.primarySoft, b.primarySoft);
      expect(c.successSoft, b.successSoft);
      expect(c.codeSurface, b.codeSurface);
      expect(c.surface, a.surface);
      final end = a.lerp(b, 1);
      expect(end.primaryDark, b.primaryDark);
      expect(end.primarySoft, b.primarySoft);
      expect(end.success, b.success);
      expect(end.successDark, b.successDark);
      expect(end.successSoft, b.successSoft);
      expect(end.codeSurface, b.codeSurface);
      expect(end.codeInk, b.codeInk);
      expect(a.lerp(b, 0).primarySoft, a.primarySoft);
    });

    test('light theme maps palette into buildAppTheme', () {
      final theme = buildAppTheme(brightness: Brightness.light);
      expect(theme.extension<AppPalette>(), AppPalette.light);
      expect(theme.scaffoldBackgroundColor, AppPalette.light.surface);
    });
  });

  group('AppBreakpoint / AppGradients', () {
    test('breakpoints are 700 and 900', () {
      expect(AppBreakpoint.nav, 700);
      expect(AppBreakpoint.split, 900);
    });

    test('three gradient pairs', () {
      expect(AppGradients.all.length, 3);
      expect(AppGradients.g1.end, const Color(0xFF4A86E8));
      expect(AppGradients.g2.start, const Color(0xFF0F5C5C));
      expect(AppGradients.g3.end, const Color(0xFF8B5CC6));
    });
  });

  group('AppSpace', () {
    test('space constants are correct', () {
      expect(AppSpace.s1, 4);
      expect(AppSpace.s2, 8);
      expect(AppSpace.s4, 16);
      expect(AppSpace.s6, 24);
    });
  });

  group('AppRadius', () {
    test('radius constants are correct', () {
      expect(AppRadius.sm, 6);
      expect(AppRadius.md, 12);
      expect(AppRadius.pill, 999);
    });
  });

  group('AppText', () {
    test('text styles are defined', () {
      expect(AppText.display, isNotNull);
      expect(AppText.title, isNotNull);
      expect(AppText.body, isNotNull);
      expect(AppText.label, isNotNull);
      expect(AppText.caption, isNotNull);
      expect(AppText.code, isNotNull);
    });

    test('display text style has correct font family', () {
      expect(AppText.display.fontFamily, kSansFamily);
    });

    test('kSansFamily is Nunito', () {
      expect(kSansFamily, 'Nunito');
    });

    test('sans styles carry wght variation matching fontWeight', () {
      final expected = {
        AppText.display: 900,
        AppText.title: 800,
        AppText.body: 500,
        AppText.label: 700,
        AppText.caption: 600,
      };
      expected.forEach((style, w) {
        expect(style.fontVariations, isNotNull);
        expect(style.fontVariations!.single.axis, 'wght');
        expect(style.fontVariations!.single.value, w.toDouble());
        expect(style.fontWeight!.value, w);
      });
    });

    test('code text style uses mono font', () {
      expect(AppText.code.fontFamily, kMonoFamily);
    });
  });

  group('buildAppTheme', () {
    test('theme uses Material3', () {
      final theme = buildAppTheme();
      expect(theme.useMaterial3, isTrue);
    });

    test('scaffold background is surface color', () {
      final theme = buildAppTheme();
      expect(theme.scaffoldBackgroundColor, AppColors.surface);
    });

    test('colorScheme surface is mapped correctly', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.surface, AppColors.surface);
    });

    test('colorScheme surfaceContainer is mapped correctly', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.surfaceContainer, AppColors.surfaceRaised);
    });

    test('colorScheme outline is mapped correctly', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.outline, AppColors.outline);
    });

    test('colorScheme onSurface is mapped correctly', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.onSurface, AppColors.ink);
    });

    test('colorScheme onSurfaceVariant is mapped correctly', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.onSurfaceVariant, AppColors.inkMuted);
    });

    test('colorScheme primary is mapped correctly', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.primary, AppColors.primary);
    });

    test('colorScheme onPrimary is mapped correctly', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.onPrimary, AppColors.onPrimary);
    });

    test('colorScheme tertiary is mapped to accent', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.tertiary, AppColors.accent);
    });

    test('colorScheme onTertiary is mapped to onAccent', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.onTertiary, AppColors.onAccent);
    });

    test('colorScheme error is mapped to danger', () {
      final theme = buildAppTheme();
      expect(theme.colorScheme.error, AppColors.danger);
    });

    test('card theme has elevation 0', () {
      final theme = buildAppTheme();
      expect(theme.cardTheme.elevation, 0);
    });

    test('dialog theme has elevation 0', () {
      final theme = buildAppTheme();
      expect(theme.dialogTheme.elevation, 0);
    });

    test('bottom sheet theme has elevation 0', () {
      final theme = buildAppTheme();
      expect(theme.bottomSheetTheme.elevation, 0);
    });

    test('app bar theme has elevation 0', () {
      final theme = buildAppTheme();
      expect(theme.appBarTheme.elevation, 0);
    });
  });

  group('Widgets', () {
    testWidgets('SurfaceCard pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SurfaceCard(child: const Text('Test'))),
        ),
      );
      expect(find.byType(SurfaceCard), findsOneWidget);
    });

    testWidgets('TagChip pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: TagChip('tag')),
        ),
      );
      expect(find.byType(TagChip), findsOneWidget);
    });

    testWidgets('ResultBadge pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: ResultBadge(passed: true)),
        ),
      );
      expect(find.byType(ResultBadge), findsOneWidget);
    });

    testWidgets('ResultBadge shows correct text for passed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: ResultBadge(passed: true)),
        ),
      );
      expect(find.text('Đúng'), findsOneWidget);
    });

    testWidgets('ResultBadge shows correct text for failed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: ResultBadge(passed: false)),
        ),
      );
      expect(find.text('Chưa đúng'), findsOneWidget);
    });

    testWidgets('TimerPill pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: TimerPill(Duration.zero)),
        ),
      );
      expect(find.byType(TimerPill), findsOneWidget);
    });

    testWidgets('ThinProgressBar pumps without error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: ThinProgressBar(value: 0.5)),
        ),
      );
      expect(find.byType(ThinProgressBar), findsOneWidget);
    });

    testWidgets('ScreenHeader pumps without error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: ScreenHeader(title: 'Test')),
        ),
      );
      expect(find.byType(ScreenHeader), findsOneWidget);
    });

    testWidgets('SectionLabel pumps without error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: SectionLabel('label')),
        ),
      );
      expect(find.byType(SectionLabel), findsOneWidget);
    });

    testWidgets('PrimaryButton pumps without error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: PrimaryButton(label: 'Test')),
        ),
      );
      expect(find.byType(PrimaryButton), findsOneWidget);
    });

    testWidgets('GhostButton pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: GhostButton(label: 'Test')),
        ),
      );
      expect(find.byType(GhostButton), findsOneWidget);
    });

    testWidgets('HintButton pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: HintButton(used: 0)),
        ),
      );
      expect(find.byType(HintButton), findsOneWidget);
    });

    testWidgets('PrimaryButton has elevation 0', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: PrimaryButton(label: 'Test')),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).first,
      );
      expect(button.style?.elevation?.resolve({}), 0);
    });

    testWidgets(
      'PrimaryButton disabled has null onPressed and is ElevatedButton',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: PrimaryButton(label: 'Test')),
          ),
        );
        final button = tester.widget<ElevatedButton>(
          find.byType(ElevatedButton),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('PrimaryButton enabled calls onPressed', (
      WidgetTester tester,
    ) async {
      var n = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: PrimaryButton(label: 'Test', onPressed: () => n++),
          ),
        ),
      );
      await tester.tap(find.byType(ElevatedButton));
      expect(n, 1);
    });

    testWidgets('GhostButton is an OutlinedButton with 2px side', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: GhostButton(label: 'Test')),
        ),
      );
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
      expect(button.style?.side?.resolve({})?.width, 2);
    });

    testWidgets('HintButton has elevation 0', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: HintButton(used: 0)),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).last,
      );
      expect(button.style?.elevation?.resolve({}), 0);
    });

    testWidgets('SurfaceCard default has surfaceRaised background', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SurfaceCard(child: const Text('Test'))),
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SurfaceCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, AppColors.surfaceRaised);
    });

    testWidgets('SurfaceCard default has outline border', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SurfaceCard(child: const Text('Test'))),
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SurfaceCard),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.outline);
      expect(shape.side.width, 2);
    });

    testWidgets('SurfaceCard highlighted has primary border', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SurfaceCard(highlighted: true, child: const Text('Test')),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SurfaceCard),
              matching: find.byType(Material),
            )
            .first,
      );
      final shape = material.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.primary);
      expect(shape.side.width, 2);
    });

    testWidgets('SurfaceCard Material has elevation 0', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SurfaceCard(child: const Text('Test'))),
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SurfaceCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
    });

    testWidgets(
      'SurfaceCard with onTap has InkWell with proper Material wrapper',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: SurfaceCard(onTap: () {}, child: const Text('Test')),
            ),
          ),
        );
        expect(find.byType(InkWell), findsOneWidget);
        expect(find.byType(Material), findsWidgets);
      },
    );

    testWidgets('SurfaceCard with onTap triggers callback on tap', (
      WidgetTester tester,
    ) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SurfaceCard(
              onTap: () {
                tapped = true;
              },
              child: const Text('Test'),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SurfaceCard));
      expect(tapped, isTrue);
    });

    testWidgets('SurfaceCard with onTap wraps Semantics with button flag', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SurfaceCard(onTap: () {}, child: const Text('Test')),
          ),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Test')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('SurfaceCard without onTap has Semantics with no button flag', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SurfaceCard(child: const Text('Test'))),
        ),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Test')),
        isSemantics(isButton: false, hasTapAction: false),
      );
      handle.dispose();
    });

    testWidgets('ScreenHeader back button has tooltip', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ScreenHeader(title: 'Test', onBack: () {}, showMenu: false),
          ),
        ),
      );
      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Quay lại');
    });

    testWidgets('ScreenHeader back button has accessible tap size', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ScreenHeader(title: 'Test', onBack: () {}, showMenu: false),
          ),
        ),
      );
      expect(find.byType(IconButton), findsOneWidget);
      // IconButton default size is 48x48 (Material Design standard)
      final size = tester.getSize(find.byType(IconButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      // Verify tooltip exists
      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Quay lại');
    });

    testWidgets(
      'ScreenHeader menu-button: có ở 800px ngoài shell, showMenu:false thì không, 400px không có',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Future<void> pumpAt(double width, {bool? showMenu}) async {
          tester.view.physicalSize = Size(width, 600);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              home: Scaffold(
                body: ScreenHeader(
                  title: 'Test',
                  onBack: () {},
                  showMenu: showMenu,
                ),
              ),
            ),
          );
        }

        await pumpAt(800);
        expect(find.byKey(const Key('menu-button')), findsOneWidget);

        await pumpAt(800, showMenu: false);
        expect(find.byKey(const Key('menu-button')), findsNothing);

        await pumpAt(400);
        expect(find.byKey(const Key('menu-button')), findsNothing);
      },
    );

    testWidgets('SurfaceCard without onTap still renders InkWell', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SurfaceCard(child: const Text('Test'))),
        ),
      );
      expect(find.byType(InkWell), findsOneWidget);
    });
  });

  group('Focus ring', () {
    test('buildAppTheme has focusColor set to primary', () {
      final theme = buildAppTheme();
      expect(theme.focusColor, AppColors.primary);
    });

    test('buildAppTheme has inputDecorationTheme with focused border', () {
      final theme = buildAppTheme();
      expect(theme.inputDecorationTheme.focusedBorder, isNotNull);
    });

    test('inputDecorationTheme focused border has 2px primary width', () {
      final theme = buildAppTheme();
      final border =
          theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
      expect(border.borderSide.width, 2);
      expect(border.borderSide.color, AppColors.primary);
    });
  });
}
