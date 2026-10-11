import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/judge_client.dart';
import 'support/content_fixture.dart';
import 'package:smart_coding_study/domain/merge.dart';
import 'package:smart_coding_study/features/exercise/code_tab.dart';
import 'package:smart_coding_study/features/exercise/session_controller.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';

class FakeJudge implements JudgeClient {
  FakeJudge(this.responder);

  Future<JudgeResult> Function(String code) responder;
  final List<String> calls = [];

  @override
  Future<JudgeResult> run(String exerciseId, String code) {
    calls.add(code);
    return responder(code);
  }
}

const _id = 'split-chunks';
final _ex = testContent.exerciseById(_id);

const _passed = JudgeResult(
  status: JudgeStatus.passed,
  tests: [
    JudgeTest(
      call: "split_chunks('abcd', 2)",
      expected: "['ab', 'cd']",
      actual: "['ab', 'cd']",
      passed: true,
    ),
    JudgeTest(
      call: "split_chunks('', 3)",
      expected: '[]',
      actual: '[]',
      passed: true,
    ),
  ],
);

Map<String, String> _solution() => {
  for (final b in _ex.blocks) b.label: b.acceptedAnswers.first,
};

class _H {
  _H(this.container, this.judge);
  final ProviderContainer container;
  final FakeJudge judge;
  ExerciseProgress? get progress => container.read(progressProvider)[_id];
}

Future<_H> _pump(
  WidgetTester t,
  FakeJudge judge, {
  Map<String, String> drafts = const {},
  double keyboard = 0,
}) async {
  t.view.physicalSize = const Size(375, 667);
  t.view.devicePixelRatio = 1;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [...contentOverrides, judgeClientProvider.overrideWithValue(judge)],
  );
  addTearDown(container.dispose);
  for (final e in drafts.entries) {
    container.read(progressProvider.notifier).saveDraft(_id, e.key, e.value);
  }
  final router = GoRouter(
    initialLocation: '/exercise/$_id',
    routes: [
      GoRoute(
        path: '/exercise/:id',
        builder: (c, s) => Scaffold(
          body: s.pathParameters['id'] == _id
              ? CodeTab(exercise: _ex)
              : Text('NEXT ${s.pathParameters['id']}'),
        ),
      ),
    ],
  );
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildAppTheme(brightness: Brightness.light),
        routerConfig: router,
      ),
    ),
  );
  await t.pump();
  return _H(container, judge);
}

Future<void> _run(WidgetTester t) async {
  await t.tap(find.byKey(const Key('run-button')));
  await t.pumpAndSettle();
}

Color _frameColor(WidgetTester t, String label) {
  final box = t.widget<Container>(find.byKey(Key('cell-$label-frame')));
  return ((box.decoration as BoxDecoration).border as Border).top.color;
}

