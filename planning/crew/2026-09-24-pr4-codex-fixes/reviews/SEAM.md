# Review mối nối — run 2026-09-24-pr4-codex-fixes

Phạm vi: 4 task (T-01..T-04) trên branch `crew/2026-09-24-flutter-demo-core`, 4 commit mới
nhất trên worktree. Không nhận danh sách file — tự tìm bằng grep. Read-only, không sửa code.

## Bằng chứng chạy thật

```
$ cd mobile && flutter analyze
No issues found! (ran in 1.3s)

$ flutter test
...
00:03 +184: All tests passed!
```

184/184 test xanh, analyze sạch. `git status --short -- mobile/` rỗng — không có artifact thử
tạm bị bỏ sót.

## Từng bất biến

INV-01: CÒN ĐÚNG — Run/hint/"Gợi ý rõ hơn"/gõ đều gọi activity(); reset qua session_controller.activity(), không pop nào ngoài phase timedOut — mobile/lib/features/exercise/cell_screen.dart:54, mobile/lib/features/exercise/cell_screen.dart:72
INV-02: CÒN ĐÚNG — Home/Block-list/Cell subtitle đều dùng completed+1, thử markBlockPassed qua app_flow_test 184/184 xanh — mobile/lib/features/browse/home_screen.dart:73, mobile/lib/features/exercise/block_list_screen.dart:161
INV-03: CÒN ĐÚNG — SurfaceCard Material+InkWell+Semantics(button: onTap!=null), card khoá onTap null không bấm được, Key cũ giữ nguyên — mobile/lib/shared/widgets.dart:18, mobile/lib/features/exercise/block_list_screen.dart:252
INV-04: CÒN ĐÚNG — placeholder chỉ là IgnorePointer overlay đọc controller.text, không ghi ngược; test khoá "never reaches controller text or onChanged" xanh — mobile/lib/features/exercise/code_input.dart:198, mobile/test/code_input_test.dart:180
INV-05: CÒN ĐÚNG — nhánh bàn phím mở giữ nguyên (Expanded flex 1/3, không đổi so với T-06b); cell_layout_test 6 case (3 size × 2 inset) đều xanh — mobile/lib/features/exercise/cell_screen.dart:299, mobile/test/cell_layout_test.dart:63

## Chi tiết & bằng chứng bổ sung

### INV-01 — idle reset
- `_runCode` gọi `sessionNotifier.activity()` trước khi `run()` — cell_screen.dart:51-57.
- `_showHintSheet` gọi `activity()` ngay khi mở sheet (cell_screen.dart:72) VÀ lại gọi lần nữa
  khi bấm "Gợi ý rõ hơn" (cell_screen.dart:134-136) — đúng yêu cầu "mở hint" và "gợi ý rõ hơn"
  đều reset, không chỉ một trong hai.
- Gõ/chạm chip/phím ký hiệu: mọi thay đổi giá trị controller (typing, `_insertSymbol`,
  `_applySuggestion`) đi qua `_onControllerChanged` → `widget.onActivity?.call()` —
  code_input.dart:81-91, wiring ở cell_screen.dart:266-267.
- Duy nhất một chỗ `context.pop()` không do người dùng chủ động: `ref.listen` chỉ pop khi
  `next.phase == SessionPhase.timedOut && previous?.phase != timedOut` — cell_screen.dart:217-224.
  Không có đường pop nào khác ngoài Back (chủ động) và nút "Nghỉ" trong idle dialog (chủ động).
- Test thật: `cell_idle_test.dart` — Run lúc 100s / mở hint lúc 100s → 170s vẫn active (không
  idle dialog); không chạm gì 121s → dialog hiện. Cả 3 case pump 184/184 xanh (ghi nhận ở log
  test ở trên, dòng `cell_idle_test.dart`).

