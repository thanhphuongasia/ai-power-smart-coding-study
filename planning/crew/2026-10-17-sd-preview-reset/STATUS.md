Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-17-sd-preview-reset
Branch:   crew/2026-10-17-sd-preview-reset
Issue:    #66 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/66

Trạng thái: P4 — PR vào dev, chờ user merge (KHÔNG tự merge)
Next action: user review + merge PR; distill đã dispatch

## Task
- T-01 backend (orchestrator, L4): PASS với Minor sau 2 vòng (external Major khoá section đã sửa)
- T-02 reader preview (crew-impl-standard): Major bị bác (DEVIATIONS) → đóng
- T-03 màn lộ trình preview + reset (crew-impl-standard) + T-03b correction (crew-impl-light): PASS với Minor
- SEAM: 6/6 CÒN ĐÚNG, verify-seam exit 0

## Kiểm chứng
- backend pytest full: 934 passed, 2 skipped
- flutter test full: 816 passed; flutter analyze lib: No issues found
- E2E uvicorn thật (DB riêng, đã xoá): 13/13 PASS (INV-02..06)
- INV-01 (preview không ghi tiến độ): widget test sd_reader_test (P), chưa chạy trên thiết bị

## Backlog
- T-01: chưa có test đồng thời DELETE↔PUT; section mới thêm khi admin nhập lại đúng lúc reset vẫn có thể chen PUT
- T-02: guard preview rải 4 chỗ; preview với backend cũ không nhảy section khoá
- T-03: assert matchedLocation lặp; chưa chặn bấm đôi reset (idempotent); chưa test header 360px
- SEAM: toast "Hoàn thành section trước để mở khoá" ở sd_path_screen/reader_menu gần như code chết — dọn sau
- Phase 2 vẫn chờ đọc hết section (giữ theo plan) — đổi nếu user muốn
