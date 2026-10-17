# Backend: nội dung học + chấm bài

FastAPI có hai việc:

- `GET /content` — toàn bộ nội dung học (theme → topic → file → bài → ô TODO) từ Postgres. App tải
  lúc mở và lưu cache trên máy.
- `POST /run` — nhận code học viên (đã ghép từ các ô ở app), chạy unit test của bài trên máy chấm
  Python thật, trả kết quả từng test.

## Chạy local

Cần Postgres đang chạy (Homebrew: `brew services start postgresql@15`, cổng 5432).

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
set -a; [ -f .env ] && . ./.env; set +a        # tuỳ chọn (DATABASE_URL, máy chấm) — trước các lệnh dưới
createdb smart_coding_study                    # một lần
.venv/bin/alembic upgrade head                 # tạo bảng
.venv/bin/python -m app.load_content --if-empty  # nạp content/content.json nếu DB chưa có nội dung
.venv/bin/python -m app.seed_users             # tạo 2 tài khoản; mật khẩu vào backend/.initial-passwords (gitignore)
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

App iOS simulator gọi `http://127.0.0.1:8000` (đổi bằng `--dart-define=API_URL=...`; một biến cho
cả `/content` và `/run`).

```bash
curl -s localhost:8000/content | head -c 300
curl -s localhost:8000/run -H 'Content-Type: application/json' \
  -d '{"exercise_id": "clean-text", "code": "def clean_text(text):\n    return text.strip()"}'
```

## Thêm / sửa bài

**DB là nguồn chính.** Cách thường dùng: đăng nhập tài khoản admin → nút Admin → sửa → "Kiểm tra" →
"Lưu" (`/api/admin/content`, xem `app/admin_api.py`). `content/content.json` chỉ còn để seed lần đầu
và làm bản xuất (cùng shape `/content`, mỗi bài thêm `judge: {solution, cases}` — phần này KHÔNG trả
ra app). Sửa bằng file:

```bash
.venv/bin/python -m app.export_content content/content.json   # 1. lấy bản đang chạy (có sửa của admin)
# 2. sửa file
.venv/bin/python -m app.load_content --force                   # 3. kiểm đủ luật rồi thay toàn bộ
```

Lệnh nạp và nút Lưu của admin chạy CÙNG bộ kiểm (`load_content.validation_errors`: schema, id trùng,
judge, sơ đồ + `app/content_rules.py`: marker, ghép đáp án == lời giải, ≤3 ô, 3 gợi ý…) rồi **thay
toàn bộ** nội dung trong một transaction (khoá `pg_advisory_xact_lock`, không ghi xen nhau). Không có
`--force` thì CLI không ghi đè DB đã có nội dung. Tiến độ học viên ở bảng riêng, không bị xoá. App thấy
nội dung mới ở lần mở sau, không cần build lại. Giữ nguyên `id` bài và `id`/`label` ô khi sửa: tiến độ của học viên
gắn theo các id đó.

## Test

Cần Postgres local; test tự tạo DB `smart_coding_study_test` (từ chối chạy trên DB không có đuôi
`_test`).

```bash
.venv/bin/python -m pytest -q                  # không gọi mạng
JUDGE0_LIVE=1 .venv/bin/python -m pytest -q    # thêm 1 test gọi Judge0 thật
```

## Cách hoạt động

| Phần | File | Việc |
|---|---|---|
| API | `app/main.py` | `POST /run`, nối router `/content` |
| Nội dung | `app/content_api.py` | dựng payload `/content` từ DB (8 query cố định, đọc lại nếu đang nạp xen giữa); tra phần chấm cho `/run` |
| Nạp | `app/load_content.py` | validate + thay toàn bộ nội dung, tính `version` (sha256 phần công khai) |
| Bảng | `app/tables.py`, `migrations/` | SQLAlchemy + Alembic |
| Harness | `app/harness.py` | chạy TRÊN máy chấm: đọc stdin, chạy code + test case, in 1 dòng `__JUDGE_RESULT__{json}` |
| Máy chấm | `app/runner.py` | interface `CodeRunner`; bản hiện tại `Judge0Runner` |

## Đổi sang tự host máy chấm

- **Tự host Judge0 CE** (docker-compose của Judge0): đặt `JUDGE0_URL` (và `JUDGE0_TOKEN` nếu bật
  auth). Không sửa code.
- **Tự chạy container**: viết class mới cài `CodeRunner.run(source, stdin) -> Execution` trong
  `app/runner.py`, thêm nhánh trong `runner_from_env()`, đặt `CODE_RUNNER=<tên>`. Harness, API và
  app không đổi.

## Kết nối Claude (MCP)

Connector cho claude.ai, URL: `https://codewithphuong.jacons-corp.com/mcp`

1. claude.ai → Customize → Connectors → Add custom connector → dán URL → Connect.
2. Đăng nhập GitHub qua identity-service (`https://identity.jacons-corp.com`).
3. Lần đầu, tool báo "sub=… chưa được cấp quyền": admin chạy trên VPS (cùng cách `set_password` trong `deploy/README.md`):

```bash
ssh vps 'cd /opt/smart-coding-study/backend && set -a && . /etc/smart-coding-study.env && set +a && .venv/bin/python -m app.mcp_access allow <sub> --as <email admin>'
```

Tool (12): `list_projects`, `get_project`, `get_lesson`, `get_authoring_guide` (đọc); `create_project`,
`update_project`, `create_module`, `update_module`, `create_file`, `update_file`, `create_lesson`,
`update_lesson` (ghi, nhận `dry_run`).

- Mọi thay đổi có hiệu lực ngay với học viên. Luôn thử `dry_run=true` trước, rồi mới ghi thật.
- Thu hồi quyền: `python -m app.mcp_access revoke <sub>`, chạy theo cùng cách như trên.

Tool tài liệu System Design: `sd_list_docs`, `sd_get_doc`, `sd_create_doc`, `sd_replace_doc`, `sd_edit_doc`,
`sd_set_status`, `sd_delete_doc`. Xoá là xoá mềm (`status=archived`) — học viên không thấy nữa, bài nộp và tiến
độ còn nguyên; khôi phục bằng `sd_set_status`.

### Backfill markdown gốc

Tài liệu nhập trước khi có `source_md` không sửa lại được bằng `sd_edit_doc`. Nhập lại đúng file `.md` gốc,
giữ nguyên status. File phải nằm TRÊN VPS (đường dẫn trong lệnh là đường dẫn trên server):

```bash
scp backend/content/sd/<file>.md vps:/tmp/<file>.md
ssh vps 'cd /opt/smart-coding-study/backend && set -a && . /etc/smart-coding-study.env && set +a && .venv/bin/python -m app.sd.import_file /tmp/<file>.md --id <slug> --mode replace && rm /tmp/<file>.md'
```

Thêm `--dry-run` để xem trước số card thêm/bớt mà không ghi.

## Giới hạn

- `ce.judge0.com` là máy chủ công khai: code bài tập được gửi tới bên thứ ba, có giới hạn tần suất
  theo IP. Chỉ dùng cho dev; production nên tự host.
- Mỗi lần Run mất khoảng 2–3 giây (đo trên ce.judge0.com).
- Không chống gian lận: code học viên chạy cùng tiến trình với harness.
- Tiến độ học viên chưa lưu trên server (chỉ trong app).