void main() {
  testWidgets('notebook: ô khoá + 3 ô TODO + ghi chú + nút Gợi ý/Run', (
    t,
  ) async {
    await _pump(t, FakeJudge((_) async => _passed));
    expect(find.byKey(const Key('locked-cell')), findsWidgets);
    expect(find.text('có sẵn'), findsWidgets);
    for (final l in ['A', 'B', 'C']) {
      expect(find.byKey(Key('cell-$l-field')), findsOneWidget);
    }
    expect(find.text('trong hàm'), findsWidgets);
    expect(find.text('trong vòng for'), findsOneWidget);
    expect(find.byKey(const Key('indent-note')), findsOneWidget);
    expect(find.text('Gợi ý ô A'), findsOneWidget);
    expect(find.text('Run tất cả'), findsOneWidget);
  });

  testWidgets('ô trống chặn Run: không gọi judge, báo ô và viền đỏ', (t) async {
    final judge = FakeJudge((_) async => _passed);
    final h = await _pump(t, judge); // seed chỉ có draft ô A
    await _run(t);
    expect(judge.calls, isEmpty);
    expect(find.text('Ô B, C còn trống'), findsOneWidget);
    expect(_frameColor(t, 'B'), isNot(Colors.transparent));
    expect(_frameColor(t, 'A'), Colors.transparent);
    expect(h.progress?.passed ?? false, isFalse);
  });

  testWidgets('ô chỉ có khoảng trắng coi là trống', (t) async {
    final judge = FakeJudge((_) async => _passed);
    await _pump(t, judge, drafts: {..._solution(), 'B': '  \n  '});
    await _run(t);
    expect(judge.calls, isEmpty);
    expect(find.text('Ô B còn trống'), findsOneWidget);
  });

  testWidgets('passed ⇒ markPassed, Bài tiếp theo dẫn tới overlap-chunks', (
    t,
  ) async {
    final judge = FakeJudge((_) async => _passed);
    final h = await _pump(t, judge, drafts: _solution());
    expect(h.progress?.passed ?? false, isFalse);
    await _run(t);
    expect(judge.calls, hasLength(1));
    expect(judge.calls.single, mergeCells(_ex, _solution()).code);
    expect(h.progress!.passed, isTrue);
    expect(find.text('2/2 test đạt'), findsOneWidget);
    expect(find.byKey(const Key('merged-code')), findsOneWidget);
    expect(find.byKey(const Key('edit-again')), findsOneWidget);
    // dòng khoá không có cột nguồn, dòng ô có chữ nguồn
    expect(t.widget<Text>(find.byKey(const Key('merged-origin-0'))).data, '');
    expect(t.widget<Text>(find.byKey(const Key('merged-origin-2'))).data, 'A');

    await t.tap(find.byKey(const Key('next-exercise')));
    await t.pumpAndSettle();
    expect(find.text('NEXT overlap-chunks'), findsOneWidget);
  });

  testWidgets('lỗi cú pháp ở dòng của ô B ⇒ viền đỏ đúng ô B (INV-05)', (
    t,
  ) async {
    final cells = _solution();
    final merged = mergeCells(_ex, cells);
    final line = merged.lineOrigin.indexOf('B') + 1;
    final judge = FakeJudge(
      (_) async => JudgeResult(
        status: JudgeStatus.error,
        error: JudgeError(
          kind: 'syntax',
          line: line,
          message: 'invalid syntax',
        ),
      ),
    );
    final h = await _pump(t, judge, drafts: cells);
    await _run(t);
    expect(_frameColor(t, 'B'), isNot(Colors.transparent));
    expect(_frameColor(t, 'A'), Colors.transparent);
    expect(_frameColor(t, 'C'), Colors.transparent);
    expect(find.text('Lỗi ở ô B: invalid syntax'), findsOneWidget);
    expect(find.text('Lỗi cú pháp'), findsOneWidget);
    expect(h.progress?.passed ?? false, isFalse);
  });

  testWidgets('lỗi ở dòng khoá ⇒ nói lỗi ở phần có sẵn, không đổ cho ô nào', (
    t,
  ) async {
    final judge = FakeJudge(
      (_) async => const JudgeResult(
        status: JudgeStatus.error,
        error: JudgeError(kind: 'syntax', line: 1, message: 'oops'),
      ),
    );
    await _pump(t, judge, drafts: _solution());
    await _run(t);
    expect(find.byKey(const Key('run-error-locked')), findsOneWidget);
    for (final l in ['A', 'B', 'C']) {
      expect(_frameColor(t, l), Colors.transparent);
      expect(find.byKey(Key('cell-$l-error')), findsNothing);
    }
  });

  testWidgets(
    'failed ⇒ không markPassed, hiện expected và gợi ý kiểm tra ô sai',
    (t) async {
      final judge = FakeJudge(
        (_) async => const JudgeResult(
          status: JudgeStatus.failed,
          tests: [
            JudgeTest(
              call: "split_chunks('abcd', 2)",
              expected: "['ab', 'cd']",
              actual: "['ab']",
              passed: false,
            ),
            JudgeTest(
              call: "split_chunks('', 3)",
              expected: '[]',
              actual: '[]',
              passed: true,
            ),
          ],
        ),
      );
      final h = await _pump(
        t,
        judge,
        drafts: {..._solution(), 'C': 'return chunk'},
      );
      await _run(t);
      expect(h.progress?.passed ?? false, isFalse);
      expect(find.text('1/2 test đạt'), findsOneWidget);
      expect(find.byKey(const Key('test-expected-0')), findsOneWidget);
      expect(find.byKey(const Key('test-expected-1')), findsNothing);
      expect(find.byKey(const Key('cell-C-recheck')), findsOneWidget);
      expect(find.byKey(const Key('cell-A-recheck')), findsNothing);
      expect(find.byKey(const Key('next-exercise')), findsNothing);
      expect(find.byKey(const Key('run-button')), findsOneWidget);
    },
  );

  testWidgets('unavailable ⇒ Thử lại gọi judge lần nữa, không markPassed', (
    t,
  ) async {
    var n = 0;
    final judge = FakeJudge(
      (_) async => n++ == 0
          ? const JudgeResult.unavailable('Không kết nối được')
          : _passed,
    );
    final h = await _pump(t, judge, drafts: _solution());
    await _run(t);
    expect(h.progress?.passed ?? false, isFalse);
    expect(find.byKey(const Key('run-unavailable')), findsOneWidget);
    await t.tap(find.byKey(const Key('retry-button')));
    await t.pumpAndSettle();
    expect(judge.calls, hasLength(2));
    expect(h.progress!.passed, isTrue);
  });

  testWidgets('đang chạy: có spinner, bấm Run lặp không gọi judge thêm', (
    t,
  ) async {
    final c = Completer<JudgeResult>();
    final judge = FakeJudge((_) => c.future);
    await _pump(t, judge, drafts: _solution());
    await t.tap(find.byKey(const Key('run-button')));
    await t.pump();
    expect(find.byKey(const Key('run-spinner')), findsOneWidget);
    await t.tap(find.byKey(const Key('run-button')), warnIfMissed: false);
    await t.pump();
    expect(judge.calls, hasLength(1));
    c.complete(_passed);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('run-spinner')), findsNothing);
  });

  testWidgets('draft lưu theo label và còn nguyên khi dựng lại tab', (t) async {
    final h = await _pump(t, FakeJudge((_) async => _passed));
    await t.enterText(find.byKey(const Key('cell-C-field')), 'return chunks');
    await t.pump();
    expect(h.progress!.drafts['C'], 'return chunks');

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: Scaffold(body: CodeTab(exercise: _ex)),
        ),
      ),
    );
    await t.pump();
    final field = find.descendant(
      of: find.byKey(const Key('cell-C-field')),
      matching: find.byType(EditableText),
    );
    expect(t.widget<EditableText>(field).controller.text, 'return chunks');
  });

  testWidgets('mở tab có draft rồi focus ô ngay: không ném lỗi; Gợi ý ≤3', (
    t,
  ) async {
    final h = await _pump(
      t,
      FakeJudge((_) async => _passed),
      drafts: _solution(),
    );
    await t.tap(find.byKey(const Key('cell-B-field')));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Gợi ý ô B'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      final btn = find.byKey(const Key('hint-button'));
      await t.tap(btn);
      await t.pump();
    }
    expect(h.progress!.hintsUsed['B'], 3);
    expect(find.byKey(const Key('hint-B-0')), findsOneWidget);
    expect(find.byKey(const Key('hint-B-2')), findsOneWidget);
    expect(find.byKey(const Key('hint-A-0')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('không overflow ở 375x667 khi bàn phím mở (kể cả có kết quả)', (
    t,
  ) async {
    final judge = FakeJudge((_) async => _passed);
    await _pump(t, judge, drafts: _solution(), keyboard: 300);
    await _run(t);
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const Key('edit-again')));
    await t.pump();
    await t.tap(find.byKey(const Key('cell-A-field')));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
