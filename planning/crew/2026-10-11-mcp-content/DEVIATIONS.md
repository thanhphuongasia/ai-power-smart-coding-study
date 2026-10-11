# DEVIATIONS — 2026-10-11-mcp-content

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| Validation dùng `.venv/bin/pytest` | venv mới của worktree không đặt `backend/` vào sys.path → ModuleNotFoundError | đổi mọi validation sang `.venv/bin/python -m pytest` (cùng test, khác cách gọi) | orchestrator — không đổi acceptance |
| Review T-01 (m3 nội bộ, Minor 4 external): không giữ khoá suốt lần tải JWKS | Giữ nguyên một khoá | Bác: tải chỉ xảy ra tối đa 1 lần / 60s (min_refresh tính cả lần lỗi), timeout 5s → request khác chờ tối đa 5s mỗi phút; single-flight thêm độ phức tạp cho ca chưa đo thấy nghẽn. Ghi docstring JwksCache | orchestrator |
| Review T-01 (m4): giới hạn kích thước token | Không thêm | Bác: header đã bị uvicorn/h11 giới hạn (~64KB), JWKS giới hạn bởi identity-service do mình vận hành | orchestrator |
| Review T-02 Minor 1–3, T-03 Minor 1–4 | Không sửa trong run | Ghi Backlog STATUS.md (PASS với Minor) | orchestrator |
