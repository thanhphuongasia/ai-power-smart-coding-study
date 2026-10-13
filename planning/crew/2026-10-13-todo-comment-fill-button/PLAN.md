# PLAN — Ô TODO trống hiện `# TODO <nhãn> — <tiêu đề>` + nút "Điền code" rõ ràng

## Context

Issue #38 (quản lý nội dung admin) kéo theo yêu cầu mới: màn soạn bài admin cần "Xem trước"
đúng như học viên thấy. Khi dựng mockup Xem trước, user muốn ô TODO rỗng hiện `# TODO <nhãn>`
như một dòng comment thật trong code, kèm nút "Điền code" rõ ràng — bấm vào mới mở chỗ nhập,
nhập xong code chèn đúng vào vị trí đó. User sau đó xác nhận: style này áp dụng cho **cả màn
làm bài thật của học viên** (`CodeTab`), không chỉ riêng preview admin — vì preview admin tái
dùng đúng widget `CodeTab` (qua `ExerciseScreen(preview: true)`), nên sửa một chỗ là đủ cho cả
hai nơi.

Đã khảo sát kỹ trước khi lên plan (đọc `code_tab.dart`, `cell_editor_page.dart`, `merge.dart`,
`domain/models.dart`, `code_tab_test.dart`) và phát hiện phạm vi **nhỏ hơn nhiều** so với ước
lượng ban đầu khi mới dispatch `/crew`:

- `Block` đã có sẵn field `title` ngắn (vd "Chuyến bay đã đầy chưa") — **không cần thêm field
  schema mới** cho dòng comment, dùng thẳng `block.title`.
- `CellEditorPage` (màn soạn code toàn màn hình, có `CodeInput`/`CodeToolbar` — số dòng, gợi ý
  vocab, autocomplete) đã là đúng "chỗ nhập code" — **không thay bằng box nhập inline**, giữ
  nguyên kiến trúc hiện có, chỉ đổi cách MỞ nó rõ ràng hơn.
- Luồng khoá ô, accordion (`_unlocked`/`_frontier`/`_advanceFrom`), `markPassed`, lưu draft —
  **không đổi gì**, chỉ đổi phần hiển thị NỘI DUNG ô khi còn trống.

→ Đây là 1 thay đổi hiển thị cục bộ trong `_CodePreview` (code_tab.dart), không phải việc tách
nhiều task song song. Chạy qua `/crew` vẫn đúng theo yêu cầu của user (worktree riêng, PR thay
vì commit tay), nhưng chỉ cần **một task** — không có mối nối giữa nhiều agent để lo.

## Thay đổi cụ thể

File: `mobile/lib/features/exercise/code_tab.dart`

- `_CodePreview` hiện nhận `code` + `onTap`; đổi để nhận thêm `label` và `title` (hoặc cả
  `Block b`) để biết chữ hiển thị khi rỗng.
- Khi `code` rỗng (trường hợp hiện render placeholder `'# chạm để viết code'` ở dòng ~773–779):
  - Dòng đầu: `# TODO $label — $title`, style giống comment Python thật (tái dùng tông màu
    comment đã có ở `_codeStyles` / cách `_LockedCell` tô màu, `p.outline`, in nghiêng) — không
    phải chữ `inkMuted` generic như hiện tại.
  - Thêm một nút rõ ràng "✏️ Điền code" (style theo `p.primary`, cùng tinh thần `PrimaryButton`
    trong `shared/widgets.dart`) bên dưới dòng comment, `onPressed` gọi đúng `onTap` đang có
    (mở `CellEditorPage`) — **không đổi đích đến**, chỉ thêm lối vào rõ ràng hơn ngoài việc
    chạm cả vùng box như hiện tại (giữ nguyên `InkWell` bọc ngoài để không phá hành vi tap cũ).
  - `Key('cell-$label-field')` **giữ nguyên trên đúng widget hiện có** — test cũ
    (`_openEditor` helper trong `code_tab_test.dart` tap đúng key này) không được đổi ý nghĩa.
