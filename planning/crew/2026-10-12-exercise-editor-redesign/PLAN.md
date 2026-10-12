# Plan: thiết kế lại màn Soạn bài tập (modular, responsive, code cell kiểu Jupyter)

## Context
Mockup đã duyệt: https://claude.ai/artifact/UnNYrxVEMcWYNaMRjPFcQ6. Màn hiện tại (`mobile/lib/features/admin/exercise_editor.dart`, 806 dòng) là một cột dài, code nằm trong TextField thường, chỉ hợp điện thoại.
P0: `mobile/ios/Runner.xcodeproj/project.pbxproj` đang sửa dở, không liên quan run này; worktree mới base từ HEAD nên không mang theo. Dùng worktree (git-workflow.md); không làm thẳng trên main.

## Quyết định thiết kế
1. **Code cell = một `TextField` giữ nguyên Key**, controller là `HighlightingController extends TextEditingController` override `buildTextSpan` để tô màu. Không overlay, không thêm package. `controller.text` vẫn là nguồn sự thật nên `_Form.toJson`/`_previewMerge` không đổi.
2. Tô màu: tokenizer nhỏ (Python: comment, chuỗi, keyword, `# TODO X` nổi bật; JSON: key, chuỗi, số). Màu lấy từ `context.palette` (không hardcode theo theme).
3. Layout theo `LayoutBuilder`: ≥1100 = mục lục | form | panel ghép thử; 700–1100 = form | panel; <700 = một cột + thanh Huỷ/Áp dụng dưới. Panel ghép thử **chỉ dựng ở một chỗ tại một thời điểm** (tránh trùng Key `merge-preview`).
4. **Mọi mục và mọi ô mở mặc định** (khác mockup, nơi vài mục đóng): test cũ tìm Key trong Judge/Challenge/ô B, mục đóng thì widget không có trong cây. Có nút "Thu gọn tất cả".
5. Không đổi `AdminController`, hành vi Áp dụng/Huỷ, `_Form`/`_BlockForm`/`toJson`/`_previewMerge`.

## Tasks (tất cả trong `$WT/mobile`)
| ID | Role · tier · model | Mục tiêu | Owned files |
|---|---|---|---|
| T-01 | crew-impl-standard · T2 · sonnet | `CodeCell` + `HighlightingController` + tokenizer Python/JSON, số dòng, nút Chép/Thu gọn, hiện lỗi dưới cell | `lib/features/admin/code_cell.dart`, `test/code_cell_test.dart` |
| T-02 | crew-impl-light · T1 · haiku | `CollapsibleSection` (tiêu đề + tóm tắt một dòng khi đóng + chấm trạng thái) và `CollapsibleCard` cho ô A/B/C | `lib/features/admin/collapsible_section.dart`, `test/collapsible_section_test.dart` |
| T-03 | crew-impl-standard · T2 · sonnet | Nối vào `exercise_editor.dart`: layout 3 breakpoint, mục lục neo, panel ghép thử, thanh dưới, dùng T-01/T-02; thêm test breakpoint | `lib/features/admin/exercise_editor.dart`, `test/admin_exercise_editor_test.dart` |

Wave 1: T-01 ∥ T-02 (ownership rời). Wave 2: T-03 (cần API của hai task trên). Checkpoint sau T-03: full `flutter test`.
Forbidden cho cả run: `lib/features/admin/admin_controller.dart`, `lib/domain/**`, `lib/app/theme.dart`, `pubspec.*`, `ios/**`.
Validation (một lệnh/task): `cd $WT/mobile && flutter test <file test của task>`; T-03 thêm `flutter analyze`. Cần `flutter pub get` trong worktree trước (`.dart_tool` bị gitignore).
Evidence: `git diff --stat -- <owned files>`.

## Sổ bất biến
- INV-01 · Mọi Key hiện có (`ex-*`, `block-<L>-*`, `label-*`, `exercise-apply/cancel`, `merge-*`, `block-add`) vẫn tồn tại ở layout mặc định
  phải khớp: `exercise_editor.dart` · `test/admin_exercise_editor_test.dart`
  vỡ thì thấy gì: 20+ test cũ đỏ vì `find.byKey` rỗng.
- INV-02 · Text trong TextField của CodeCell == text controller của `_Form` (highlight chỉ đổi style, không đổi chuỗi)
  phải khớp: `code_cell.dart` · `exercise_editor.dart` (`toJson`, `_previewMerge`)
  vỡ thì thấy gì: "Khớp lời giải" sai, ghép thử lệch so với lời giải dù nhìn giống nhau.
- INV-03 · Tại mọi bề rộng, đúng một `Key('merge-preview')` trong cây
  phải khớp: `exercise_editor.dart` (hàm chọn layout)
  vỡ thì thấy gì: test `findsOneWidget` trên `merge-ok`/"Lệch ở dòng" đỏ, hoặc preview hiện hai lần.
- INV-04 · Nút Áp dụng/Huỷ có ở mọi layout, cùng điều kiện vô hiệu (`casesError`/`hasLabelError`)
  phải khớp: `exercise_editor.dart`
  vỡ thì thấy gì: ở <700px hoặc ≥700px không bấm được Áp dụng khi cases JSON lỗi vẫn áp dụng được.

## E2E (orchestrator tự chạy trước commit)
1. `flutter test` toàn bộ trong `$WT/mobile` xanh.
2. Test mới đặt `tester.view.physicalSize` ở 400, 800, 1280 px: ở mỗi cỡ, sửa đáp án ô B → thấy `merge-mismatch` đúng một lần → bấm Áp dụng khi cases lỗi không ghi (đi qua mối nối form ↔ preview ↔ nút).
3. Chạy web build/preview một lần ở 3 bề rộng, chụp màn (nếu Chrome tab visible).

## Review
`crew-review` từng task (T2); sau cùng một reviewer mối nối nhận contract + sổ INV, không nhận danh sách file, ghi `reviews/SEAM.md`. Chạy `verify-seam.sh`. Không dùng external review (không phải L4).
Kết thúc: commit trong worktree, push, mở PR (kèm `Closes #n` nếu có issue cha), không tự merge.
