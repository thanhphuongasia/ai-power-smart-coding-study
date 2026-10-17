# DEVIATIONS — 2026-10-17-mcp-publish-tool

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| PLAN chỉ có T-01 (backend MCP) | User yêu cầu giữa run thêm nút approve/publish trên UI; nút duyệt bài code đã có sẵn | PLAN-v2: thêm T-02 màn 'Tài liệu SD' (publish/ẩn/khôi phục) | user (tin nhắn giữa run) |
| Review T-02 Minor 1–3 (test double-tap, include_archived query, encode id, 401/5xx; guard client) | Không sửa | Backlog | orchestrator |
| Review T-01 Minor 1, 2, 5 | Bắt OperationalError theo từng id; test savepoint hoàn tác ghi dở (mutation bắt được); sắp import | Chấp nhận | orchestrator |
| Review T-01 Minor 3–4 (id vượt int64 ở get_pending_change; lô 50 giữ khoá lâu) | Không sửa | Backlog | orchestrator |
