import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight/languages/python.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/domain/answer_checker.dart';
import 'package:smart_coding_study/features/exercise/code_input.dart';

const _field = Key('code-input-field');

/// Popup gợi ý overlay của flutter_code_editor (class `Popup` nằm ở src/wip,
/// không export) → dò theo tên kiểu.
Finder _popup() =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Popup');

TextEditingController _ctrl(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller;

/// Gõ như IME thật: gửi value = cũ + 1 ký tự tại con trỏ.
Future<void> _type(WidgetTester tester, String chars) async {
  for (final ch in chars.split('')) {
    final v = _ctrl(tester).value;
    final s = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: v.text.replaceRange(s.start, s.end, ch),
      selection: TextSelection.collapsed(offset: s.start + ch.length),
    ));
    await tester.pump();
  }
}

/// Bàn phím điện thoại commit NHIỀU ký tự một lần (autocorrect, gợi ý từ,
/// composing): value = cũ + [chunk] tại con trỏ, trong một update duy nhất.
Future<void> _commit(WidgetTester tester, String chunk,
    {TextRange composing = TextRange.empty}) async {
  final v = _ctrl(tester).value;
  final p = v.selection.start;
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: v.text.replaceRange(p, p, chunk),
    selection: TextSelection.collapsed(offset: p + chunk.length),
    composing: composing,
  ));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

/// Python block `split-chunks` [i] trong seed.
final _splitChunks = exerciseById('split-chunks').blocks;

/// Backspace như IME: xoá 1 ký tự trước con trỏ.
Future<void> _backspace(WidgetTester tester) async {
  final v = _ctrl(tester).value;
  final p = v.selection.start;
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: v.text.replaceRange(p - 1, p, ''),
    selection: TextSelection.collapsed(offset: p - 1),
  ));
  await tester.pump();
}

class _Harness {
  final changes = <String>[];
  int activity = 0;
  final focus = FocusNode();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  String initialCode = '',
  List<String> known = const ['text', 'size', 'chunks'],
  List<String> vocab = const ['range', 'len', 'append'],
}) async {
  final h = _Harness();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: CodeInput(
        initialCode: initialCode,
        knownIdentifiers: known,
        vocab: vocab,
        onChanged: h.changes.add,
        onActivity: () => h.activity++,
        focusNode: h.focus,
      ),
    ),
  ));
  await tester.showKeyboard(find.byKey(_field));
  await tester.pump();
  return h;
}

/// Tháo cây widget + chờ timer debounce của controller (history 5s, analysis
/// 500ms) để test không kết thúc với timer treo.
Future<void> _teardown(WidgetTester tester, [_Harness? h]) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
  h?.focus.dispose();
}