### INV-02 — nhãn số block nhất quán
- Home `_ContinueCard`: `'Tiếp tục Block ${completed + 1}/$total'` — home_screen.dart:73.
- Block-list banner: `blockIndex: completed` (block_list_screen.dart:33 `hasDraftInProgress`,
  truyền vào `_ContinueBanner`), hiển thị `'Bạn đang làm dở Block ${blockIndex + 1}'` —
  block_list_screen.dart:161, và nút "Tiếp tục" mở đúng `/block/$blockIndex` (= completed,
  0-based) — cùng block Cell sẽ mở.
- Cell subtitle: `'Block ${widget.blockIndex + 1}/$total'` — cell_screen.dart:278,284. Cell mở
  ở `blockIndex = completed` (route từ banner/continue-card), nên subtitle hiện đúng
  `completed+1/total` — khớp cả 3 nơi.
- `block_list_screen.dart` KHÔNG nằm trong owned files của 4 task (T-01..T-04 chỉ chạm
  widgets.dart, cell_screen.dart, code_input.dart, home_screen.dart) — không có diff ở file
  này trong run này; nhãn của nó vẫn đúng công thức từ trước, không bị lệch bởi các sửa lần này.
  `app_flow_test.dart` (không thuộc owned của task nào, nhưng chạy qua cả 3 màn) xanh: tap
  continue-card → block-list-continue-button → Cell B3 → Run → B4 mở khoá, xác nhận số khớp
  xuyên 3 màn bằng hành vi thật, không chỉ đọc code.

### INV-03 — widget chạm không đổi Key/chữ/khả năng tap
- `SurfaceCard`: `Semantics(button: onTap != null)` bọc `Material(elevation:0)` +
  `InkWell(onTap: onTap)` — widgets.dart:18-38. Card khoá (`BlockStatus.locked`) nhận
  `onTap: null` — block_list_screen.dart:252 (`tappable ? ... : null`) — không bấm được, đúng
  spec "card bị khoá... onTap null".
- `ScreenHeader` back: `IconButton(icon: arrow_back, tooltip: 'Quay lại')` — widgets.dart:211-216.
  `_CompactHeader` (T-02, dùng khi bàn phím mở) cũng `IconButton` cùng tooltip —
  cell_screen.dart:432-436. Cả hai đường (bàn phím đóng/mở) đều accessible như nhau.
- Key cũ giữ nguyên qua toàn bộ diff: `run-button`, `hint-reveal-more`, `code-input-field`,
  `code-input-border`, `continue-card`, `block-list-continue-button`, `block-card-$index` — tất
  cả xuất hiện đúng vị trí cũ trong code hiện tại (grep xác nhận, không đổi tên).
- `app_flow_test.dart:128` vẫn `tester.tap(find.byIcon(Icons.arrow_back).first)` — test cũ
  (viết trước run này) chạy xanh sau khi đổi `GestureDetector` → `IconButton`, xác nhận đường
  tap cũ không gãy dù đổi widget chạm.
- `theme_test.dart:454-490` (T-01, tự phá 2 chiều theo báo cáo T-01 vòng 2): Semantics
  button:true khi có onTap, button:false khi onTap null — đúng đối xứng INV-03.

### INV-04 — placeholder chỉ là lớp hiển thị
- `showPlaceholder = _controller.text.isEmpty` (đọc, không ghi) — code_input.dart:198.
- Placeholder bọc `IgnorePointer` — không nhận gesture, không thể vô tình gõ vào placeholder
  rồi lẫn vào controller — code_input.dart:202-216.
- `onChanged`/`saveDraft` chỉ được gọi từ `_onControllerChanged` khi `textChanged` (so với
  `_last.text`, tức nội dung controller thật) — code_input.dart:84-89, wiring
  cell_screen.dart:263-265 (`onChanged: (code) => ... saveDraft(...)`).
- Test khoá trực tiếp: "placeholder ... never reaches the controller text or onChanged" —
  code_input_test.dart:180, xanh.

