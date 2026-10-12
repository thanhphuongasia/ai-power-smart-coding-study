# SEAM review — issue29-reskin (HEAD 5ef13f7, 7 task)

Bằng chứng chạy thật (không sửa file):
- `cd mobile && flutter analyze` → No issues found!
- `cd mobile && flutter test` → +563: All tests passed!
- Mô phỏng merge với PR #26 (`git merge-tree` HEAD + crew/2026-10-12-exercise-editor-redesign → tree 02e26be; chỉ conflict text ở `planning/crew/_index.md`; `git archive` cả tree ra scratchpad): `flutter analyze` sạch, `flutter test` → +588: All tests passed! (gồm admin_exercise_editor_test, code_cell_test, collapsible_section_test của PR #26).

INV-01: CÒN ĐÚNG — app_shell.dart:41 (`bottom-nav` <700), exercise_screen.dart:371 (`exercise-tabs`), code_tab.dart:555-603 (`cell-*`), code_input.dart (key `code-input-*`/`suggestion-*`); toàn bộ test cũ xanh ở 375/412/420/800 (563 pass)
INV-02: CÒN ĐÚNG — app_shell.dart:22 (≥700 top bar ☰, không NavigationBar; <700 `bottom-nav`, không ☰), widgets.dart:208-211 (ScreenHeader ☰ khi ≥nav và `!InAppShell.of`), exercise_screen.dart:333 (☰ màn luyện ≥nav, ScreenHeader không dùng ở đây nên không kép)
INV-03: CÒN ĐÚNG — theme.dart:84-86 là nơi duy nhất; mọi so sánh: app_shell.dart:22, widgets.dart:210, exercise_screen.dart:295+333, home_screen.dart:386-388; grep không còn số 700/900/720 cứng trong lib/ (ngoài font weight)
INV-04: CÒN ĐÚNG — code_input.dart:135-144 (`_ghost` chỉ đọc), :200-204 (`onChanged` chỉ khi `v.text` đổi), :725-746 (ghost chỉ nối vào TextSpan hiển thị), :147-157 (`_acceptGhost` mới ghi text); `_isDone` code_tab.dart:77 chỉ đọc `_cells`
INV-05: CÒN ĐÚNG — widgets.dart:310 (`ElevatedButton.icon(onPressed: onPressed)`), :351 (`OutlinedButton(onPressed: onPressed)`); đã chạy admin_exercise_editor_test của PR #26 trên tree merge giả lập: pass
INV-06: CÒN ĐÚNG — code_tab.dart:77 `_isDone`, :156 `_onCellChanged`, :659-669 inline và :113-130 route đều truyền cùng `_cells`/`_onCellChanged`/`_isDone`/`_nextAfter` vào CellEditorBody/CellEditorPage; `_run` code_tab.dart:197 duy nhất; draft chỉ lưu ở :160
INV-07: CÒN ĐÚNG — theme_mode.dart:9 (`ThemeMode.light`); main.dart:34, content_gate.dart:154, auth_gate.dart:94 cùng `ref.watch(themeModeProvider)` + cùng cặp `theme: light / darkTheme: buildAppTheme()`; banner content_gate.dart:94 cùng provider; palette dark/light đủ 17 trường, copyWith+lerp đủ (theme.dart:100-232)
INV-08: VỠ — run_result_view.dart:197 (khối "Code đã ghép" nền `alphaBlend(p.ink 6%, p.surfaceRaised)` theo theme, chữ `AppText.code` mặc định) trong khi code_tab.dart:820/885, solution_tab.dart:232, code_input.dart:325 dùng `codeSurface/codeInk` luôn tối
INV-09: CÒN ĐÚNG — "ô đang làm" chỉ có một nguồn trong CodeTab: `_open` (code_tab.dart:66); dải bước suy ra từ `_open/_isDone/_unlocked` (code_tab.dart:436-445) và không có state thứ hai ở exercise_screen.dart; drawer/Home "bài đang học" là khái niệm KHÁC cấp bài, cùng MỘT provider `inProgressExerciseProvider` (session_providers.dart:30; dùng ở app_drawer.dart:101 và home_screen.dart:27) → không có hai nguồn cho cùng một khái niệm
INV-10: CÒN ĐÚNG — (tự thêm: ☰ ở xem trước admin) ghi nhận rủi ro nhỏ, không vỡ: exercise_screen.dart:58 `ExercisePreview` bọc ProviderScope lồng, nhưng `showAppDrawer` mở trên root navigator (app_drawer.dart:25-27) nên drawer ở màn xem trước đọc tiến độ/nội dung THẬT, và chạm một mục điều hướng sẽ rời màn xem trước; không làm hỏng dữ liệu (preview cô lập progress)

