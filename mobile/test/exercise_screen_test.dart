import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/features/exercise/exercise_screen.dart';
import 'package:smart_coding_study/features/exercise/session_controller.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  String id, {
  Size size = const Size(375, 667),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            home: ExerciseScreen(exerciseId: id),
          );
        },
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('mở Challenge khi chưa có draft; chuyển được 3 tab', (t) async {
    await _pump(t, 'clean-text');
    expect(find.byKey(const Key('challenge-motivation')), findsOneWidget);
    expect(find.text('Code 0/1'), findsOneWidget);
    expect(find.text('ĐỀ BÀI'), findsOneWidget);

    await t.tap(find.text('Solution'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('solution-warning')), findsOneWidget);

    await t.tap(find.byKey(const Key('back-to-code')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('code-scroll')), findsOneWidget);
    expect(find.byKey(const Key('solution-warning')), findsNothing);

    await t.tap(find.text('Challenge'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('start-coding')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('challenge-motivation')), findsNothing);
  });

  testWidgets('có draft → mở thẳng tab Code, badge đếm ô có draft', (t) async {
    await _pump(t, 'split-chunks');
    expect(find.text('Code 1/3'), findsOneWidget);
    expect(find.byKey(const Key('challenge-motivation')), findsNothing);
  });

  testWidgets('segmented ví dụ: mặc định Dự án thật, đổi sang Ví dụ nhỏ', (
    t,
  ) async {
    await _pump(t, 'clean-text');
    final ex = exerciseById('clean-text').challenge;
    await t.ensureVisible(find.byKey(const Key('example-switch')));
    await t.pump();
    expect(find.text(ex.project.input), findsOneWidget);
    await t.tap(find.text('Ví dụ nhỏ'));
    await t.pump();
    expect(find.text(ex.small.input), findsOneWidget);
    expect(find.text(ex.project.input), findsNothing);
  });

  testWidgets('Solution: ẩn mặc định, reveal gọi viewSolution và hiện code', (
    t,
  ) async {
    final c = await _pump(t, 'clean-text');
    await t.tap(find.text('Solution'));
    await t.pumpAndSettle();
    final block = exerciseById('clean-text').blocks.first;

    expect(find.byKey(const Key('solution-code-A')), findsNothing);
    expect(
      c.read(progressProvider)['clean-text']?.solutionViewed ?? {},
      isEmpty,
    );

    await t.ensureVisible(find.byKey(const Key('reveal-A')));
    await t.tap(find.byKey(const Key('reveal-A')));
    await t.pump();

    expect(c.read(progressProvider)['clean-text']!.solutionViewed, {'A'});
    expect(find.byKey(const Key('solution-code-A')), findsOneWidget);
    expect(
      find.textContaining(block.acceptedAnswers.first, findRichText: true),
      findsWidgets,
    );
    expect(find.text(block.explanation), findsOneWidget);
    expect(find.byKey(const Key('reveal-A')), findsNothing);
  });

  testWidgets('bài khoá mở thẳng route → màn khoá, không có tab', (t) async {
    await _pump(t, 'overlap-chunks');
    expect(find.byKey(const Key('locked-title')), findsOneWidget);
    expect(find.byKey(const Key('exercise-tabs')), findsNothing);
  });

  testWidgets('bài đã pass mà bài trước chưa pass → vẫn mở, có tab (INV-08)', (
    t,
  ) async {
    final c = await _pump(t, 'overlap-chunks');
    expect(find.byKey(const Key('locked-title')), findsOneWidget);
    c.read(progressProvider.notifier).markPassed('overlap-chunks');
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('locked-title')), findsNothing);
    expect(find.byKey(const Key('exercise-tabs')), findsOneWidget);
  });

  testWidgets('bài khoá không start đồng hồ', (t) async {
    var now = DateTime(2026, 1, 1, 9);
    final c = await _pump(
      t,
      'overlap-chunks',
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    now = now.add(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('locked-title')), findsOneWidget);
    expect(c.read(sessionProvider('overlap-chunks')).elapsed, Duration.zero);
    await t.pumpWidget(const SizedBox());
  });

  Future<void> idleScenario(WidgetTester t, {required bool tap}) async {
    var now = DateTime(2026, 1, 1, 9);
    await _pump(
      t,
      'clean-text',
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    now = now.add(idleThreshold - const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 1));
    if (tap) {
      await t.ensureVisible(find.byKey(const Key('example-switch')));
      await t.pump();
      await t.tap(find.text('Ví dụ nhỏ'));
      await t.pump();
    }
    now = now.add(const Duration(seconds: 30));
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('đối chứng: không chạm thì hộp thoại idle bật', (t) async {
    await idleScenario(t, tap: false);
    expect(find.byKey(const Key('idle-countdown')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'chạm nút segmented ở Challenge reset idle → không hiện hộp thoại',
    (t) async {
      await idleScenario(t, tap: true);
      expect(find.byKey(const Key('idle-countdown')), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('ô đã xem lời giải hiện sẵn khi mở tab Solution (M1)', (t) async {
    final c = await _pump(t, 'clean-text');
    c.read(progressProvider.notifier).viewSolution('clean-text', 'A');
    await t.tap(find.text('Solution'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('solution-code-A')), findsOneWidget);
    expect(find.byKey(const Key('reveal-A')), findsNothing);
  });

  for (final size in const [Size(375, 667), Size(430, 932)]) {
    testWidgets('không overflow ở ${size.width}x${size.height}', (t) async {
      await _pump(t, 'split-chunks', size: size);
      for (final tab in ['Challenge', 'Solution']) {
        await t.tap(find.text(tab));
        await t.pumpAndSettle();
      }
      for (final l in ['A', 'B']) {
        await t.ensureVisible(find.byKey(Key('reveal-$l')));
        await t.tap(find.byKey(Key('reveal-$l')));
        await t.pump();
      }
      await t.tap(find.text('Challenge'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
