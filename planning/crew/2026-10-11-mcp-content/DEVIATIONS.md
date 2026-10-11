# DEVIATIONS — 2026-10-11-mcp-content

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| Validation dùng `.venv/bin/pytest` | venv mới của worktree không đặt `backend/` vào sys.path → ModuleNotFoundError | đổi mọi validation sang `.venv/bin/python -m pytest` (cùng test, khác cách gọi) | orchestrator — không đổi acceptance |
| Review T-01 (m3 nội bộ, Minor 4 external): không giữ khoá suốt lần tải JWKS | Giữ nguyên một khoá | Bác: tải chỉ xảy ra tối đa 1 lần / 60s (min_refresh tính cả lần lỗi), timeout 5s → request khác chờ tối đa 5s mỗi phút; single-flight thêm độ phức tạp cho ca chưa đo thấy nghẽn. Ghi docstring JwksCache | orchestrator |
| Review T-01 (m4): giới hạn kích thước token | Không thêm | Bác: header đã bị uvicorn/h11 giới hạn (~64KB), JWKS giới hạn bởi identity-service do mình vận hành | orchestrator |
| Review T-02 Minor 1–3, T-03 Minor 1–4 | Không sửa trong run | Ghi Backlog STATUS.md (PASS với Minor) | orchestrator |
| External T-04 Major 1: test khoá ghi bằng connection độc lập + barrier | Thêm test chen lần ghi giữa validate và khoá (cùng session, giả lập) — bắt được mutation bỏ khoá / bỏ so version; chưa có race thật hai connection | Chấp nhận một phần: fixture DB test rollback theo transaction nên connection độc lập phải commit thật vào DB test dùng chung (dễ gây đỏ lẻ tẻ — xem recurring-failures). Khoá là `pg_advisory_xact_lock` dùng chung với admin PUT đã chạy production | orchestrator |
| Review T-04 Minor 4 (lock_timeout 15s giữ connection) | Không đổi | Backlog: 1 admin, chưa đo thấy nghẽn | orchestrator |
| Review T-05 Minor 3 (README local env) | Không sửa | Backlog | orchestrator |
| Re-review T-04 r2 Minor M1: "đổi thứ tự khoá/so version test vẫn xanh" | Mutation thật (so version trước, khoá sau) → test_write_between_validate_and_lock_is_refused ĐỎ | Bác: lần ghi chen nằm trong lock_content nên đổi thứ tự là bị bắt | orchestrator |
| SEAM ngoài sổ #3: test chen-ghi đỏ khi chạy gộp 4 file | Chạy gộp 3 lần liên tiếp: 100/100 cả 3 | Bác: trùng lúc reviewer khác chạy pytest trên DB test dùng chung (recurring-failures: test DB dùng chung) | orchestrator |
| SEAM ngoài sổ #2: đổi mật khẩu app không thu hồi mcp_access | Giữ | Quyền MCP gắn tài khoản identity (GitHub), không gắn mật khẩu app; cắt bằng `revoke`. Ghi README/Backlog | orchestrator |
