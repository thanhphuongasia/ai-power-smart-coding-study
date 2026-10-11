Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    (không tạo)

# Status: open

| Task | Trạng thái |
|---|---|
| T-01 viết lại 9 bài BankAccount kiểu notebook tiến dần (crew-impl-standard) | done — review PASS với Minor (Minor 1, 3 đã sửa); seam PASS, verify-seam exit 0 |
| T-02 nạp VPS (orchestrator) | đang chạy |

Kiểm: pytest (DB sạch scs_progressive_verify_test) 360 passed, 2 skipped · flutter test 452 passed · validation_errors = [].

## Backlog (Minor)

- Test chống lộ bỏ dòng < 12 ký tự (review T-01 Minor 2).
- bank-apply-interest case mong đợi float lẻ 10.200000000000001 — dễ vỡ nếu đổi công thức tương đương.
- Nhãn ô A/B/C bank-init/bank-properties đổi nghĩa: draft cũ trên thiết bị có thể hiện vào ô mới cùng nhãn (VPS không có draft).
- DB test mặc định bị phiên mcp-content nâng lên 0005 — pytest mặc định lỗi môi trường tới khi merge 0005.

Next action: T-02 — export so sánh → deploy.sh → load_content --force → kiểm /content 31 bài.
