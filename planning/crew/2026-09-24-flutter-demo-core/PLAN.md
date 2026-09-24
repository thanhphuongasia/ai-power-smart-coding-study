# Plan v2 — Flutter demo app (issue #3), ưu tiên màn làm bài

## Context
Issue #3 (https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/3): build Flutter app demo trước,
trong folder riêng `mobile/`. Nguồn: mockup CodeSprint + design system "Smart Coding Study".
**User chốt ưu tiên**: màn làm bài (Block list + Cell/Exercise) với **autocomplete UX cao để khỏi nản** làm trước;
đi tới đó qua Home → Theme → Topic. Tiến độ / Review / Stats / SM-2 / cross-cut → **phase sau** (issue riêng).
Hiện trạng: thư mục local trống, chưa `git init`; remote repo rỗng.

## Phạm vi phase 1
Màn: Home (danh sách theme) · A Theme detail (topics) · B Topic detail (file → exercise) · 2 Block list (stepper,
khoá/mở dần) · 3 Cell (prompt + editor + Run + output) · 4 Hint sheet (3 mức mờ→rõ) · 5 Idle popup.
Ngoài phạm vi: 6 Review, 7 Stats, C File cross-cut, 8 Admin, SM-2, lưu tiến độ qua restart (Hive).
Bottom nav chỉ còn khi có ≥2 tab thật → phase 1 không có bottom nav.

## Quyết định (duyệt plan = duyệt các điểm này)
1. **Bootstrap git (ngoại lệ "không push thẳng main")**: remote rỗng nên PR không có base → 1 commit chỉ gồm
   `README.md` + `.gitignore` lên `main`. Code app đi qua branch `crew/...` + PR.
2. **Bỏ ở phase 1**: Dio/Retrofit, get_it/injectable (chưa có backend; Riverpod đã làm DI), Hive (tiến độ để phase sau —
   trạng thái giữ in-memory trong Riverpod). Giữ: Riverpod 3, go_router, `flutter_code_editor`, `google_fonts`, Material 3 dark.
3. **Run = so khớp đáp án, không chạy Python thật**: chuẩn hoá khoảng trắng rồi so với danh sách đáp án chấp nhận
   của block; đúng → output mẫu (màu `primary` + chữ "Đúng"); sai → `danger` + chữ "Chưa đúng". Giới hạn: viết khác cách bị chấm sai.
4. **Màu/type theo design system**, không theo mockup (teal `primary`, amber `accent` chỉ cho hint, IBM Plex Sans +
   JetBrains Mono, không shadow, không emoji). Chữ UI tiếng Việt, sentence case.

## Autocomplete — thiết kế (phần rủi ro nhất, làm sớm)
Popup autocomplete kiểu desktop khó dùng trên điện thoại. Thay bằng **thanh gợi ý nằm ngay trên bàn phím**:
- **Hàng 1 — gợi ý từ**: lọc theo tiền tố của từ đang gõ, xếp hạng: (a) biến/tham số đã có ở block trước
  (`text`, `size`, `chunks`) → (b) từ vựng của exercise trong seed (`range`, `len`, `append`) → (c) keyword/builtin Python.
  Chạm = thay từ đang gõ. Chưa gõ gì → hiện gợi ý theo ngữ cảnh (sau `for ` → biến lặp `i`; sau `in ` → `range(`).
- **Hàng 2 — phím ký hiệu** mà bàn phím điện thoại giấu sâu: `(` `)` `[` `]` `:` `=` `.` `,` `"` và Tab (4 space).
- **Hành vi editor**: tự đóng ngoặc/nháy, xuống dòng sau `:` tự thụt 4 space, Enter giữ thụt dòng trước.
- Engine là **hàm thuần** `suggest(prefixText, vocab) → List<Suggestion>`, test không cần UI.
- Chữ ký API `flutter_code_editor` 0.3.5 (CodeController/CodeField, cách chèn text tại con trỏ) **xác minh ở T-00 từ source thật**
  sau `pub get`, dán vào contract T-03 — không để worker tự đoán.

Version đã kiểm pub.dev (Flutter 3.44.9 / Dart 3.12.2 local): flutter_riverpod 3.4.3 (Notifier API), go_router 18.0.1,
flutter_code_editor 0.3.5, google_fonts 8.2.1.

## Tasks (role · tier · model)
| ID | Nội dung | Role · tier · model | Phụ thuộc |
|---|---|---|---|
| T-00 | git bootstrap + `flutter create mobile` + deps + xác minh API flutter_code_editor | orchestrator tự làm | — |
| T-01 | domain models + seed + answer checker + test | crew-impl-standard · T2 · sonnet | T-00 |
| T-02 | theme tokens + shared widgets + test | crew-impl-light · T1 · haiku | T-00 |
| T-03 | **autocomplete**: engine thuần + widget CodeInput (editor + thanh gợi ý + phím ký hiệu + auto-close/indent) + test | crew-impl-standard · T2 · **opus** (nâng: đây là phần user ưu tiên nhất, UX nhiều edge case con trỏ/selection) | T-00 |
| — | checkpoint: analyze + test, commit checkpoint | orchestrator | |
| T-04 | session controller: tiến trình block (khoá/mở), timer, idle 2 phút + đếm ngược 60s, max timeout, hint ≤3 + test | crew-impl-standard · T2 · sonnet | T-01 |
| T-05 | Home, Theme detail, Topic detail | crew-impl-standard · T2 · sonnet | T-01, T-02 |
| T-06 | Block list, Cell (dùng CodeInput, hint sheet, idle dialog), router, main + widget test luồng | crew-impl-standard · T2 · sonnet | T-03, T-04, T-05 |

