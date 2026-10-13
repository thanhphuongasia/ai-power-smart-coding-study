import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/admin/code_cell.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

List<String> _texts(String src, CodeLanguage l, CodeSpanKind k) => [
      for (final s in tokenize(src, l))
        if (s.kind == k) src.substring(s.start, s.end),
    ];

void main() {
  group('tokenize python', () {
    const src = 'class A:\n'
        '    def f(self):  # ghi chu\n'
        '        # TODO B\n'
        '        return "x#y" + \'z\'\n'
        '    classy = 1';

    test('keyword chỉ khớp nguyên từ', () {
      expect(_texts(src, CodeLanguage.python, CodeSpanKind.keyword),
          ['class', 'def', 'self', 'return']);
    });

    test('comment, TODO, chuỗi (# trong chuỗi không phải comment)', () {
      expect(_texts(src, CodeLanguage.python, CodeSpanKind.comment),
          ['# ghi chu']);
      expect(_texts(src, CodeLanguage.python, CodeSpanKind.todo),
          ['# TODO B']);
      expect(_texts(src, CodeLanguage.python, CodeSpanKind.string),
          ['"x#y"', "'z'"]);
    });

    test('chuỗi thiếu dấu đóng dừng ở cuối dòng', () {
      expect(_texts('a = "abc\nb = 1', CodeLanguage.python, CodeSpanKind.string),
          ['"abc']);
    });
  });

  group('tokenize json', () {
    const src = '[{"a": 1, "b": -2.5e3, "c": "v", "d": true}]';

    test('key vs chuỗi giá trị', () {
      expect(_texts(src, CodeLanguage.json, CodeSpanKind.key),
          ['"a"', '"b"', '"c"', '"d"']);
      expect(_texts(src, CodeLanguage.json, CodeSpanKind.string), ['"v"']);
    });

    test('số và true/false/null', () {
      expect(_texts(src, CodeLanguage.json, CodeSpanKind.number),
          ['1', '-2.5e3']);
      expect(_texts(src, CodeLanguage.json, CodeSpanKind.keyword), ['true']);
    });

    test('JSON không có comment kiểu #', () {
      expect(_texts('# x', CodeLanguage.json, CodeSpanKind.comment), isEmpty);
    });
  });

  testWidgets('HighlightingController: toPlainText == text, có màu',
      (tester) async {
    const src = 'def f():\n    return "a"  # TODO A\n\n';
    final c = HighlightingController(text: src, language: CodeLanguage.python);
    late TextSpan span;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Builder(builder: (context) {
        span = c.buildTextSpan(
            context: context, style: AppText.code, withComposing: false);
        return const SizedBox();
      }),
    ));
    expect(span.toPlainText(), src);
    expect(span.children!.length, greaterThan(1));
    final c2 = HighlightingController(language: CodeLanguage.json);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Builder(builder: (context) {
        span = c2.buildTextSpan(
            context: context, style: AppText.code, withComposing: false);
        return const SizedBox();
      }),
    ));
    expect(span.toPlainText(), '');
  });

  testWidgets('gõ vào TextField đổi controller.text và gọi onChanged',
      (tester) async {
    final c = HighlightingController(text: 'x', language: CodeLanguage.python);
    String? changed;
    await tester.pumpWidget(_host(CodeCell(
      key: const Key('cell-a'),
      controller: c,
      language: CodeLanguage.python,
      onChanged: (v) => changed = v,
    )));
    expect(find.byKey(const Key('cell-a')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('cell-a'))).controller,
        same(c));
    await tester.enterText(find.byKey(const Key('cell-a')), 'a\nb\nc\nd');
    await tester.pump();
    expect(c.text, 'a\nb\nc\nd');
    expect(changed, 'a\nb\nc\nd');
    expect(find.text('4 dòng'), findsOneWidget);
    expect(find.text('1\n2\n3\n4'), findsOneWidget);
  });

  testWidgets('Thu gọn ẩn TextField nhưng giữ controller; Mở rộng hiện lại',
      (tester) async {
    final c = TextEditingController(text: 'giữ nguyên');
    await tester.pumpWidget(_host(CodeCell(
      key: const Key('cell-a'),
      controller: c,
      language: CodeLanguage.json,
    )));
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byKey(const Key('code-cell-fold')));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Mở rộng'), findsOneWidget);
    expect(c.text, 'giữ nguyên');
    await tester.tap(find.byKey(const Key('code-cell-fold')));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('errorText và label hiện; không có thì không hiện',
      (tester) async {
    final c = TextEditingController(text: '{');
    await tester.pumpWidget(_host(CodeCell(
      controller: c,
      language: CodeLanguage.json,
      label: 'Cases',
      errorText: 'JSON lỗi',
    )));
    expect(find.text('JSON lỗi'), findsOneWidget);
    expect(find.text('Cases'), findsOneWidget);
    await tester.pumpWidget(_host(CodeCell(
      controller: c,
      language: CodeLanguage.json,
    )));
    expect(find.text('JSON lỗi'), findsNothing);
  });

  testWidgets('nút Chép đưa text vào clipboard', (tester) async {
    String? clip;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clip = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final c = TextEditingController(text: 'abc');
    await tester.pumpWidget(_host(CodeCell(
      controller: c,
      language: CodeLanguage.python,
    )));
    await tester.tap(find.byKey(const Key('code-cell-copy')));
    await tester.pump();
    expect(clip, 'abc');
    expect(find.text('Đã chép'), findsOneWidget);
  });

  testWidgets('readOnly không cho gõ', (tester) async {
    final c = TextEditingController(text: 'abc');
    await tester.pumpWidget(_host(CodeCell(
      key: const Key('cell-a'),
      controller: c,
      language: CodeLanguage.python,
      readOnly: true,
    )));
    expect(
        tester.widget<TextField>(find.byKey(const Key('cell-a'))).readOnly, isTrue);
  });
}
