# Backend chấm bài

FastAPI nhận code học viên (đã ghép từ các ô TODO ở app), chạy unit test của bài trên máy chấm
Python thật, trả kết quả từng test.

## Chạy local

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
set -a; [ -f .env ] && . ./.env; set +a      # tuỳ chọn, mặc định dùng ce.judge0.com
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

App iOS simulator gọi `http://127.0.0.1:8000` (đổi bằng `--dart-define=JUDGE_URL=...`).

```bash
curl -s localhost:8000/run -H 'Content-Type: application/json' \
  -d '{"exercise_id": "clean-text", "code": "def clean_text(text):\n    return text.strip()"}'
```

## Test

```bash
.venv/bin/python -m pytest -q                  # không gọi mạng
JUDGE0_LIVE=1 .venv/bin/python -m pytest -q    # thêm 1 test gọi Judge0 thật
```

## Cách hoạt động

| Phần | File | Việc |
|---|---|---|
| API | `app/main.py` | `POST /run {exercise_id, code}` → ghép payload, gọi máy chấm, trả JSON |
| Harness | `app/harness.py` | chạy TRÊN máy chấm: đọc stdin, chạy code + test case, in 1 dòng `__JUDGE_RESULT__{json}` |
| Test case | `app/exercises.json` | test + lời giải tham chiếu từng bài (app không sửa được) |
| Máy chấm | `app/runner.py` | interface `CodeRunner`; bản hiện tại `Judge0Runner` |

Máy chấm chỉ cần làm một việc: chạy chương trình Python với stdin và trả stdout.

## Đổi sang tự host

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
