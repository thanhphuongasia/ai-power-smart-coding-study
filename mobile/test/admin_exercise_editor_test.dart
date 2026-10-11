import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:smart_coding_study/data/admin_repository.dart';
import 'package:smart_coding_study/features/admin/admin_controller.dart';
import 'package:smart_coding_study/features/admin/exercise_editor.dart';

import 'support/admin_fixture.dart';

/// Bài đầy đủ: template có 2 ô, đáp án chuẩn ghép ra đúng lời giải.
Map<String, dynamic> fullExercise() => {
  'id': 'e1',
  'title': 'One',
  'class_name': 'Box',
  'function_name': 'fill',
  'params': ['a', 'b'],
  'template':
      'class Box:\n    def fill(self, a, b):\n        # TODO A\n        # TODO B',
  'challenge': {
    'statement': 's',
    'motivation': 'm',
    'small': {'caption': 'c', 'input': 'i', 'output': 'o', 'note': null},
    'project': {'caption': 'c', 'input': 'i', 'output': 'o', 'note': 'n'},
  },
  'blocks': [
    for (final l in ['A', 'B'])
      {
        'id': 'e1-${l.toLowerCase()}',
        'label': l,
        'title': 'Ô $l',
        'prompt': 'p',
        'indent_level': 2,
        'accepted_answers': ['self.${l.toLowerCase()} = ${l.toLowerCase()}'],
        'expected_output': 'ok',
        'explanation': 'e',
        'hints': ['h1', 'h2', 'h3'],
        'vocab': ['self'],
      },
  ],
  'judge': {
    'solution':
        'class Box:\n    def fill(self, a, b):\n        self.a = a\n        self.b = b',
    'cases': [
      {
        'steps': ['x = Box()'],
        'call': 'x.fill(1, 2)',
        'expect': {'return': null},
      },
    ],
  },
};

