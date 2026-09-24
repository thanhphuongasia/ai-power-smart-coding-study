/// T-02: bấm Run hoặc mở gợi ý phải tính là hoạt động — reset mốc idle,
/// giống việc gõ code (INV-01). Trước bản sửa này, `_runCode` và
/// `_showHintSheet`/"Gợi ý rõ hơn" không gọi `activity()`, nên người học
/// bấm Run liên tục trong lúc suy nghĩ vẫn bị hệ thống coi là ngồi im và
/// hiện dialog "Vẫn đang làm chứ?" sau đúng 2 phút kể từ lúc mở màn.
///
/// clockProvider bị override bằng đồng hồ giả điều khiển tay — cùng kỹ
/// thuật với test/app_flow_test.dart: FakeAsync nội bộ của testWidgets đẩy
/// Timer.periodic theo `tester.pump(duration)`, nhưng `DateTime.now()` thật
/// không tự chạy theo, nên phải tự khớp đồng hồ giả với từng lần pump.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/features/exercise/cell_screen.dart';
import 'package:smart_coding_study/features/exercise/session_controller.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/shared/widgets.dart';

class _FakeClock {
  DateTime now = DateTime(2024, 1, 1, 9);
}

/// Dựng CellScreen ở block 'split-chunks' index 2 (đúng bối cảnh đã dùng ở
/// cell_layout_test.dart/app_flow_test.dart), trả về [ProviderContainer]
/// thật để đọc trực tiếp `sessionProvider` mà không phụ thuộc UI phụ (label
/// TimerPill, ...).
Future<ProviderContainer> _pumpCell(
  WidgetTester tester,
  _FakeClock fakeClock,
) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [clockProvider.overrideWithValue(() => fakeClock.now)],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return const MaterialApp(
            home: CellScreen(exerciseId: 'split-chunks', blockIndex: 2),
          );
        },
      ),
    ),
  );
  // Frame đầu: initState -> postFrameCallback -> session.start().
  await tester.pump();
  return container;
}

/// Tiến đồng hồ giả VÀ đồng hồ ảo của tester cùng lúc — Timer.periodic(1s)
/// của SessionController ăn theo thời gian tester.pump đẩy, còn các phép
/// tính elapsed/idle bên trong đọc `clockProvider` (đồng hồ giả).
Future<void> _advance(
  WidgetTester tester,
  _FakeClock fakeClock,
  Duration d,
) async {
  fakeClock.now = fakeClock.now.add(d);
  await tester.pump(d);
}

/// flutter_code_editor có Timer debounce 5s vẫn chạy sau khi widget đã
/// unmount trong test — phải xả hết trước khi testWidgets kết thúc.
Future<void> _drainEditorTimer(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 6));
}

const _idleDialogTitle = 'Vẫn đang làm chứ?';

void main() {
  testWidgets(
    'Bấm Run lúc 100s → tới 170s phase vẫn active, không hiện idle dialog',
    (tester) async {
      final fakeClock = _FakeClock();
      final container = await _pumpCell(tester, fakeClock);

      await _advance(tester, fakeClock, const Duration(seconds: 100));

      await tester.tap(find.byKey(const Key('run-button')));
      await tester.pump();

      await _advance(tester, fakeClock, const Duration(seconds: 70));

      expect(
        container.read(sessionProvider('split-chunks')).phase,
        SessionPhase.active,
        reason: 'bấm Run lúc 100s phải reset mốc idle (INV-01)',
      );
      expect(find.text(_idleDialogTitle), findsNothing);

      await _drainEditorTimer(tester);
    },
  );

  testWidgets(
    'Mở gợi ý lúc 100s → tới 170s phase vẫn active, không hiện idle dialog',
    (tester) async {
      final fakeClock = _FakeClock();
      final container = await _pumpCell(tester, fakeClock);

      await _advance(tester, fakeClock, const Duration(seconds: 100));

      await tester.tap(find.byType(HintButton));
      await tester.pumpAndSettle();

      // Đóng bottom sheet: chạm ra ngoài vùng sheet (barrier mặc định
      // barrierDismissible=true của showModalBottomSheet).
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      await _advance(tester, fakeClock, const Duration(seconds: 70));

      expect(
        container.read(sessionProvider('split-chunks')).phase,
        SessionPhase.active,
        reason: 'mở gợi ý lúc 100s phải reset mốc idle (INV-01)',
      );
      expect(find.text(_idleDialogTitle), findsNothing);

      await _drainEditorTimer(tester);
    },
  );

  testWidgets(
    'Không chạm gì 121s → idle dialog hiện (giữ hành vi cũ)',
    (tester) async {
      final fakeClock = _FakeClock();
      await _pumpCell(tester, fakeClock);

      await _advance(tester, fakeClock, const Duration(seconds: 121));
      await tester.pump();

      expect(find.text(_idleDialogTitle), findsOneWidget);

      await _drainEditorTimer(tester);
    },
  );
}
