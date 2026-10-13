import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/exercise/exercise_screen.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';

import 'support/content_fixture.dart';

// split-chunks: demo progress đã có draft ô A, ô B đang mở, ô C khoá.
const _id = 'split-chunks';
const _answerB = 'chunks.append(text[i:i + size])';

Future<ProviderContainer> _pump(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late ProviderContainer container;
  await t.pumpWidget(
    ProviderScope(
      overrides: contentOverrides,
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            home: const ExerciseScreen(exerciseId: _id),
          );
        },
      ),
    ),
  );
  await t.pump();
  return container;
}

IconData? _markOf(WidgetTester t, String l) => t
    .widgetList<Icon>(
      find.descendant(
        of: find.byKey(Key('step-$l')),
        matching: find.byType(Icon),
      ),
    )
    .firstOrNull
    ?.icon;

/// Gỡ cây widget để huỷ Timer của session trước khi test kết thúc.
Future<void> _end(WidgetTester t) => t.pumpWidget(const SizedBox());

void main() {
  testWidgets('1280x800: chia đôi, dải bước, gõ đúng → step đổi, không route', (
    t,
  ) async {
    final c = await _pump(t, const Size(1280, 800));
    expect(find.byKey(const Key('exercise-split')), findsOneWidget);
    expect(find.byKey(const Key('exercise-tabs')), findsNothing);
    expect(find.text('Challenge'), findsNothing);
    expect(find.text('Đề'), findsOneWidget);
    expect(find.text('Lời giải'), findsOneWidget);
    expect(find.byKey(const Key('step-strip')), findsOneWidget);
    // Cột trái là Đề; không nút nhảy sang tab Code.
    expect(find.byKey(const Key('challenge-motivation')), findsOneWidget);
    expect(find.byKey(const Key('start-coding')), findsNothing);

    expect(_markOf(t, 'A'), Icons.check);
    expect(_markOf(t, 'B'), isNull);
    expect(_markOf(t, 'C'), Icons.lock_outline);

    await t.enterText(find.byKey(const Key('editor-field')), _answerB);
    await t.pumpAndSettle();
    expect(c.read(progressProvider)[_id]!.drafts['B'], _answerB);
    expect(_markOf(t, 'B'), Icons.check);
    expect(_markOf(t, 'C'), isNull);
    // Không push route: vẫn cùng một màn chia đôi.
    expect(find.byKey(const Key('exercise-split')), findsOneWidget);
    expect(find.byKey(const Key('editor-done')), findsNothing);
    expect(t.takeException(), isNull);
    await _end(t);
  });

  testWidgets(
    '1280x800: tab Lời giải không có nút back-to-code, không ném lỗi',
    (t) async {
      await _pump(t, const Size(1280, 800));
      await t.tap(find.text('Lời giải'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('solution-warning')), findsOneWidget);
      expect(find.byKey(const Key('back-to-code')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('800x800 (dưới split): ba tab như cũ', (t) async {
    await _pump(t, const Size(800, 800));
    expect(find.byKey(const Key('exercise-tabs')), findsOneWidget);
    expect(find.byKey(const Key('exercise-split')), findsNothing);
    expect(find.text('Code 1/3'), findsOneWidget);
    expect(find.byKey(const Key('step-strip')), findsNothing);
    await _end(t);
  });

  testWidgets('menu-button: 1 cái ở ≥nav, không có ở 400', (t) async {
    await _pump(t, const Size(1280, 800));
    expect(find.byKey(const Key('menu-button')), findsOneWidget);
    await _pump(t, const Size(800, 800));
    expect(find.byKey(const Key('menu-button')), findsOneWidget);
    await _pump(t, const Size(400, 800));
    expect(find.byKey(const Key('menu-button')), findsNothing);
    await _end(t);
  });

  testWidgets('đổi cỡ 1280 → 800 → 1280 không mất draft', (t) async {
    final c = await _pump(t, const Size(1280, 800));
    await t.enterText(find.byKey(const Key('editor-field')), _answerB);
    await t.pumpAndSettle();

    t.view.physicalSize = const Size(800, 800);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exercise-tabs')), findsOneWidget);
    expect(find.text('Code 2/3'), findsOneWidget);
    expect(c.read(progressProvider)[_id]!.drafts['B'], _answerB);

    t.view.physicalSize = const Size(1280, 800);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exercise-split')), findsOneWidget);
    expect(c.read(progressProvider)[_id]!.drafts['B'], _answerB);
    expect(_markOf(t, 'B'), Icons.check);
    expect(t.takeException(), isNull);
    await _end(t);
  });
}
