# STATUS — 2026-10-17-mcp-publish-tool

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-17-mcp-publish-tool
Branch:   crew/2026-10-17-mcp-publish-tool (base origin/main 52da8c8 — user chọn; PR vào dev kéo theo 26 commit main mà dev chưa có)
Issue:    #59 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/59

| Task | Tier | Trạng thái |
|---|---|---|
| T-01 6 tool MCP publish (hàng chờ bài code + SD) | L4 orchestrator | đóng — PASS với Minor (1, 2, 5 sửa); external 0 finding |
| T-02 màn "Tài liệu SD" trong Admin (PLAN-v2) | T2 | đóng — PASS với Minor (Backlog) |

Cổng mối nối: SEAM 7/7 CÒN ĐÚNG (INV-07 ở PLAN-v2), verify-seam exit 0.

Next action: user review + merge PR vào dev (KHÔNG tự merge); khi đưa lên main/deploy: Disconnect → Connect connector trên claude.ai.

## Bằng chứng

- Backend full: `931 passed, 2 skipped` (38bb518); sau sửa review: test_mcp_publish/test_mcp/test_sd_mcp `74 passed`.
- Flutter full: xanh, `flutter analyze lib` sạch (gate T-02).
- E2E uvicorn thật: 9/9 PASS.
- Mutation bắt: bỏ rollback savepoint (test_failure_after_partial_write_is_rolled_back_per_id).

## Backlog

- T-01: id vượt int64 ở get_pending_change; lô 50 id giữ khoá lâu.
- T-02: test double-tap, include_archived query, encode id, 401/5xx màn SD; guard role phía client.
- SEAM: sd_set_status cũng publish được (cùng lớp chặn Needs approval).
- Tài liệu SD chưa có bản nháp riêng (sửa doc published lên ngay).
