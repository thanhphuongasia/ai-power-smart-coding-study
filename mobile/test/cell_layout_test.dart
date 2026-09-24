/// T-06b: khi bàn phím ảo mở trên máy nhỏ (360x640), màn Cell từng bị
/// RenderFlex overflow và nút Run/chip gợi ý bị bàn phím che (CodeInput nằm
/// trong SizedBox(200) cố định + hàng nút Run ngoài vùng cuộn — header +
/// progress + 200 + hàng nút cộng lại vượt quá chiều cao còn lại sau khi
/// bàn phím chiếm chỗ).
///
/// Test này khoá bất biến: ở mọi kích thước máy trong danh sách, bàn phím
/// đóng hay mở, không có overflow exception, và ba thứ quan trọng nhất khi
/// đang gõ code — dòng code, chip gợi ý, nút Run — đều nằm hoàn toàn trong
/// vùng nhìn thấy (không bị bàn phím che, không tràn ra ngoài màn hình).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/exercise/cell_screen.dart';

const _sizes = [
  Size(360, 640),
  Size(390, 844),
  Size(412, 915),
];

const _keyboardInsets = [0.0, 300.0];

/// Dùng block-index 2 của 'split-chunks' — có 2 done-block preview phía
/// trên + prompt, đúng nội dung đã dùng để tái hiện lỗi gốc.
Future<void> _pumpCell(
  WidgetTester tester, {
  required Size size,
  required double keyboardInset,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: buildAppTheme(),
      home: const CellScreen(exerciseId: 'split-chunks', blockIndex: 2),
    ),
  ));
  await tester.pump();
}

/// flutter_code_editor có Timer debounce 5s (phân tích/tìm kiếm định danh)
/// vẫn chạy sau khi widget đã unmount trong test — phải xả hết trước khi
/// testWidgets kết thúc, nếu không "A Timer is still pending" làm test đỏ.
Future<void> _drainEditorTimer(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  for (final size in _sizes) {
    for (final inset in _keyboardInsets) {
      final label =
          '${size.width.toInt()}x${size.height.toInt()}, bàn phím '
          '${inset == 0 ? 'đóng' : 'mở (${inset.toInt()}dp)'}';

      testWidgets(
        'Cell không overflow, Run/chip/editor luôn thấy được — $label',
        (tester) async {
          await _pumpCell(tester, size: size, keyboardInset: inset);

          // Không có RenderFlex overflow (hay bất kỳ exception nào khác)
          // phát sinh trong lúc build/layout.
          expect(tester.takeException(), isNull);

          final visibleBottom = size.height - inset;

          final field = find.byKey(const Key('code-input-field'));
          expect(field, findsOneWidget, reason: 'thiếu ô nhập code');
          expect(tester.getRect(field).bottom, lessThanOrEqualTo(visibleBottom),
              reason: 'ô nhập code bị bàn phím che');

          final run = find.byKey(const Key('run-button'));
          expect(run, findsOneWidget, reason: 'thiếu nút Run');
          expect(tester.getRect(run).bottom, lessThanOrEqualTo(visibleBottom),
              reason: 'nút Run bị bàn phím che');

          // Chip gợi ý đầu tiên — 'suggestion-text' xuất hiện đúng ngữ cảnh
          // block 'split-chunks' index 2 (gợi ý biến `text` có sẵn trong
          // known identifiers của bài, xem app_flow_test.dart).
          final chip = find.byKey(const Key('suggestion-text'));
          expect(chip, findsOneWidget, reason: 'thiếu chip gợi ý');
          expect(tester.getRect(chip).bottom, lessThanOrEqualTo(visibleBottom),
              reason: 'chip gợi ý bị bàn phím che');

          // T-02: bàn phím đóng — editor không còn bị ép cao đúng 200dp cố
          // định (từng quá thấp trên máy nhỏ). AC (orchestrator, sau khi
          // phát hiện 45% màn hình không khả thi ở 360x640 — ScreenHeader
          // wrap title dài ăn hết dư địa, xem cell_screen.dart): khung viền
          // editor ('code-input-border', T-03) phải (a) cao ≥ 200dp — mức
          // sàn cũ (SizedBox(200)); (b) cao HƠN vùng đề bài
          // ('cell-prompt-scroll'); (c) không overflow, Run/chip vẫn thấy
          // được (đã kiểm ở trên).
          if (inset == 0) {
            final border = find.byKey(const Key('code-input-border'));
            expect(border, findsOneWidget, reason: 'thiếu khung viền editor');
            final borderHeight = tester.getRect(border).height;

            final prompt = find.byKey(const Key('cell-prompt-scroll'));
            expect(prompt, findsOneWidget, reason: 'thiếu vùng đề bài');
            final promptHeight = tester.getRect(prompt).height;

            // Số đo cho báo cáo T-02, không phải log sản phẩm.
            // ignore: avoid_print
            print(
              'T-02 layout $label: editor=$borderHeight '
              'prompt=$promptHeight (màn hình=${size.height})',
            );

            expect(
              borderHeight,
              greaterThanOrEqualTo(200.0),
              reason: 'editor bàn phím đóng phải cao ≥ 200dp (mức sàn cũ) — '
                  'label=$label',
            );
            expect(
              borderHeight,
              greaterThan(promptHeight),
              reason: 'editor phải cao hơn vùng đề bài — label=$label',
            );
          }

          await _drainEditorTimer(tester);
        },
      );
    }
  }
}
