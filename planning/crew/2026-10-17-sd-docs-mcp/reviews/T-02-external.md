Answer: Có — 2 lỗi thực tế; body unauthenticated vẫn bị chặn trước khi SDK đọc, và mọi tool doc đều gọi `_authorized`.

- Low — `backend/app/mcp_server.py:88`: lỗi quyền trả cả JWT `sub` và lệnh CLI nội bộ cho client; fix: dùng thông báo quyền chung, chỉ log chi tiết phía server.
- Medium — `backend/app/mcp_server.py:367`: `sd_edit_doc` gắn `_WRITE` với `destructive_hint=False` dù `new_text` có thể xoá/đổi section, task và làm mất tiến độ; fix: dùng annotation destructive như `_UPDATE` nhưng giữ `idempotent_hint=False`.