- Khi `code` không rỗng: **không đổi gì** — vẫn syntax-highlight + icon mở rộng như hiện tại.
- `_todoCell` (nơi gọi `_CodePreview`): truyền thêm `b.label`/`b.title` vào constructor mới.
- Không chạm `_CollapsedCell` (dòng rút gọn khi ô đã thu lại) — nằm ngoài phạm vi user yêu cầu,
  giữ "Chạm để mở"/"✓ ..." như cũ.

File: `mobile/test/code_tab_test.dart`

- Soát qua các test hiện có dùng `cell-$label-field` / `cell-$label-frame` / `_openEditor` —
  xác nhận còn pass (key không đổi ý nghĩa nên về lý thuyết không vỡ gì, nhưng phải chạy thật
  để xác nhận).
- Thêm 1–2 test mới: ô rỗng hiện đúng `# TODO <nhãn> — <tiêu đề>` (dùng tiêu đề thật của block
  trong fixture `test/support/content_fixture.dart`), và bấm nút "Điền code" mở đúng
  `CellEditorPage` (verify qua cùng cách `_openEditor` hiện kiểm, vd tìm `Key('editor-title')`
  sau khi bấm).

## Bất biến (seam-invariants)

Bất biến: KHÔNG CÓ — chỉ một task, một agent, không chia ownership giữa nhiều worker nên không
phát sinh mối nối. Hành vi khoá ô/accordion/`markPassed`/lưu draft không bị chạm (chỉ sửa nhánh
hiển thị khi `code` rỗng trong `_CodePreview`) — xác nhận lại bằng cách chạy nguyên bộ
`code_tab_test.dart` (bao gồm các test khoá ô, lỗi, hint, đã có từ trước) sau khi sửa, không chỉ
test mới thêm.

## Task contract — T-01

| Mục | Nội dung |
|---|---|
| ID · tier · model | T-01 · T2 · `crew-impl-standard` (balanced = sonnet, không override) |
| Objective | Ô TODO rỗng hiện `# TODO <nhãn> — <tiêu đề>` dạng comment + nút "Điền code" rõ ràng, thay cho placeholder mờ hiện tại; không đổi logic khoá/accordion/lưu draft |
| Owned files | `mobile/lib/features/exercise/code_tab.dart`, `mobile/test/code_tab_test.dart` |
| Forbidden files | mọi file khác — đặc biệt `cell_editor_page.dart`, `merge.dart`, `domain/models.dart` |
| Acceptance criteria | (1) Ô rỗng hiện đúng text `# TODO <nhãn> — <tiêu đề block>` kiểu comment + nút "Điền code"; (2) bấm nút mở đúng `CellEditorPage` hiện có; (3) ô đã có code không đổi hiển thị; (4) toàn bộ test cũ trong `code_tab_test.dart` vẫn pass; (5) có thêm ≥1 test mới cho hành vi mới |
| Validation command | `cd mobile && flutter test test/code_tab_test.dart` |
| Evidence command | `git diff --stat -- mobile/lib/features/exercise/code_tab.dart mobile/test/code_tab_test.dart` |
| Thứ tự thực hiện | Sửa `_CodePreview` trước, chạy test cũ để xác nhận không vỡ gì, rồi mới thêm test mới |

## Verification (orchestrator tự chạy ở P3)

1. `cd mobile && flutter test test/code_tab_test.dart` — toàn bộ pass, dán output thật.
2. `cd mobile && flutter analyze lib/features/exercise/code_tab.dart` — không lỗi mới.
3. Đọc diff bằng mắt: xác nhận `_CollapsedCell`, logic khoá/`_unlocked`/`_frontier`,
   `markPassed`, lưu draft không bị động tới.
4. Xác nhận admin "Xem trước" (`review_detail_screen.dart` → `ExerciseScreen(preview: true)`)
   tự nhận thay đổi vì dùng chung `CodeTab`, không cần sửa thêm.

## E2E (orchestrator tự chạy, không uỷ quyền)

Vì chỉ 1 task, không có mối nối giữa nhiều agent — bước 4 ở Verification đóng vai trò e2e:
xác nhận tính năng hiện đúng ở CẢ hai nơi dùng chung component (học viên thật + admin preview).