void main() {
  testWidgets('baseline: stock CodeController DOES show overlay popup',
      (tester) async {
    // Chứng minh cách dò `_popup()` bắt được popup thật → test "không popup"
    // bên dưới không xanh oan.
    final c = CodeController(text: 'chunks = 1\n', language: python);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CodeTheme(
          data: CodeThemeData(styles: const {}),
          child: CodeField(key: _field, controller: c),
        ),
      ),
    ));
    await tester.showKeyboard(find.byKey(_field));
    await tester.pump();
    await _type(tester, 'chu');
    expect(c.popupController.shouldShow, isTrue);
    expect(_popup(), findsOneWidget);
    await _teardown(tester);
    c.dispose();
  });

  testWidgets('CodeInput shows no overlay popup', (tester) async {
    final h = await _pump(tester, initialCode: 'chunks = []\n');
    await _type(tester, 'chu');
    expect(_popup(), findsNothing);
    expect(find.byKey(const Key('suggestion-chunks')), findsOneWidget);
    await _teardown(tester, h);
  });

  testWidgets('tap suggestion replaces typed word, caret at end',
      (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'chu');
    await tester.tap(find.byKey(const Key('suggestion-chunks')));
    await tester.pump();
    expect(_ctrl(tester).text, 'chunks');
    expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 6));
    expect(h.changes.last, 'chunks');
    expect(h.focus.hasFocus, isTrue);
    await _teardown(tester, h);
  });

  testWidgets('callable suggestion inserts range() with caret inside',
      (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'for i in ');
    await tester.tap(find.byKey(const Key('suggestion-range')));
    await tester.pump();
    expect(_ctrl(tester).text, 'for i in range()');
    expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 15));

    // Gõ tiếp bằng tay trong ngoặc, rồi `)` phải overtype chứ không nhân đôi.
    await _type(tester, '0, len(');
    await tester.tap(find.byKey(const Key('suggestion-text')));
    await tester.pump();
    await _type(tester, '), size):');
    expect(_ctrl(tester).text, 'for i in range(0, len(text), size):');
    expect(runBlock(_ctrl(tester).text, _splitChunks[2]).passed, isTrue);
    await _teardown(tester, h);
  });

  testWidgets('prefix-typed callable: "ran" → range() caret between',
      (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'ran');
    await tester.tap(find.byKey(const Key('suggestion-range')));
    await tester.pump();
    expect(_ctrl(tester).text, 'range()');
    expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 6));
    await _teardown(tester, h);
  });

  testWidgets('typing full line by hand with auto-close yields single pairs',
      (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'range(0, len(text), size)');
    expect(_ctrl(tester).text, 'range(0, len(text), size)');
    expect(_ctrl(tester).selection.baseOffset, 25);

    await _type(tester, '\nchunks.append(text[i:i + size])');
    expect(_ctrl(tester).text,
        'range(0, len(text), size)\nchunks.append(text[i:i + size])');
    await _teardown(tester, h);
  });

  testWidgets('quote auto-pairs and overtypes', (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'print("hi")');
    expect(_ctrl(tester).text, 'print("hi")');
    await _teardown(tester, h);
  });

  testWidgets('backspace inside empty pair deletes both', (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'len(');
    expect(_ctrl(tester).text, 'len()');
    await _backspace(tester);
    expect(_ctrl(tester).text, 'len');
    await _teardown(tester, h);
  });

  testWidgets('Enter after ":" indents 4; plain Enter keeps indent',
      (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'for i in x:\n');
    expect(_ctrl(tester).text, 'for i in x:\n    ');
    await _type(tester, 'y = 1\n');
    expect(_ctrl(tester).text, 'for i in x:\n    y = 1\n    ');
    await _teardown(tester, h);
  });

  testWidgets('symbol keys insert at caret, keep focus, run auto-close',
      (tester) async {
    final h = await _pump(tester);
    await _type(tester, 'len');
    await tester.tap(find.byKey(const Key('symbol-(')));
    await tester.pump();
    expect(_ctrl(tester).text, 'len()');
    expect(_ctrl(tester).selection.baseOffset, 4);
    await tester.tap(find.byKey(const Key('symbol-)')));
    await tester.pump();
    expect(_ctrl(tester).text, 'len()');
    expect(_ctrl(tester).selection.baseOffset, 5);
    await tester.tap(find.byKey(const Key('symbol-:')));
    await tester.pump();
    expect(_ctrl(tester).text, 'len():');
    expect(h.focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await _teardown(tester, h);
  });

  testWidgets('Tab key inserts 4 spaces', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(const Key('symbol-tab')));
    await tester.pump();
    expect(_ctrl(tester).text, '    ');
    expect(_ctrl(tester).selection.baseOffset, 4);
    await _teardown(tester, h);
  });

  testWidgets('all symbol keys exist and are at least 40 tall',
      (tester) async {
    final h = await _pump(tester);
    for (final c in ['(', ')', '[', ']', ':', '=', '.', ',', '"', 'tab']) {
      final f = find.byKey(Key('symbol-$c'));
      expect(f, findsOneWidget, reason: c);
      expect(tester.getSize(f).height, greaterThanOrEqualTo(40), reason: c);
    }
    await _teardown(tester, h);
  });

  testWidgets('bars sit below the editor', (tester) async {
    final h = await _pump(tester);
    final editorBottom = tester.getBottomLeft(find.byKey(_field)).dy;
    final symbolTop = tester.getTopLeft(find.byKey(const Key('symbol-('))).dy;
    expect(symbolTop, greaterThanOrEqualTo(editorBottom));
    await _teardown(tester, h);
  });

  testWidgets('onChanged per text change, onActivity per interaction',
      (tester) async {
    final h = await _pump(tester);
    final before = h.activity;
    await _type(tester, 'ab');
    expect(h.changes, ['a', 'ab']);
    expect(h.activity, greaterThanOrEqualTo(before + 2));
    await _teardown(tester, h);
  });

  testWidgets('initialCode change on same widget reloads editor text',
      (tester) async {
    final h = _Harness();
    Widget build(String code) => MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: CodeInput(
              initialCode: code,
              knownIdentifiers: const [],
              vocab: const [],
              onChanged: h.changes.add,
            ),
          ),
        );
    await tester.pumpWidget(build('a = 1'));
    await tester.pumpWidget(build('b = 2'));
    expect(_ctrl(tester).text, 'b = 2');
    expect(h.changes, isEmpty);
    await _teardown(tester, h);
  });

  group('IME commits several chars at once', () {
    testWidgets('len( + "0)" → len(0), caret at end', (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'len(');
      await _commit(tester, '0)');
      expect(_ctrl(tester).text, 'len(0)');
      expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 6));
      expect(h.changes.last, 'len(0)');
      await _teardown(tester, h);
    });

    testWidgets('range( + "0, len(text), size)" → one outer pair',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'for i in range(');
      expect(_ctrl(tester).text, 'for i in range()');
      await _commit(tester, '0, len(text), size)');
      expect(_ctrl(tester).text, 'for i in range(0, len(text), size)');
      expect(_ctrl(tester).selection.baseOffset, 34);
      await _type(tester, ':');
      expect(runBlock(_ctrl(tester).text, _splitChunks[2]).passed, isTrue);
      await _teardown(tester, h);
    });

    testWidgets('"x)" kept when char after caret is not ")"', (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'text[');
      expect(_ctrl(tester).text, 'text[]');
      await _commit(tester, 'x)');
      expect(_ctrl(tester).text, 'text[x)]');
      expect(_ctrl(tester).selection.baseOffset, 7);
      await _teardown(tester, h);
    });

    testWidgets('"x)" kept at end of text (nothing to overtype)',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'a');
      await _commit(tester, 'x)');
      expect(_ctrl(tester).text, 'ax)');
      await _teardown(tester, h);
    });

    testWidgets('balanced "(a)" before ")" is kept whole', (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'len(');
      await _commit(tester, '(a)');
      expect(_ctrl(tester).text, 'len((a))');
      expect(_ctrl(tester).selection.baseOffset, 7);
      await _teardown(tester, h);
    });

    testWidgets('quote: odd count closes existing string, even is kept',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'print("');
      expect(_ctrl(tester).text, 'print("")');
      await _commit(tester, 'hi"');
      expect(_ctrl(tester).text, 'print("hi")');
      expect(_ctrl(tester).selection.baseOffset, 10);
      await _teardown(tester, h);

      final h2 = await _pump(tester);
      await _type(tester, 'f(');
      await _commit(tester, '"a")');
      expect(_ctrl(tester).text, 'f("a")');
      await _teardown(tester, h2);
    });

    testWidgets('composing region shrinks with the dropped closer',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'len(');
      await _commit(tester, '0)', composing: const TextRange(start: 4, end: 6));
      expect(_ctrl(tester).text, 'len(0)');
      expect(_ctrl(tester).value.composing,
          const TextRange(start: 4, end: 5));
      expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 6));
      await _teardown(tester, h);
    });

    testWidgets('f(x[ + "0])" closes both nested auto-closed pairs',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'f(x[');
      expect(_ctrl(tester).text, 'f(x[])');
      await _commit(tester, '0])');
      expect(_ctrl(tester).text, 'f(x[0])');
      expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 7));
      await _teardown(tester, h);
    });

    testWidgets('chunks.append(text[ + "i:i + size])" passes runBlock',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'chunks.append(text[');
      expect(_ctrl(tester).text, 'chunks.append(text[])');
      await _commit(tester, 'i:i + size])');
      final code = _ctrl(tester).text;
      expect(code, 'chunks.append(text[i:i + size])');
      expect(_ctrl(tester).selection.baseOffset, code.length);
      expect(runBlock(code, _splitChunks[3]).passed, isTrue);
      await _teardown(tester, h);
    });

    testWidgets('f(x[ + "0]" closes only one level, caret before ")"',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'f(x[');
      await _commit(tester, '0]');
      expect(_ctrl(tester).text, 'f(x[0])');
      expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 6));
      await _teardown(tester, h);
    });

    testWidgets('f(x[ + "(a)])" keeps self-balanced "(a)"', (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'f(x[');
      await _commit(tester, '(a)])');
      expect(_ctrl(tester).text, 'f(x[(a)])');
      expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 9));
      await _teardown(tester, h);
    });

    testWidgets('f([ + "0)" wrong order → no overtype', (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'f([');
      expect(_ctrl(tester).text, 'f([])');
      await _commit(tester, '0)');
      expect(_ctrl(tester).text, 'f([0)])');
      expect(_ctrl(tester).selection, const TextSelection.collapsed(offset: 5));
      await _teardown(tester, h);
    });

    testWidgets('composing shrinks by k and stays within text',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'f(x[');
      await _commit(tester, '0])', composing: const TextRange(start: 4, end: 7));
      expect(_ctrl(tester).text, 'f(x[0])');
      expect(_ctrl(tester).value.composing,
          const TextRange(start: 4, end: 5));
      await _teardown(tester, h);
    });
  });

  testWidgets(
      'end-to-end line 2: chunks.append(text[i:i + size]) via '
      'suggestions + symbol keys + typing passes runBlock', (tester) async {
    final block = _splitChunks[3];
    final h = await _pump(tester,
        known: const ['text', 'size', 'chunks', 'i'], vocab: block.vocab);
    await _type(tester, 'chu');
    await _tap(tester, 'suggestion-chunks');
    await _type(tester, '.');
    await _tap(tester, 'suggestion-append');
    expect(_ctrl(tester).text, 'chunks.append()');
    await _type(tester, 'tex');
    await _tap(tester, 'suggestion-text');
    await _tap(tester, 'symbol-[');
    expect(_ctrl(tester).text, 'chunks.append(text[])');
    await _type(tester, 'i');
    await _tap(tester, 'symbol-:');
    await _type(tester, 'i + si');
    await _tap(tester, 'suggestion-size');
    await _tap(tester, 'symbol-]');
    await _tap(tester, 'symbol-)');
    final code = _ctrl(tester).text;
    expect(code, 'chunks.append(text[i:i + size])');
    expect(_ctrl(tester).selection.baseOffset, code.length);
    expect(runBlock(code, block).passed, isTrue);
    await _teardown(tester, h);
  });

  group('placeholder "Nhập code"', () {
    testWidgets('shows on empty, hides once a char is typed', (tester) async {
      final h = await _pump(tester);
      expect(find.text('Nhập code'), findsOneWidget);
      await _type(tester, 'a');
      expect(find.text('Nhập code'), findsNothing);
      await _teardown(tester, h);
    });

    testWidgets('reappears after deleting all text', (tester) async {
      final h = await _pump(tester, initialCode: 'x');
      expect(find.text('Nhập code'), findsNothing);
      await _backspace(tester);
      expect(_ctrl(tester).text, isEmpty);
      expect(find.text('Nhập code'), findsOneWidget);
      await _teardown(tester, h);
    });

    testWidgets('never reaches the controller text or onChanged',
        (tester) async {
      final h = await _pump(tester);
      await _type(tester, 'ab');
      await _backspace(tester);
      await _backspace(tester);
      expect(find.text('Nhập code'), findsOneWidget);
      expect(_ctrl(tester).text, isNot(contains('Nhập code')));
      expect(h.changes.any((c) => c.contains('Nhập code')), isFalse);
      await _teardown(tester, h);
    });

    testWidgets('tapping the placeholder area still focuses the editor',
        (tester) async {
      final h = await _pump(tester);
      h.focus.unfocus();
      await tester.pump();
      expect(h.focus.hasFocus, isFalse);
      // IgnorePointer chủ ý làm placeholder "trong suốt" với hit-test — tap
      // rơi xuyên qua, chạm đúng editor bên dưới thay vì chính chữ này.
      await tester.tap(find.text('Nhập code'), warnIfMissed: false);
      await tester.pump();
      expect(h.focus.hasFocus, isTrue);
      await _teardown(tester, h);
    });
  });

  group('editor border reacts to focus', () {
    BoxDecoration border(WidgetTester tester) => tester
        .widget<Container>(find.byKey(const Key('code-input-border')))
        .decoration as BoxDecoration;

    testWidgets('2px primary when focused, 1px outline when blurred',
        (tester) async {
      final h = await _pump(tester);
      final scheme =
          Theme.of(tester.element(find.byKey(_field))).colorScheme;

      // _pump() gọi showKeyboard() → editor đã focus sẵn.
      expect(h.focus.hasFocus, isTrue);
      var deco = border(tester);
      expect(deco.border!.top.width, 2);
      expect(deco.border!.top.color, scheme.primary);

      h.focus.unfocus();
      await tester.pump();
      deco = border(tester);
      expect(deco.border!.top.width, 1);
      expect(deco.border!.top.color, scheme.outline);
      await _teardown(tester, h);
    });
  });

  testWidgets('works inside unbounded-height parent', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: ListView(children: [
          CodeInput(
            initialCode: 'x',
            knownIdentifiers: const [],
            vocab: const [],
            onChanged: (_) {},
          ),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byKey(_field), findsOneWidget);
    await _teardown(tester);
  });
}
