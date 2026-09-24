# Plan — Sửa feedback Codex trên PR #4

## Context
Codex review PR #4 (https://github.com/thanhphuongasia/ai-power-smart-coding-study/pull/4) đề nghị chưa approve.
Orchestrator đã đối chiếu code thật, 4 điểm đúng cần sửa:
1. Idle: `_runCode` (cell_screen.dart:51) và nút "Gợi ý rõ hơn" (:133) không gọi `activity()` → đang bấm Run/xem hint vẫn bị coi là bỏ máy.
2. Accessibility: nút back là `GestureDetector` + icon 24px (widgets.dart:205, cell_screen.dart:387), `SurfaceCard` dùng `GestureDetector` → không ripple, không semantics button, vùng chạm < 48dp.
3. Editor khi bàn phím đóng: `SizedBox(height: 200)` cố định (cell_screen.dart:296), đề bài `Expanded` chiếm khoảng trống lớn; editor không placeholder, không focus state.
4. Home thẻ Tiếp tục ghi "Block 2/5" nhưng mở Block 3 (home_screen.dart:~70).
Không làm (đã nói với user): light theme (design system chỉ có dark), bottom nav (phase 2, #5).

Làm tiếp trên branch `crew/2026-09-24-flutter-demo-core`, worktree cũ (PR đã mở → push thêm commit, không tạo worktree/PR mới). Run dir mới: `planning/crew/2026-09-24-pr4-codex-fixes/`.

## Quyết định
- Back: `IconButton` (48×48 mặc định Material, `tooltip: 'Quay lại'` → nhãn screen reader). Áp ở `ScreenHeader` và `_CompactHeader`.
- `SurfaceCard`: `Material(color: surfaceRaised, shape viền outline/primary, radius md)` + `InkWell` (ripple, bo góc) + `Semantics(button: onTap != null)`. Không shadow (elevation 0). Giữ nguyên chữ ký public.
- Idle: `activity()` khi bấm Run, mở hint sheet, bấm "Gợi ý rõ hơn". Đọc đề mà không chạm gì vẫn tính idle (đúng yêu cầu gốc "đứng im thì nhắc").
- Editor bàn phím đóng: đề bài + block đã xong tối đa ~40% chiều cao còn lại (cuộn nếu dài), editor `Expanded` lấy phần còn lại. Nhánh bàn phím mở giữ nguyên (T-06b đã đo).
- Placeholder "Nhập code" (ink-muted, font mono) hiện khi text rỗng, là lớp hiển thị `IgnorePointer` — KHÔNG vào controller. Focus: viền editor 1px outline → 2px primary khi focus (focus ring của design system).
- Home thẻ Tiếp tục: "Tiếp tục Block {completed+1}/{total}" + dòng phụ "Đã xong {completed}/{total}".

## Tasks (role · tier · model) — 4 task song song, ownership rời hẳn
| ID | Nội dung | Role · tier · model | Owned (dưới mobile/) |
|---|---|---|---|
| T-01 | SurfaceCard InkWell+Semantics, ScreenHeader IconButton | crew-impl-light · T1 · haiku | lib/shared/widgets.dart, test/theme_test.dart |
| T-02 | Cell: idle activity ở Run/hint, layout editor bàn phím đóng, back _CompactHeader | crew-impl-standard · T2 · sonnet | lib/features/exercise/cell_screen.dart, test/cell_layout_test.dart, test/cell_idle_test.dart (mới) |
| T-03 | CodeInput placeholder + focus border | crew-impl-standard · T2 · sonnet | lib/features/exercise/code_input.dart, test/code_input_test.dart |
| T-04 | Home nhãn Tiếp tục | crew-impl-light · T1 · haiku | lib/features/browse/home_screen.dart, test/browse_screens_test.dart |

Validation mỗi task: `cd mobile && flutter analyze && flutter test`. Evidence: `git diff --stat -- <owned>` + `git status --porcelain -uall -- <owned>`.
Forbidden: mọi file ngoài owned, pubspec.yaml, planning/** (trừ orchestrator).
Không git checkout/restore/stash; thử tạm bằng cp. Nhắc Flutter lock + timeout 600000.

AC chính:
- T-01: back có tooltip 'Quay lại', vùng chạm ≥48×48 (test getSize); SurfaceCard có InkWell, semantics button khi có onTap, không có khi onTap null; elevation 0; mọi test cũ xanh (app_flow_test tap `Icons.arrow_back` vẫn chạy).
- T-02: widget test: Run lúc 100s → tới 170s phase vẫn active; mở hint lúc 100s tương tự; không chạm gì 120s → idle (giữ hành vi). cell_layout_test thêm: bàn phím đóng ở 360x640 editor cao ≥ 45% chiều cao màn và không overflow; nhánh bàn phím mở giữ đo cũ.
- T-03: text rỗng → thấy "Nhập code"; gõ 1 ký tự → placeholder mất; `controller.text` không bao giờ chứa "Nhập code"; focus → viền 2px primary, blur → 1px outline.
- T-04: Home "Tiếp tục Block 3/5" + "Đã xong 2/5" cho split-chunks; test INV-02 cũ cập nhật số.

## Bất biến
INV-01 · Mọi tương tác của người học ở Cell (gõ, chạm gợi ý/phím, Run, mở hint, gợi ý rõ hơn) đều reset mốc idle · phải khớp: cell_screen.dart (_runCode, _showHintSheet) · code_input.dart (onActivity) · session_controller.dart (activity) · vỡ thì thấy gì: bấm Run liên tục trong 2 phút vẫn hiện "Vẫn đang làm chứ?".
INV-02 · Số block trên thẻ Tiếp tục = block Cell sẽ mở (completed+1), "Đã xong" = completedBlocks · phải khớp: home_screen.dart (_ContinueCard) · block_list_screen.dart (banner "đang làm dở Block n") · cell_screen.dart (subtitle 'Block ${index+1}/$total') · vỡ thì thấy gì: Home ghi Block 3/5 nhưng Cell mở Block 4/5 hoặc banner ghi Block khác.
INV-03 · Đổi widget chạm (InkWell/IconButton) không đổi Key, chữ, khả năng tap của luồng cũ · phải khớp: widgets.dart · cell_screen.dart (_CompactHeader) · app_flow_test.dart · browse_screens_test.dart · vỡ thì thấy gì: test luồng Home→Cell fail ở bước tap, hoặc card locked vẫn bấm được.
INV-04 · Placeholder chỉ là lớp hiển thị, không vào text/draft/runBlock · phải khớp: code_input.dart · cell_screen.dart (onChanged → saveDraft) · answer_checker.dart · vỡ thì thấy gì: draft rỗng lưu thành "Nhập code", hoặc Run chấm chuỗi placeholder.
INV-05 · Layout bàn phím mở của T-06b giữ nguyên sau khi đổi nhánh bàn phím đóng · phải khớp: cell_screen.dart · cell_layout_test.dart · vỡ thì thấy gì: cell_layout_test 360x640 bàn phím mở fail / Run bị che.

## E2E (orchestrator tự chạy)
1. `flutter analyze && flutter test` sạch.
2. app_flow_test (Home → Cell → Run → Block 4 mở) vẫn xanh sau đổi widget chạm (qua mối nối INV-03).
3. Widget test idle: Run ở giây 100 → giây 170 chưa idle (INV-01).
4. `flutter build web` + chụp Home và Cell ở 600px xem thẻ Tiếp tục + editor + placeholder.

## Kết thúc
Review từng task + reviewer mối nối → verify-seam.sh → commit, push vào branch PR #4, comment trả lời Codex trên PR. Không merge.
