/// Test luồng end-to-end: Home → Block list → Cell, gõ bằng gợi ý +
/// phím ký hiệu để Run đúng, rồi xác nhận block kế tiếp mở khoá.
///
/// clockProvider bị override bằng một đồng hồ giả điều khiển tay — Flutter
/// test chạy trong FakeAsync riêng của nó (Timer.periodic ăn theo thời gian
/// `tester.pump` đẩy), nhưng `DateTime.now()` thật KHÔNG bị ảnh hưởng bởi
/// FakeAsync đó, nên phải tự khớp đồng hồ giả với từng lần pump.
library;

// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/features/exercise/cell_screen.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/main.dart';

class _FakeClock {
  DateTime now = DateTime(2024, 1, 1, 9);
}

TextEditingController _ctrl(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).controller;

/// Gõ như IME thật: gửi value = cũ + 1 ký tự tại con trỏ (xem
/// test/code_input_test.dart cho giải thích đầy đủ).
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

Future<void> _backspace(WidgetTester tester) async {
  final v = _ctrl(tester).value;
  final p = v.selection.start;
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: v.text.replaceRange(p - 1, p, ''),
    selection: TextSelection.collapsed(offset: p - 1),
  ));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

void main() {
  testWidgets(
    'Home → continue-card → Block list → Tiếp tục → Cell B3, '
    'gõ bằng gợi ý ra đáp án đúng → Run "Đúng" → B4 mở khoá',
    (tester) async {
      final fakeClock = _FakeClock();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [clockProvider.overrideWithValue(() => fakeClock.now)],
          child: const SmartCodingStudyApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Bắt đầu ở Home.
      expect(find.byKey(const Key('continue-card')), findsOneWidget);

      // Chạm 1: continue-card → Block list.
      await tester.tap(find.byKey(const Key('continue-card')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block-list-continue-button')),
          findsOneWidget);

      // Chạm 2: "Tiếp tục" → Cell (block active = index 2, hiển thị "Block
      // 3/5" — split-chunks đã xong 2 block trong seed).
      await tester.tap(find.byKey(const Key('block-list-continue-button')));
      await tester.pumpAndSettle();
      expect(find.byType(CellScreen), findsOneWidget);
      expect(find.text('Block 3/5'), findsOneWidget);

      final cellFinder = find.byType(CellScreen);
      Finder inCell(Finder f) =>
          find.descendant(of: cellFinder, matching: f);

      await tester.showKeyboard(find.byKey(const Key('code-input-field')));
      await tester.pump();

      // TimerPill phải tăng sau khi màn Cell mở được 2 giây (BẮT BUỘC:
      // session start() phải chạy thật, không bị autoDispose huỷ sớm).
      fakeClock.now = fakeClock.now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(inCell(find.text('00:02')), findsOneWidget);

      // Test thêm: gõ "chu" thấy gợi ý suggestion-chunks (INV-02).
      await _type(tester, 'chu');
      expect(inCell(find.byKey(const Key('suggestion-chunks'))),
          findsOneWidget);
      await _backspace(tester);
      await _backspace(tester);
      await _backspace(tester);
      expect(_ctrl(tester).text, isEmpty);

      // Gõ đáp án đúng của block 3 bằng gợi ý + phím ký hiệu:
      // "for i in range(0, len(text), size):"
      await _type(tester, 'for i in ');
      await _tap(tester, 'suggestion-range');
      expect(_ctrl(tester).text, 'for i in range()');
      await _type(tester, '0, len(');
      await _tap(tester, 'suggestion-text');
      await _type(tester, '), size):');
      final code = _ctrl(tester).text;
      expect(code, 'for i in range(0, len(text), size):');

      // Run.
      await _tap(tester, 'run-button');
      expect(inCell(find.text('Đúng')), findsOneWidget);

      // Quay lại Block list bằng nút back trên header (ScreenHeader không
      // export key riêng cho icon back — dò theo Icons.arrow_back).
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();

      expect(find.byType(CellScreen), findsNothing);
      // Block 4 (index 3) không còn khoá: không còn nằm trong Opacity mờ
      // của _BlockCard locked, và không còn hiện "Mở khoá sau Block 3".
      final block4Card = find.byKey(const Key('block-card-3'));
      expect(block4Card, findsOneWidget);
      expect(
        find.ancestor(of: block4Card, matching: find.byType(Opacity)),
        findsNothing,
        reason: 'block-card-3 (Block 4) phải hết khoá sau khi Run B3 đúng',
      );
      expect(find.text('Mở khoá sau Block 3'), findsNothing);

      // Dọn timer debounce 5s của flutter_code_editor (đã unmount cùng
      // CellScreen, nhưng vẫn còn ở block trước đó trong lịch sử pump).
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    },
  );
}
