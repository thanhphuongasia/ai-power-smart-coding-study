# DEVIATIONS — 2026-10-17-sd-docs-mcp

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| Validation dùng `.venv/bin/pytest` | Dùng `.venv/bin/python -m pytest` (venv worktree thiếu sys.path) | Cùng test, khác cách gọi | orchestrator |
| T-01 owned không có `backend/tests/test_sd_schema.py` | Test ghi cứng alembic head "0007" → thêm 0008 thì phải đổi thành "0008" | Thêm file vào owned T-01, chỉ đổi đúng 1 dòng | orchestrator |
