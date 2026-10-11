Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    (không tạo)

# Status: open

| Task | Trạng thái |
|---|---|
| T-01 viết lại 9 bài BankAccount kiểu notebook tiến dần (crew-impl-standard) | done — review PASS với Minor (Minor 1, 3 đã sửa); seam PASS, verify-seam exit 0 |
| T-02 nạp VPS (orchestrator) | done — export VPS == content trước run (29 bài); KHÔNG chạy deploy.sh (main local chưa có 8 commit mcp-content, rsync --delete sẽ xoá MCP trên VPS) → scp riêng content.json + load_content --force sha256:bafcd895…; /content 31 bài, 9 bank-*, id cũ đủ; /run bank-init lời giải passed 6/6, mutant withdraw failed 6/6 |

Kiểm: pytest (DB sạch scs_progressive_verify_test) 360 passed, 2 skipped · flutter test 452 passed · validation_errors = [].

## Backlog (Minor)

- Test chống lộ bỏ dòng < 12 ký tự (review T-01 Minor 2).
- bank-apply-interest case mong đợi float lẻ 10.200000000000001 — dễ vỡ nếu đổi công thức tương đương.
- Nhãn ô A/B/C bank-init/bank-properties đổi nghĩa: draft cũ trên thiết bị có thể hiện vào ô mới cùng nhãn (VPS không có draft).
- DB test mặc định bị phiên mcp-content nâng lên 0005 — pytest mặc định lỗi môi trường tới khi merge 0005.

Next action: đồng bộ git — local main có commit 501547c chưa push; origin/main đi trước 8 commit (mcp-content). merge bị chặn vì mobile/ios/ci_scripts/ci_post_clone.sh sửa dở (nội dung == origin/main). Chờ user quyết.