### INV-05 — layout bàn phím mở giữ nguyên
- Nhánh `keyboardOpen == true`: `Expanded(flex:1, child: promptScroll)` +
  `Expanded(flex:3, child: codeInput)` — cell_screen.dart:299-304 — không đổi cấu trúc so với
  T-06b (comment tại chỗ xác nhận: "không đổi hành vi ở nhánh bàn phím mở").
- Chỉ nhánh `else` (bàn phím đóng) bị viết lại — từ `SizedBox(height:200)` cố định sang
  `LayoutBuilder` + `ConstrainedBox` co dãn (cell_screen.dart:320-340) — đúng phạm vi T-02.
- `cell_layout_test.dart` chạy cả 3 size × 2 trạng thái bàn phím (6 case) — case bàn phím MỞ
  (`inset=300`) không assert thêm gì về chiều cao (giữ nguyên đo cũ T-06b: chỉ check field/
  run/chip không bị che, không overflow) — xanh cho cả 3 size.
- Viền focus 2px của T-03 (code_input.dart:227-239, `Container` với `border width: focused?2:1`)
  không đổi kích thước tổng — comment tại chỗ: "Container tự bù padding bằng đúng độ dày viền
  nên kích thước tổng thể không đổi khi focus/blur". `maxLines` header của T-01 chỉ áp cho
  `ScreenHeader` (widgets.dart:225,233 — dùng ở nhánh bàn phím ĐÓNG), `_CompactHeader` (nhánh
  bàn phím MỞ) dùng `maxLines: 1` riêng (cell_screen.dart:441) — không đụng nhánh bàn phím mở.
  Không có case nào trong 6 case layout test overflow hay che Run.

## Không xác minh được
- Cảm quan hình ảnh thật (screenshot `flutter build web` ở Home/Cell 600px theo bước E2E #4
  của PLAN.md) — không tự chạy build+chụp ảnh trong phạm vi review mối nối này, chỉ xác nhận
  bằng test số đo (`getRect`) và đọc code. Đây là việc của orchestrator ở bước E2E, không phải
  của reviewer mối nối.
- Hành vi bàn phím ảo thật / IME tiếng Việt thật trên thiết bị — cùng giới hạn đã ghi trong
  T-03.md, không có gì mới phát sinh ở lớp mối nối.
- `_showIdleDialog`/dialog "Nghỉ" dẫn tới `context.pop()` chủ động — không phải nhánh idle timeout,
  không thuộc phạm vi "đường thoát do idle", chỉ note để không nhầm là một lỗi INV-01.

## Checklist NFR — baseline

SEC-01: N/A — thay đổi chỉ ở UI Flutter cục bộ, không có dữ liệu truyền qua mạng.
SEC-02: N/A — không chạm lưu trữ/persistence (draft đã lưu qua provider có sẵn, không đổi cơ chế).
SEC-03: PASS — grep diff không thấy secret/token/key, chỉ Flutter `Key(...)` widget key.
SEC-04: N/A — input là code người học gõ cục bộ, không băng qua trust boundary server nào trong 4 diff.
SEC-05: N/A — không có authZ/permission trong scope Flutter demo app này.
PERF-01: N/A — không có query DB/network trong 4 diff.
PERF-02: PASS — LayoutBuilder/build đồng bộ nhẹ, không I/O chặn main thread — mobile/lib/features/exercise/cell_screen.dart:320-340.
PERF-03: N/A — không có network call, pagination, hay retry trong 4 diff.
MNT-01: PASS — không phát hiện logic lặp mới xuyên 4 task (mỗi task sửa đúng 1 vùng, không copy code giữa file).
MNT-02: N/A — không có ranh giới module mới; SurfaceCard/CodeInput giữ nguyên chữ ký public.
MNT-03: PASS — thêm nhánh bàn phím đóng không sửa `if/else` nhánh mở đã ổn định (xem INV-05); thêm biến thể focus/placeholder bằng ternary đơn giản, không cần OCP ở quy mô này.

## Verdict: PASS
