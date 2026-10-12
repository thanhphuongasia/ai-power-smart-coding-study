import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/judge_client.dart';
import 'support/content_fixture.dart';
import 'package:smart_coding_study/domain/merge.dart';
import 'package:smart_coding_study/features/exercise/cell_editor_page.dart';
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
  bool inline = false,
  Brightness brightness = Brightness.light,
  Size size = const Size(375, 667),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [
      ...contentOverrides,
      judgeClientProvider.overrideWithValue(judge),
    ],
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
              ? CodeTab(exercise: _ex, inlineEditor: inline)
              : Text('NEXT ${s.pathParameters['id']}'),
        ),
      ),
    ],
  );
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildAppTheme(brightness: brightness),
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

/// Chạm bản xem trước của ô → màn soạn code toàn màn hình.
Future<void> _openEditor(WidgetTester t, String label) async {
  await t.tap(find.byKey(Key('cell-$label-field')));
  await t.pumpAndSettle();
}

Color _frameColor(WidgetTester t, String label) {
  final box = t.widget<Container>(find.byKey(Key('cell-$label-frame')));
  return ((box.decoration as BoxDecoration).border as Border).top.color;
}

void main() {
  testWidgets('notebook: seed A xong ⇒ A thu gọn ✓, B mở, C khoá', (t) async {
    await _pump(t, FakeJudge((_) async => _passed));
    expect(find.byKey(const Key('locked-cell')), findsWidgets);
    expect(find.text('có sẵn'), findsWidgets);
    expect(find.byKey(const Key('cell-A-collapsed')), findsOneWidget);
    expect(find.byKey(const Key('cell-A-field')), findsNothing);
    expect(find.byKey(const Key('cell-B-field')), findsOneWidget);
    expect(find.byKey(const Key('cell-C-locked')), findsOneWidget);
    expect(find.byKey(const Key('cell-C-field')), findsNothing);
    expect(find.text('Làm xong ô B để mở'), findsOneWidget);
    expect(find.text('trong vòng for'), findsOneWidget);
    expect(find.byKey(const Key('indent-note')), findsOneWidget);
    expect(find.text('Gợi ý ô B'), findsOneWidget);
    expect(find.text('Run tất cả'), findsOneWidget);
  });

  testWidgets('chạm ô ⇒ màn soạn toàn màn hình chỉ có editor + phím; Xong '
      'quay lại notebook', (t) async {
    await _pump(t, FakeJudge((_) async => _passed), keyboard: 300);
    expect(find.byKey(const Key('symbol-(')), findsNothing);
    await _openEditor(t, 'B');
    expect(find.byKey(const Key('editor-field')), findsOneWidget);
    expect(find.byKey(const Key('symbol-(')), findsOneWidget);
    expect(find.text('Cắt và thêm vào danh sách'), findsOneWidget);
    expect(find.byKey(const Key('run-button')), findsNothing);
    expect(find.byKey(const Key('locked-cell')), findsNothing);
    expect(t.takeException(), isNull);

    await t.tap(find.byKey(const Key('editor-done')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('editor-field')), findsNothing);
    expect(find.byKey(const Key('run-button')), findsOneWidget);
  });

  testWidgets('B khớp ⇒ màn soạn chuyển sang C (focus); C khớp ⇒ đóng, '
      'notebook thu gọn hết', (t) async {
    final h = await _pump(t, FakeJudge((_) async => _passed));
    await _openEditor(t, 'B');
    await t.enterText(find.byKey(const Key('editor-field')), 'chunks.append(');
    await t.pump();
    expect(find.text('Cắt và thêm vào danh sách'), findsOneWidget);

    await t.enterText(
      find.byKey(const Key('editor-field')),
      'chunks.append(text[i : i+size])', // khác khoảng trắng vẫn khớp
    );
    await t.pumpAndSettle();
    expect(find.text('Trả về kết quả'), findsOneWidget);
    expect(find.byKey(const Key('editor-advanced')), findsOneWidget);
    final c = find.descendant(
      of: find.byKey(const Key('editor-field')),
      matching: find.byType(EditableText),
    );
    expect(t.widget<EditableText>(c).controller.text, '');
    expect(t.widget<EditableText>(c).focusNode.hasFocus, isTrue);
    expect(h.progress!.drafts['B'], 'chunks.append(text[i : i+size])');

    await t.enterText(find.byKey(const Key('editor-field')), 'return chunks');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('editor-field')), findsNothing);
    for (final l in ['A', 'B', 'C']) {
      expect(find.byKey(Key('cell-$l-collapsed')), findsOneWidget);
    }
  });

  testWidgets('chạm ô đã xong ⇒ mở lại sửa được; ô đang mở thu gọn', (t) async {
    await _pump(t, FakeJudge((_) async => _passed));
    await t.tap(find.byKey(const Key('cell-A-collapsed')));
    await t.pump();
    expect(find.byKey(const Key('cell-A-field')), findsOneWidget);
    expect(find.byKey(const Key('cell-B-field')), findsNothing);
    expect(find.byKey(const Key('cell-B-collapsed')), findsOneWidget);

    // Sửa A thành sai ⇒ B, C khoá lại.
    await _openEditor(t, 'A');
    await t.enterText(find.byKey(const Key('editor-field')), 'for i in');
    await t.pump();
    await t.tap(find.byKey(const Key('editor-done')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('cell-B-locked')), findsOneWidget);
    expect(find.byKey(const Key('cell-C-locked')), findsOneWidget);
  });

  testWidgets('bài đã passed ⇒ không khoá ô nào dù khác đáp án mẫu', (t) async {
    final h = await _pump(
      t,
      FakeJudge((_) async => _passed),
      drafts: {'A': 'for j in range(0, len(text), size):'},
    );
    expect(find.byKey(const Key('cell-B-locked')), findsOneWidget);
    h.container.read(progressProvider.notifier).markPassed(_id);
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
    expect(find.byKey(const Key('cell-B-locked')), findsNothing);
    expect(find.byKey(const Key('cell-B-collapsed')), findsOneWidget);
  });

  testWidgets('ô trống chặn Run: không gọi judge, báo ô và viền đỏ', (t) async {
    final judge = FakeJudge((_) async => _passed);
    final h = await _pump(t, judge); // seed chỉ có draft ô A
    await _run(t);
    expect(judge.calls, isEmpty);
    expect(find.text('Ô B, C còn trống'), findsOneWidget);
    expect(_frameColor(t, 'B'), isNot(Colors.transparent));
    expect(find.byKey(const Key('cell-A-collapsed')), findsOneWidget);
    expect(find.byKey(const Key('cell-C-locked')), findsOneWidget);
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
    // Ô lỗi tự mở dù đã khớp đáp án; ô khác vẫn thu gọn.
    expect(_frameColor(t, 'B'), isNot(Colors.transparent));
    expect(find.byKey(const Key('cell-A-collapsed')), findsOneWidget);
    expect(find.byKey(const Key('cell-C-collapsed')), findsOneWidget);
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
      expect(find.byKey(Key('cell-$l-collapsed')), findsOneWidget);
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
    await _openEditor(t, 'B');
    await t.enterText(find.byKey(const Key('editor-field')), 'chunks.append(');
    await t.pump();
    expect(h.progress!.drafts['B'], 'chunks.append(');

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
    expect(
      find.descendant(
        of: find.byKey(const Key('cell-B-field')),
        matching: find.textContaining('chunks.append(', findRichText: true),
      ),
      findsOneWidget,
    );
    await _openEditor(t, 'B');
    final field = find.descendant(
      of: find.byKey(const Key('editor-field')),
      matching: find.byType(EditableText),
    );
    expect(t.widget<EditableText>(field).controller.text, 'chunks.append(');
  });

  testWidgets('mở tab có draft rồi focus ô ngay: không ném lỗi; Gợi ý ≤3', (
    t,
  ) async {
    final h = await _pump(
      t,
      FakeJudge((_) async => _passed),
      drafts: _solution(),
    );
    // Đủ đáp án ⇒ mọi ô thu gọn; chạm để mở rồi focus.
    await t.tap(find.byKey(const Key('cell-B-collapsed')));
    await t.pump();
    expect(find.text('Gợi ý ô B'), findsOneWidget);
    await _openEditor(t, 'B');
    expect(t.takeException(), isNull);

    // Gợi ý ngay trong màn soạn, tối đa 3.
    for (var i = 0; i < 4; i++) {
      await t.tap(find.byKey(const Key('editor-hint')));
      await t.pump();
    }
    expect(h.progress!.hintsUsed['B'], 3);
    expect(find.byKey(const Key('editor-hint-2')), findsOneWidget);
    await t.tap(find.byKey(const Key('editor-done')));
    await t.pumpAndSettle();
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
    await t.tap(find.byKey(const Key('cell-A-collapsed')));
    await t.pump();
    await _openEditor(t, 'A');
    expect(t.takeException(), isNull);
  });

  group('inlineEditor', () {
    Finder inlineField() => find.descendant(
      of: find.byKey(const Key('editor-field')),
      matching: find.byType(EditableText),
    );

    testWidgets('mặc định (false): chạm ô vẫn push route, không có dải bước', (
      t,
    ) async {
      await _pump(t, FakeJudge((_) async => _passed));
      expect(find.byKey(const Key('step-strip')), findsNothing);
      expect(find.byKey(const Key('editor-field')), findsNothing);
      await _openEditor(t, 'B');
      expect(find.byKey(const Key('editor-done')), findsOneWidget);
      expect(find.byKey(const Key('run-button')), findsNothing);
    });

    testWidgets('true: chạm ô không push route; editor nằm trong notebook', (
      t,
    ) async {
      await _pump(t, FakeJudge((_) async => _passed), inline: true);
      // Ô B đang mở: editor inline ngay trong notebook, notebook còn nguyên.
      expect(find.byKey(const Key('editor-field')), findsOneWidget);
      expect(find.byKey(const Key('cell-B-field')), findsNothing);
      expect(find.byKey(const Key('editor-done')), findsNothing);
      expect(find.byKey(const Key('run-button')), findsOneWidget);
      expect(find.byKey(const Key('locked-cell')), findsWidgets);
      for (final l in ['A', 'B', 'C']) {
        expect(find.byKey(Key('step-$l')), findsOneWidget);
      }
      // Chạm ô A đã xong: mở inline tại chỗ, không có route mới.
      await t.tap(find.byKey(const Key('cell-A-collapsed')));
      await t.pump();
      expect(find.byKey(const Key('cell-A-header')), findsOneWidget);
      expect(find.byKey(const Key('editor-field')), findsOneWidget);
      expect(find.byType(CellEditorPage), findsNothing);
      expect(find.byKey(const Key('run-button')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('gõ đúng đáp án: step đổi, ô kế mở, draft qua saveDraft', (
      t,
    ) async {
      final h = await _pump(t, FakeJudge((_) async => _passed), inline: true);
      IconData? markOf(String l) => t
          .widgetList<Icon>(
            find.descendant(
              of: find.byKey(Key('step-$l')),
              matching: find.byType(Icon),
            ),
          )
          .firstOrNull
          ?.icon;
      expect(markOf('A'), Icons.check);
      expect(markOf('B'), isNull); // đang làm: hiện số
      expect(markOf('C'), Icons.lock_outline);

      await t.enterText(
        find.byKey(const Key('editor-field')),
        'chunks.append(text[i:i + size])',
      );
      await t.pumpAndSettle();
      expect(h.progress!.drafts['B'], 'chunks.append(text[i:i + size])');
      expect(markOf('B'), Icons.check);
      expect(markOf('C'), isNull);
      expect(find.byKey(const Key('cell-B-collapsed')), findsOneWidget);
      // Ô C mở ngay trong notebook, không pop route nào.
      expect(t.widget<EditableText>(inlineField()).controller.text, '');
      expect(find.byKey(const Key('cell-C-header')), findsOneWidget);

      await t.enterText(find.byKey(const Key('editor-field')), 'return chunks');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('editor-field')), findsNothing);
      expect(h.progress!.drafts['C'], 'return chunks');
      for (final l in ['A', 'B', 'C']) {
        expect(find.byKey(Key('cell-$l-collapsed')), findsOneWidget);
      }
    });

    testWidgets('chạm step ô đã mở khoá mở ô đó; ô khoá thì không', (t) async {
      await _pump(t, FakeJudge((_) async => _passed), inline: true);
      await t.tap(find.byKey(const Key('step-C'))); // C đang khoá
      await t.pump();
      expect(find.byKey(const Key('cell-C-locked')), findsOneWidget);
      expect(find.byKey(const Key('cell-B-header')), findsOneWidget);

      await t.tap(find.byKey(const Key('step-A')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('cell-A-header')), findsOneWidget);
      expect(find.byKey(const Key('cell-B-collapsed')), findsOneWidget);
      expect(find.byKey(const Key('editor-field')), findsOneWidget);
    });

    testWidgets('Run, Gợi ý dùng chung đường cũ khi inline', (t) async {
      final judge = FakeJudge((_) async => _passed);
      final h = await _pump(t, judge, inline: true, drafts: _solution());
      await _run(t);
      expect(judge.calls, hasLength(1));
      expect(h.progress!.passed, isTrue);

      await t.tap(find.byKey(const Key('edit-again')));
      await t.pump();
      await t.tap(find.byKey(const Key('cell-B-collapsed')));
      await t.pump();
      await t.tap(find.byKey(const Key('hint-button')));
      await t.pump();
      expect(h.progress!.hintsUsed['B'], 1);
      expect(find.byKey(const Key('hint-B-0')), findsOneWidget);
    });

    testWidgets('ghost + vocab nối vào editor inline (chip nhận gợi ý)', (
      t,
    ) async {
      final h = await _pump(t, FakeJudge((_) async => _passed), inline: true);
      await t.enterText(find.byKey(const Key('editor-field')), 'chunks.');
      await t.pump();
      expect(find.byKey(const Key('ghost-accept')), findsOneWidget);
      // Ghost chỉ phủ hiển thị: draft chưa chứa phần gợi ý (INV-04).
      expect(h.progress!.drafts['B'], 'chunks.');
      await t.tap(find.byKey(const Key('ghost-accept')));
      await t.pumpAndSettle();
      expect(h.progress!.drafts['B'], _ex.blocks[1].acceptedAnswers.first);
    });

    testWidgets('route cũng có ghost-accept (answers nối ở cả hai nhánh)', (
      t,
    ) async {
      await _pump(t, FakeJudge((_) async => _passed));
      await _openEditor(t, 'B');
      await t.enterText(find.byKey(const Key('editor-field')), 'chunks.');
      await t.pump();
      expect(find.byKey(const Key('ghost-accept')), findsOneWidget);
    });
  });

  group('nền khối code (INV-08)', () {
    Color? fillOf(WidgetTester t, Finder f) {
      final box = t.widget<Container>(f);
      return (box.decoration as BoxDecoration).color;
    }

    for (final b in Brightness.values) {
      testWidgets('codeSurface ở theme ${b.name}: ô khoá, xem trước, editor', (
        t,
      ) async {
        await _pump(
          t,
          FakeJudge((_) async => _passed),
          brightness: b,
          drafts: {'B': 'x = 1'},
        );
        final palette = buildAppTheme(brightness: b).extension<AppPalette>()!;
        expect(
          fillOf(t, find.byKey(const Key('locked-cell')).first),
          palette.codeSurface,
        );
        final preview = find.descendant(
          of: find.byKey(const Key('cell-B-field')),
          matching: find.byType(Container),
        );
        expect(fillOf(t, preview.first), palette.codeSurface);

        await _openEditor(t, 'B');
        final field = t.widget<CodeField>(
          find.byKey(const Key('editor-field')),
        );
        expect(field.background, palette.codeSurface);
      });
    }
  });
}
