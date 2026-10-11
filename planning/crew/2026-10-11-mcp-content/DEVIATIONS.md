# DEVIATIONS — 2026-10-11-mcp-content

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| Validation dùng `.venv/bin/pytest` | venv mới của worktree không đặt `backend/` vào sys.path → ModuleNotFoundError | đổi mọi validation sang `.venv/bin/python -m pytest` (cùng test, khác cách gọi) | orchestrator — không đổi acceptance |