T-01, T-02, T-03 chạy song song (ownership rời; engine T-03 nhận input kiểu thuần `List<String>`, không import models).

Chung: Validation `cd mobile && flutter analyze && flutter test`. Evidence `git status --porcelain -uall -- <owned>`.
Forbidden: file ngoài owned, `mobile/pubspec.yaml` (trừ T-00), thư mục platform.
Owned (đường dẫn dưới `mobile/`, khai từng file):
- T-01: lib/domain/models.dart, lib/data/seed.dart, lib/domain/answer_checker.dart, test/seed_test.dart, test/answer_checker_test.dart.
  AC: seed 2–3 theme, RAG có Chunking → chunker.py → split_chunks (5 block), overlap_chunks; mỗi block ≤2 dòng, exercise ≤10 dòng,
  đúng 3 hint mờ→rõ, ID duy nhất, mỗi block có `vocab`; checker chấp nhận khác biệt khoảng trắng/dấu nháy đơn-kép.
- T-02: lib/app/theme.dart, lib/shared/widgets.dart, test/theme_test.dart. AC: 10 màu token, elevation 0, radius 6/12/pill, font từ google_fonts.
- T-03: lib/features/exercise/completion_engine.dart, lib/features/exercise/code_input.dart, test/completion_engine_test.dart, test/code_input_test.dart.
  AC: xếp hạng a>b>c; chạm gợi ý thay đúng từ đang gõ và con trỏ nằm cuối từ; `(` tự thêm `)` với con trỏ ở giữa; Enter sau `:` thụt 4;
  thanh gợi ý không che dòng đang gõ; widget test gõ `chu` → thấy `chunks` → chạm → text đúng.
- T-04: lib/features/exercise/session_controller.dart, lib/features/exercise/session_providers.dart, test/session_controller_test.dart.
  AC: clock giả trong test, không sleep; draft code của block giữ nguyên khi idle/thoát ra vào lại (trong phiên app).
- T-05: lib/features/browse/home_screen.dart, theme_detail_screen.dart, topic_detail_screen.dart.
- T-06: lib/features/exercise/block_list_screen.dart, lib/features/exercise/cell_screen.dart, lib/app/router.dart, lib/main.dart, test/app_flow_test.dart.
  AC: từ Home vào Cell đang dở ≤2 chạm (thẻ "Tiếp tục" trên Home → Block list → Cell là 2 chạm); test bắt đầu từ Home.

## Bất biến
INV-01 · Trạng thái block (done/active/locked) chỉ lấy từ session controller; B(N+1) mở khi B(N) đúng · phải khớp: session_controller.dart · block_list_screen.dart · cell_screen.dart · vỡ thì thấy gì: Run đúng B3 ở Cell, quay lại Block list B4 vẫn khoá.
INV-02 · Autocomplete gợi ý biến đã định nghĩa ở block trước và từ vựng của block hiện tại · phải khớp: seed.dart (vocab) · session_controller.dart (ghép code block trước) · completion_engine.dart · cell_screen.dart · vỡ thì thấy gì: ở B3 gõ `chu` không thấy `chunks`.
INV-03 · Code sinh ra bởi autocomplete (auto-close ngoặc, thụt 4 space) được answer checker chấp nhận khi đúng ý · phải khớp: code_input.dart · answer_checker.dart · seed.dart (đáp án) · vỡ thì thấy gì: gõ bằng gợi ý ra đúng `for i in range(0, len(text), size):` mà Run báo "Chưa đúng".
INV-04 · Màu chỉ đi từ theme.dart; `accent` chỉ dùng cho hint · phải khớp: theme.dart · lib/features/** · vỡ thì thấy gì: `grep -rn "Color(0x" lib/features` có kết quả, hoặc accent ngoài hint.
INV-05 · Idle/timeout lưu draft trước khi thoát · phải khớp: session_controller.dart · cell_screen.dart · vỡ thì thấy gì: idle tự thoát, vào lại mất code đang gõ.

## E2E (orchestrator tự chạy trước PR)
1. `flutter analyze && flutter test` sạch.
2. `test/app_flow_test.dart`: Home → Tiếp tục → Block list → Cell B3 → gõ `for i in ra` + chạm gợi ý `range(` … → Run → "Đúng" → quay lại Block list thấy B4 mở (INV-01, INV-03 qua mối nối).
3. Chạy app thật (`flutter run -d macos` hoặc web) + chụp màn Cell có thanh gợi ý.

## Kết thúc
Review từng task (crew-review T2) + reviewer mối nối → `verify-seam.sh` → commit, push branch, PR `Closes #3`.
Tạo issue phase 2 (Review/Stats/SM-2/Hive/cross-cut/backend). Không merge.