Future<ProviderContainer> pumpEditor(
  WidgetTester tester, {
  void Function(Map<String, dynamic> ex)? tweak,
}) async {
  tester.view.physicalSize = const Size(412, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final content = sampleContent();
  content['exercises'] = <String, dynamic>{
    ...(content['exercises'] as Map<String, dynamic>),
    'e1': (fullExercise()..also(tweak)),
  };
  final client = MockClient(
    (r) async =>
        jsonResponse(jsonEncode({'version': 'v1', 'content': content}), 200),
  );
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const Scaffold()),
      GoRoute(
        path: '/admin/exercise/:id',
        builder: (_, s) =>
            ExerciseEditorScreen(exerciseId: s.pathParameters['id']!),
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(
        AdminRepository(client, baseUrl: Uri.parse('http://x')),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await container.read(adminProvider.notifier).load();
  router.push('/admin/exercise/e1');
  await tester.pumpAndSettle();
  return container;
}

Map<String, dynamic> e1(ProviderContainer c) =>
    c.read(adminProvider).exercises['e1'] as Map<String, dynamic>;

extension on Map<String, dynamic> {
  void also(void Function(Map<String, dynamic>)? f) => f?.call(this);
}

Finder _applyButton() => find.descendant(
  of: find.byKey(const Key('exercise-apply')),
  matching: find.byType(ElevatedButton),
);

void main() {
  testWidgets('sửa tiêu đề rồi Áp dụng ghi vào doc, cây dirty', (tester) async {
    final c = await pumpEditor(tester);
    expect(find.byKey(const Key('exercise-editor')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ex-title')), 'Mới');
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    expect(e1(c)['title'], 'Mới');
    expect(c.read(adminProvider).dirty, isTrue);
    // Field không sửa được giữ nguyên.
    expect((e1(c)['blocks'] as List).length, 2);
    expect(e1(c)['params'], ['a', 'b']);
    expect(find.byKey(const Key('exercise-editor')), findsNothing);
  });

  testWidgets('Huỷ không đổi gì', (tester) async {
    final c = await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('ex-title')), 'Mới');
    await tester.tap(find.byKey(const Key('exercise-cancel')));
    await tester.pumpAndSettle();
    expect(e1(c)['title'], 'One');
    expect(c.read(adminProvider).dirty, isFalse);
  });

  testWidgets('ghép thử: khớp; sửa đáp án → lệch, chỉ ra dòng', (tester) async {
    await pumpEditor(tester);
    expect(find.byKey(const Key('merge-ok')), findsOneWidget);
    expect(find.byKey(const Key('merge-mismatch')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('block-B-answer-0')),
      'self.b = 99',
    );
    await tester.pump();
    expect(find.byKey(const Key('merge-ok')), findsNothing);
    expect(find.byKey(const Key('merge-mismatch')), findsOneWidget);
    expect(find.textContaining('Lệch ở dòng 4'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('merge-mismatch')),
        matching: find.textContaining('self.b = 99'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cases JSON lỗi: hiện lỗi, vô hiệu Áp dụng', (tester) async {
    final c = await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('ex-cases')), '[ {');
    await tester.pump();
    expect(find.byKey(const Key('ex-cases-error')), findsOneWidget);
    final apply = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byKey(const Key('exercise-apply')),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(apply.onPressed, isNull);
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pump();
    expect(c.read(adminProvider).dirty, isFalse);

    await tester.enterText(find.byKey(const Key('ex-cases')), '[]');
    await tester.pump();
    expect(find.byKey(const Key('ex-cases-error')), findsNothing);
  });

  testWidgets('Thêm ô: nhãn kế tiếp + id <bài>-<nhãn>; Xoá ô', (tester) async {
    final c = await pumpEditor(tester);
    await tester.tap(find.byKey(const Key('block-add')));
    await tester.pump();
    expect(find.byKey(const Key('block-C-answer-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    var blocks = e1(c)['blocks'] as List;
    expect(blocks.length, 3);
    expect(blocks.last['label'], 'C');
    expect(blocks.last['id'], 'e1-c');
    expect((blocks.last['hints'] as List).length, 3);
  });

  testWidgets('Xoá ô gỡ khỏi blocks', (tester) async {
    final c = await pumpEditor(tester);
    await tester.tap(find.byKey(const Key('block-A-remove')));
    await tester.pump();
    expect(find.byKey(const Key('block-A-answer-0')), findsNothing);
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    final blocks = e1(c)['blocks'] as List;
    expect(blocks.map((b) => b['label']), ['B']);
  });

  testWidgets('class_name rỗng → null; params/vocab theo danh sách phẩy', (
    tester,
  ) async {
    final c = await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('ex-class')), '  ');
    await tester.enterText(find.byKey(const Key('ex-params')), 'x, y ,, z');
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    expect(e1(c)['class_name'], isNull);
    expect(e1(c)['params'], ['x', 'y', 'z']);
  });

  testWidgets('bài không tồn tại báo không tìm thấy', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient(
      (r) async => jsonResponse(
        jsonEncode({'version': 'v1', 'content': sampleContent()}),
        200,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(client, baseUrl: Uri.parse('http://x')),
          ),
        ],
        child: const MaterialApp(
          home: ExerciseEditorScreen(exerciseId: 'nope'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy bài tập.'), findsOneWidget);
  });

  testWidgets(
    'lời giải có \\n cuối → preview báo lệch (server so từng ký tự)',
    (tester) async {
      await pumpEditor(tester);
      expect(find.byKey(const Key('merge-ok')), findsOneWidget);
      final f = find.byKey(const Key('ex-solution'));
      final cur = tester.widget<TextField>(f).controller!.text;
      await tester.enterText(f, '$cur\n');
      await tester.pump();
      expect(find.byKey(const Key('merge-ok')), findsNothing);
      expect(find.byKey(const Key('merge-mismatch')), findsOneWidget);
    },
  );

  testWidgets('khoảng trắng cuối dòng → lệch và hiện dấu ·', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(
      find.byKey(const Key('ex-solution')),
      'class Box:\n    def fill(self, a, b):\n        self.a = a \n        self.b = b',
    );
    await tester.pump();
    expect(find.byKey(const Key('merge-mismatch')), findsOneWidget);
    expect(find.textContaining('Lệch ở dòng 3'), findsOneWidget);
    expect(find.textContaining('a·"'), findsOneWidget);
  });

  testWidgets('đổi nhãn A→C: id suy từ nhãn khi áp dụng', (tester) async {
    final c = await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('label-e1-a')), 'C');
    await tester.pump();
    expect(find.text('e1-c'), findsOneWidget);
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    final blocks = e1(c)['blocks'] as List;
    expect(blocks[0]['label'], 'C');
    expect(blocks[0]['id'], 'e1-c');
    expect(blocks[1]['id'], 'e1-b');
  });

  testWidgets('nhãn trùng hoặc trống: báo lỗi, vô hiệu Áp dụng', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('label-e1-b')), 'A');
    await tester.pump();
    expect(find.byKey(const Key('label-error-e1-a')), findsOneWidget);
    expect(find.byKey(const Key('label-error-e1-b')), findsOneWidget);
    expect(tester.widget<ElevatedButton>(_applyButton()).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('label-e1-b')), '');
    await tester.pump();
    expect(find.text('Nhãn không được để trống'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(_applyButton()).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('label-e1-b')), 'B');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(_applyButton()).onPressed, isNotNull);
  });

  testWidgets('Thêm ô bị vô hiệu khi đã đủ 3 ô', (tester) async {
    await pumpEditor(tester);
    OutlinedButton add() => tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const Key('block-add')),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(add().onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('block-add')));
    await tester.pump();
    expect(add().onPressed, isNull);
  });

  testWidgets('vocab/params có dấu phẩy: không sửa thì giữ nguyên danh sách', (
    tester,
  ) async {
    final c = await pumpEditor(
      tester,
      tweak: (ex) {
        ex['params'] = ['a=(1, 2)', 'b'];
        ((ex['blocks'] as List)[0] as Map)['vocab'] = ['range(1, 5)'];
      },
    );
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    expect(e1(c)['params'], ['a=(1, 2)', 'b']);
    expect(((e1(c)['blocks'] as List)[0] as Map)['vocab'], ['range(1, 5)']);
  });

  testWidgets('cảnh báo luật server nằm cạnh preview, không chặn Áp dụng', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(find.byKey(const Key('merge-warnings')), findsNothing);
    await tester.enterText(find.byKey(const Key('block-A-explanation')), '');
    await tester.enterText(
      find.byKey(const Key('block-A-answer-0')),
      'x = 1\ny = 2\nz = 3',
    );
    await tester.enterText(find.byKey(const Key('block-A-vocab')), '');
    await tester.pump();
    expect(find.byKey(const Key('merge-warnings')), findsOneWidget);
    expect(find.textContaining('giải thích đang trống'), findsOneWidget);
    expect(find.textContaining('tối đa 2 dòng'), findsOneWidget);
    expect(find.textContaining('vocab'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(_applyButton()).onPressed, isNotNull);
  });

  testWidgets('cảnh báo marker thụt sai so với indent_level', (tester) async {
    await pumpEditor(
      tester,
      tweak: (ex) => ((ex['blocks'] as List)[1] as Map)['indent_level'] = 1,
    );
    expect(
      find.textContaining('Ô B: marker thụt 8 space, indent 1'),
      findsOneWidget,
    );
  });

  testWidgets('field lạ ở root/challenge/judge/block còn nguyên sau Áp dụng', (
    tester,
  ) async {
    final c = await pumpEditor(
      tester,
      tweak: (ex) {
        ex['zz_root'] = {'k': 1};
        (ex['challenge'] as Map)['zz_ch'] = 'ch';
        (ex['judge'] as Map)['zz_judge'] = [1, 2];
        ((ex['blocks'] as List)[0] as Map)['zz_block'] = true;
      },
    );
    await tester.enterText(find.byKey(const Key('ex-title')), 'Mới');
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    final ex = e1(c);
    expect(ex['title'], 'Mới');
    expect(ex['zz_root'], {'k': 1});
    expect((ex['challenge'] as Map)['zz_ch'], 'ch');
    expect((ex['judge'] as Map)['zz_judge'], [1, 2]);
    expect(((ex['blocks'] as List)[0] as Map)['zz_block'], true);
  });
}
