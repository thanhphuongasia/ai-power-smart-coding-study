# T-01 — second opinion (external agent)

vendor=codex model=<default> (gpt-5.6-sol, reasoning high) · timeout=360s · exit=0

## Findings (nguyên văn)

- **Answer**: CẦN SỬA — 2 lỗi nghiêm trọng; model/migration hiện khớp, downgrade đúng thứ tự, chưa thể xác minh việc ẩn judge fields ở API.
- **Critical — `backend/tests/conftest.py:20-22,44-47`**: URL tùy ý từ `TEST_DATABASE_URL` được chạy thẳng qua `command.downgrade(config, "base")`; cấu hình nhầm production/staging sẽ xoá 7 bảng và dữ liệu thật.
- **Major — `backend/tests/conftest.py:29-31`**: `text(f'create database "{target.database}"')` nối identifier trực tiếp; tên DB chứa `"`, `;` có thể SQL injection. Cần validate allowlist và quote bằng `psycopg.sql.Identifier`.
- **Minor — `backend/app/db.py:18-19`, `backend/migrations/env.py:17`**: `engine = create_engine(database_url(), ...)` chạy lúc import, làm `SessionLocal` giữ URL cũ nếu environment đổi sau đó; `create_engine` chưa kết nối ngay nhưng vẫn tạo pool thừa khi Alembic chỉ import `database_url`.
- **Minor — `backend/app/tables.py:32-33,42-43,68-70,77-81`**: thiếu `UNIQUE(parent_id, position)`, `CHECK(position >= 0)` và index riêng cho `file_exercises.exercise_id`; thứ tự có thể mơ hồ và cascade từ exercise phải full-scan bảng nối. `test_schema.py:16-23` không phát hiện vì chỉ kiểm migration khớp model.
- **Before vs After**: Hiện test có thể phá DB thật và schema chưa tự bảo vệ ordering; sau sửa cần guard DB test, quote identifier, lazy/factory engine, constraints và reverse-FK index đồng bộ model–migration.
- **Example**: `TEST_DATABASE_URL=.../prod` hiện dẫn tới `downgrade base`; tên percent-encoded như `foo%22%3B...` có thể biến thành `create database "foo"; ...`.

## Mâu thuẫn trong output của agent

Không có mâu thuẫn nội bộ. Ghi nhận: agent nói "chưa thể xác minh" việc ẩn judge fields ở API.
