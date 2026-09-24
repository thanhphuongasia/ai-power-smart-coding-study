import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/shared/widgets.dart';

void main() {
  group('AppColors', () {
    test('surface color is correct', () {
      expect(AppColors.surface, const Color(0xFF111418));
    });

    test('surfaceRaised color is correct', () {
      expect(AppColors.surfaceRaised, const Color(0xFF1b1f25));
    });

    test('outline color is correct', () {
      expect(AppColors.outline, const Color(0xFF626b78));
    });

    test('ink color is correct', () {
      expect(AppColors.ink, const Color(0xFFe7e9ee));
    });

    test('inkMuted color is correct', () {
      expect(AppColors.inkMuted, const Color(0xFF9aa3b0));
    });

    test('primary color is correct', () {
      expect(AppColors.primary, const Color(0xFF5ccfb0));
    });

    test('onPrimary color is correct', () {
      expect(AppColors.onPrimary, const Color(0xFF06231b));
    });

    test('accent color is correct', () {
      expect(AppColors.accent, const Color(0xFFf5b94a));
    });

    test('onAccent color is correct', () {
      expect(AppColors.onAccent, const Color(0xFF2a1a00));
    });

    test('danger color is correct', () {
      expect(AppColors.danger, const Color(0xFFff7b72));
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
          home: Scaffold(
            body: SurfaceCard(
              child: const Text('Test'),
            ),
          ),
        ),
      );
      expect(find.byType(SurfaceCard), findsOneWidget);
    });

    testWidgets('TagChip pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: TagChip('tag'),
          ),
        ),
      );
      expect(find.byType(TagChip), findsOneWidget);
    });

    testWidgets('ResultBadge pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: ResultBadge(passed: true),
          ),
        ),
      );
      expect(find.byType(ResultBadge), findsOneWidget);
    });

    testWidgets('ResultBadge shows correct text for passed', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: ResultBadge(passed: true),
          ),
        ),
      );
      expect(find.text('Đúng'), findsOneWidget);
    });

    testWidgets('ResultBadge shows correct text for failed', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: ResultBadge(passed: false),
          ),
        ),
      );
      expect(find.text('Chưa đúng'), findsOneWidget);
    });

    testWidgets('TimerPill pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: TimerPill(
              Duration.zero,
            ),
          ),
        ),
      );
      expect(find.byType(TimerPill), findsOneWidget);
    });

    testWidgets('ThinProgressBar pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ThinProgressBar(
              value: 0.5,
            ),
          ),
        ),
      );
      expect(find.byType(ThinProgressBar), findsOneWidget);
    });

    testWidgets('ScreenHeader pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: ScreenHeader(
              title: 'Test',
            ),
          ),
        ),
      );
      expect(find.byType(ScreenHeader), findsOneWidget);
    });

    testWidgets('SectionLabel pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SectionLabel('label'),
          ),
        ),
      );
      expect(find.byType(SectionLabel), findsOneWidget);
    });

    testWidgets('PrimaryButton pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: PrimaryButton(label: 'Test'),
          ),
        ),
      );
      expect(find.byType(PrimaryButton), findsOneWidget);
    });

    testWidgets('GhostButton pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: GhostButton(label: 'Test'),
          ),
        ),
      );
      expect(find.byType(GhostButton), findsOneWidget);
    });

    testWidgets('HintButton pumps without error', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: HintButton(used: 0),
          ),
        ),
      );
      expect(find.byType(HintButton), findsOneWidget);
    });
  });
}
