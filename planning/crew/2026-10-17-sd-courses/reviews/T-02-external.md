# T-02 external review (vendor=codex, model=gpt-5.6-terra, timeout=540s)

Answer: Có 1 lỗi interface MCP; các tool đều đi qua `_sd_doc` nên có authorization.

- Medium — `backend/app/mcp_server.py:431`: `changes: dict[str, Any]` tạo schema nhận mọi key/value, trái với docstring chỉ cho `title`, `skills`, `domain`, `position`; sửa bằng model/TypedDict có bốn field và kiểu riêng.

Before vs After: client hiện có thể gửi `{"status":"archived"}` hoặc `{"position":"first"}`; schema mới chặn từ MCP trước khi gọi service.

Example: `changes={"title": "System Design", "position": 2}`.
