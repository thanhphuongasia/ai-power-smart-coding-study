// Test recolor cho màn browse (T-06): màu trạng thái ExerciseRow lấy từ
// palette (sáng + tối), topic_detail không còn Colors.white/black, và không
// overflow ở bề rộng 400 / 800. Hình học và Key được browse_screens_test giữ.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/domain/models.dart';
import 'package:smart_coding_study/features/browse/exercise_row.dart';
import 'package:smart_coding_study/features/browse/theme_detail_screen.dart';
import 'package:smart_coding_study/features/browse/topic_detail_screen.dart';
import 'package:smart_coding_study/features/exercise/session_controller.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'support/content_fixture.dart';

Exercise _firstExercise() =>
    testContent.themes.first.topics.first.allFiles.first.exercises.first;

Future<void> _pumpRow(
  WidgetTester tester, {
  required Brightness brightness,
  required bool unlocked,
  ExerciseProgress? progress,
}) async {
  final exercise = _firstExercise();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...contentOverrides,
        exerciseUnlockedProvider.overrideWith((ref, id) => unlocked),
      ],
      child: MaterialApp(
        theme: buildAppTheme(brightness: brightness),
        home: Scaffold(
          body: ExerciseRow(exercise: exercise, progress: progress),
        ),
      ),
    ),
  );
  await tester.pump();
}

Color _iconColor(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon)).color!;

void _setWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

GoRouter _router(String location) => GoRouter(
  initialLocation: location,
  routes: [
    GoRoute(
      path: '/theme/:themeId',
      builder: (context, state) =>
          ThemeDetailScreen(state.pathParameters['themeId']!),
    ),
    GoRoute(
      path: '/topic/:topicId',
      builder: (context, state) =>
          TopicDetailScreen(state.pathParameters['topicId']!),
    ),
  ],
);

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final p = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final label = brightness == Brightness.dark ? 'tối' : 'sáng';

    group('ExerciseRow theme $label', () {
      testWidgets('Khoá: icon inkMuted', (tester) async {
        await _pumpRow(tester, brightness: brightness, unlocked: false);
        expect(find.text('Khoá'), findsOneWidget);
        expect(_iconColor(tester, Icons.lock_outline), p.inkMuted);
      });

      testWidgets('Đã xong: icon success', (tester) async {
        await _pumpRow(
          tester,
          brightness: brightness,
          unlocked: true,
          progress: const ExerciseProgress(passed: true),
        );
        expect(find.text('Đã xong'), findsOneWidget);
        expect(_iconColor(tester, Icons.check_circle), p.success);
      });

      testWidgets('Đang dở: icon primary', (tester) async {
        await _pumpRow(
          tester,
          brightness: brightness,
          unlocked: true,
          progress: const ExerciseProgress(drafts: {'0': 'print(1)'}),
        );
        expect(find.text('Đang dở'), findsOneWidget);
        expect(_iconColor(tester, Icons.timelapse), p.primary);
      });

      testWidgets('Mới: icon inkMuted', (tester) async {
        await _pumpRow(tester, brightness: brightness, unlocked: true);
        expect(find.text('Mới'), findsOneWidget);
        expect(_iconColor(tester, Icons.circle_outlined), p.inkMuted);
      });
    });
  }

  test('topic_detail_screen.dart không còn Colors.white / Colors.black', () {
    final src = File(
      'lib/features/browse/topic_detail_screen.dart',
    ).readAsStringSync();
    expect(src.contains('Colors.white'), isFalse);
    expect(src.contains('Colors.black'), isFalse);
  });

  for (final width in [400.0, 800.0]) {
    testWidgets('Theme detail không overflow ở width $width', (tester) async {
      _setWidth(tester, width);
      final theme = testContent.themes.first;
      await tester.pumpWidget(
        ProviderScope(
          overrides: contentOverrides,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _router('/theme/${theme.id}'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byKey(Key('topic-${theme.topics.first.id}')), findsOneWidget);
    });
  }

  // Topic detail tràn ngang ở ≤412px sẵn có trên main (font Ahem trong test); xem backlog run issue29-reskin
  testWidgets('Topic detail không overflow ở width 800', (tester) async {
    _setWidth(tester, 800);
    final topic = testContent.themes.first.topics.first;
    await tester.pumpWidget(
      ProviderScope(
        overrides: contentOverrides,
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: _router('/topic/${topic.id}'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
