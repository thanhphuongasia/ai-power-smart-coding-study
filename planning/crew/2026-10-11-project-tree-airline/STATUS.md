Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-project-tree-airline
Branch:   crew/2026-10-11-project-tree-airline
Issue:    #16 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/16

# Status: done (chờ user review PR)

Baseline: backend 94 passed / 2 skipped; mobile 294 passed (base feat/cell-gating 475f124).

| Task | Trạng thái |
|---|---|
| T-01 DB + loader | closed — PASS Minor; external Major bác bỏ (reviews/T-01-external.md) |
| T-02 /content tree | closed — PASS Minor |
| T-03 harness | closed — PASS Minor |
| T-04 mobile domain | closed — PASS Minor |
| T-05 cell location | closed — PASS Minor |
| T-06 browse screens | closed — PASS Minor |
| T-07 tree walkers | closed — PASS |
| T-08 airline seed | closed — PASS Minor |
| Seam INV-01..07 | CÒN ĐÚNG cả 7; verify-seam exit 0 |

Validation cuối: backend 141 passed / 2 skipped; mobile 312 passed; flutter analyze sạch.
E2E VPS (e2e/): /content airline đầu + 2 tầng module, không lộ judge; /run 3 bài airline passed, đổi tên method → "Không tìm thấy method"; split-chunks passed; Chrome Home → Airline → Flight → FlightService.add_flight → 3 ô → Run 5/5 passed (browser_add_flight_passed.jpg); site khác trên VPS giữ nguyên mã HTTP.
Model audit: impl/review T2 = claude-sonnet-5-5; external wrapper T1 = claude-haiku-5-5 (Codex gpt-5.6-sol bên trong).

Next action: user review/merge PR; sau merge mới dọn worktree.
## Backlog (Minor)
- T-08: project.output của bài raise ghi "ValueError" thay vì "ValueError: <msg>"; ví dụ add/search chưa dựng sẵn Flight/svc; test "thân pass phải đỏ" chưa có biến thể sai tinh vi
- T-07: chưa widget test home/stats với sub-module
- content_api children không kiểm theme_id (sửa DB tay); `in` trên list O(n²) chưa đo
- harness: test leak class-attr; SystemExit trong steps
- cellLocation: comment `#` thụt ít hơn làm cha; async for/with; header nhiều dòng; self.x từ đáp án ô trước
- browse: sub-module hiện trước file của chính module; card module chưa có tiến độ; test ≥3 tầng/375px
- content_json_test: chưa test bài dùng chung giữa file cha và sub-module