## Giải thích ngắn

INV-08 (VỠ, mức Minor về hiển thị, không mất dữ liệu / không làm test đỏ): ở theme sáng, khối "Code đã ghép" (Out sau khi Run) nền xám nhạt, còn khối code ô/lời giải nền xanh đen. Chữ vẫn đọc được (nền sáng + chữ ink) nên không phải lỗi tương phản, nhưng đúng là hai khối code lệch màu như sổ mô tả. Sửa: nền `p.codeSurface`, chữ `p.codeInk` (+ ô nhãn `merged-origin-*`, alpha 0.6 như `_CodePreview`) ở run_result_view.dart:194-250; test: pump theme sáng, tìm `merged-code` container có màu == `AppPalette.light.codeSurface`. File này nằm ngoài owned của mọi task trong run (không task nào phụ trách) — đó là lý do nó lọt: orchestrator quyết định sửa hay hoãn.

Điểm có thể xung đột với PR #26 (crew/2026-10-12-exercise-editor-redesign):
- Test: không vỡ. Đã chạy trên tree merge giả lập, 588 test pass (xem trên). `PrimaryButton/GhostButton` vẫn là ElevatedButton/OutlinedButton nên `find.descendant(...ElevatedButton)` dưới `exercise-apply` / `block-add` còn khớp.
- Text conflict duy nhất: `planning/crew/_index.md` (giữ cả hai dòng).
- Không vỡ nhưng lệch giao diện: admin `code_cell.dart` (PR #26, :379 `p.surfaceRaised`, :407 `p.ink`) là khối code dùng màu theo theme, không dùng `codeSurface/codeInk` → khối code admin ≠ khối code học viên ở INV-08 (admin nằm ngoài phạm vi INV-08 nhưng nên quyết định có đồng bộ không).
- `exercise_editor.dart` (PR #26) dùng `ScreenHeader` (:795) → ở ≥700px tự có thêm ☰ (từ nhánh này); test PR #26 không đếm icon nên không vỡ.

Quan sát phụ (không phải bất biến vỡ):
- change_password_screen.dart:91 dùng `AppBar` riêng: ≥700px không có ☰ (không bottom nav, có nút back) — chấp nhận được, ngoài danh sách màn của INV-02.
- Đổi cửa sổ qua ngưỡng 900 giữa chừng: `LayoutBuilder` + `DefaultTabController(length 2/3)` (exercise_screen.dart:292-298) dựng lại CodeTab → mất kết quả Run đang hiện (`_result`), draft vẫn còn vì đã saveDraft. Chỉ gặp khi resize cửa sổ.

## Không xác minh được
- Giao diện thật (chưa chạy `flutter build web`/chụp màn hình): màu, bóng nút, ghost text trong `buildTextSpan` (TextSpan hiển thị dài hơn `text` — caret/IME trên thiết bị thật chưa kiểm; chỉ có widget test).
- Rò rỉ giữa các hồ sơ/phiên cũ, backend: ngoài phạm vi sổ.
- Tên các test phủ từng INV: không đối chiếu (suite xanh, không soi từng test có thực sự vỡ khi cố ý làm sai).

Kết luận: CẦN SỬA nhẹ — chỉ INV-08 (run_result_view.dart:197) vỡ, mức Minor/hiển thị; verdict VỠ chặn commit theo luật của sổ, orchestrator quyết định sửa nhanh (1 file, ~4 dòng) hay ghi DEVIATIONS và hoãn.
