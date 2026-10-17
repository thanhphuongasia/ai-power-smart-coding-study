# DEVIATIONS — 2026-10-17-sd-docs-mcp

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| Validation dùng `.venv/bin/pytest` | Dùng `.venv/bin/python -m pytest` (venv worktree thiếu sys.path) | Cùng test, khác cách gọi | orchestrator |
| T-01 owned không có `backend/tests/test_sd_schema.py` | Test ghi cứng alembic head "0007" → thêm 0008 thì phải đổi thành "0008" | Thêm file vào owned T-01, chỉ đổi đúng 1 dòng | orchestrator |
| T-02 owned không có `backend/tests/test_mcp.py` | test liệt kê đúng tập tool + test 413 ở 70KB → phải cập nhật (thêm 7 tool, ngưỡng 413 lên >2MB) | Thêm vào owned T-02 | orchestrator |
| T-02: tests/test_sd_mcp.py khẳng định "không có tool sd_*delete*" (run system-design-mode) | User yêu cầu xoá mềm doc (sd_delete_doc) | Thu hẹp assert thành "không có tool xoá bài nộp"; file thêm vào owned T-02 | user (chọn xoá mềm) |
| External T-01 Major 1: rollback toàn phần xoá việc chưa commit của caller | Bỏ rollback ở dry_run; giữ rollback ở nhánh lỗi | Bác một phần: service tự quản transaction (tự commit, như `_save`/`_import` cũ); mọi caller dùng session riêng mỗi lần gọi — ghi hợp đồng ở docstring `sd/docs.py` | orchestrator |
| Review T-01 M-4 (NFC trong apply_edits), M-5, M-3 phần downgrade/2 connection | Không sửa | Backlog: old_text không khớp thì báo lỗi rõ (an toàn); test 2 connection thật dễ đỏ lẻ trên DB test dùng chung (recurring-failures) | orchestrator |
| External T-01 Major 2 (identity map cũ): thêm test hai session | Thêm `populate_existing=True` ở mọi lần đọc sau khoá; test tái hiện KHÔNG ổn định (cùng kịch bản, session dựng khác nhau cho kết quả khác) → bỏ test, không để test giả xanh | Chấp nhận bản sửa, không có test máy bắt mutation này; caller thật dùng session mới mỗi lần gọi | orchestrator |
