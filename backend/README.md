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
.venv/bin/python -m app.load_content           # nạp content/content.json, in version
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

Nguồn soạn duy nhất là `content/content.json` (cùng shape `/content`, mỗi bài thêm
`judge: {solution, cases}` — phần này KHÔNG trả ra app). Sửa file rồi nạp lại:

```bash
.venv/bin/python -m app.load_content
```

Lệnh nạp kiểm dữ liệu trước (id trùng, bài không tồn tại, thiếu judge…) rồi **thay toàn bộ** nội
dung trong một transaction. Sửa thẳng trong DB sẽ bị lần nạp sau ghi đè. App thấy nội dung mới ở
lần mở sau, không cần build lại. Giữ nguyên `id` bài và `id`/`label` ô khi sửa: tiến độ của học viên
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
| Nội dung | `app/content_api.py` | dựng payload `/content` từ DB (7 query cố định); tra phần chấm cho `/run` |
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

## Giới hạn

- `ce.judge0.com` là máy chủ công khai: code bài tập được gửi tới bên thứ ba, có giới hạn tần suất
  theo IP. Chỉ dùng cho dev; production nên tự host.
- Mỗi lần Run mất khoảng 2–3 giây (đo trên ce.judge0.com).
- Không chống gian lận: code học viên chạy cùng tiến trình với harness.
- Tiến độ học viên chưa lưu trên server (chỉ trong app).
