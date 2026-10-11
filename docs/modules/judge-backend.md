# Judge backend (chấm bài bằng Python thật)

> Server FastAPI nhỏ trong `backend/`: nhận code đã ghép của một bài, chạy cùng unit test qua máy
> chấm ngoài (Judge0), trả kết quả từng test. Dùng bởi `JudgeClient` của app Flutter.

## Là gì

Trước đây app chấm bằng cách so chuỗi code người học gõ với vài đáp án viết sẵn, nên cách viết
đúng nhưng khác đi vẫn bị chấm sai. Backend này thay bằng chấm thật: chạy code người học với các
test case của bài rồi báo test nào đúng, test nào sai, và lỗi ở dòng mấy. Test case và lời giải
tham chiếu chỉ nằm ở backend nên app không sửa được chúng. Backend không tự thực thi code — nó nhờ
một "máy chấm" bên ngoài qua interface `CodeRunner`, hiện là Judge0 CE công khai, và có thể đổi
sang tự host mà không đụng API hay app.

## Dùng khi nào

App gọi `POST /run` mỗi lần người học bấm Run ở tab Code (`JudgeClient.run`). Chạy local bằng
`uvicorn app.main:app --host 127.0.0.1 --port 8000`; app mặc định trỏ `http://127.0.0.1:8000`, đổi
bằng `--dart-define=JUDGE_URL`. Biến môi trường backend: `CODE_RUNNER`, `JUDGE0_URL`,
`JUDGE0_TOKEN` (backend/.env.example).

## Cách hoạt động

Backend ghép payload JSON `{code, function, cases}`, gửi `harness.py` làm chương trình và payload làm
stdin cho runner. Harness compile code người học với tên file `solution.py` (để số dòng lỗi là số
dòng của code đã gửi), chạy từng case rồi in đúng một dòng `__JUDGE_RESULT__{json}`.

| Tình huống | Backend trả | Nơi xử lý |
|---|---|---|
| Bài không có trong `exercises.json` | 404 `exercise_not_found` | backend/app/main.py:91-93 |
| Body sai / `code` > 8000 ký tự | 422 `invalid_request` (không lặp lại input) | backend/app/main.py:56-61 |
| Máy chấm hỏng, 429, 5xx, mã trạng thái lạ | 503 `runner_unavailable` (body không chứa token) | backend/app/main.py:103-105, backend/app/runner.py:107-125 |
| Máy chấm báo quá giờ (Judge0 status 5) | 200 `status: timeout` | backend/app/main.py:108-109 |
| Harness in kết quả | 200 `passed` / `failed` / `error` + `tests[]` | backend/app/main.py:111-116 |
| Harness bị dừng trước khi in (hết bộ nhớ...) | 200 `error` kind `runtime`, `line: null` | backend/app/main.py:119-128 |

Case test có hai dạng, hiển thị được "input / mong đợi / nhận được":

```python
if "return" in expect:
    expected_value = expect["return"]
else:
    expected_value = expect["value"]
```
(backend/app/harness.py:91-94) — dạng `return` so giá trị trả về; dạng `{"arg": i, "value": v}` so tham
số thứ i sau khi gọi (cho hàm sửa tham số tại chỗ như `save_document`).

Hợp đồng đáp ứng: `status`, `error {kind, line, message}`, `tests [{call, expected, actual, passed}]`,
`stdout`, `duration_ms`; `expected`/`actual` là `repr()` (backend/app/main.py:64-82).

## Ranh giới & đánh đổi

Harness tách khỏi máy chấm: máy chấm nào cũng chỉ cần "chạy Python với stdin", nên chuyển sang tự
host Judge0 (đổi `JUDGE0_URL`) hay viết `DockerRunner` mới (cùng `CodeRunner`) đều không đụng
`main.py` hay harness. Chưa viết `DockerRunner` vì mới có một runner thật.

Không làm: xác thực người dùng, chống gian lận (code người học chạy cùng tiến trình với harness nên
có thể in dòng kết quả giả — review external gắn Critical, bị bác vì đã khai trong PLAN), hàng chờ
có timeout tổng. Backend cũng không biết gì về tiến độ người học; "xong bài" do app quyết định từ
`status == passed`.

Giới hạn tài nguyên mỗi lần chạy gửi kèm: `cpu_time_limit=2`, `wall_time_limit=5`,
`memory_limit=128000`, timeout HTTP tới máy chấm 15s (backend/app/runner.py:85-92,
backend/app/runner.py:69-77); tối đa 4 request đồng thời tới máy chấm
(backend/app/main.py:31-32); body tối đa 64KB (backend/app/main.py:30,39-48).

## Giới hạn đã biết

- Code học viên đi qua `https://ce.judge0.com` (bên thứ ba, giới hạn theo IP) — chỉ hợp dev local.
- `JUDGE0_URL` không kiểm scheme: đặt `http://` thì token đi plaintext; hàng chờ semaphore không có
  timeout tổng (planning/crew/2026-10-11-exercise-tabs-judge/STATUS.md:39 — Backlog T-02).
- Harness so bằng `==` nên `True == 1` coi là bằng; case ném exception thì dừng, các case sau không
  chạy (backend/app/harness.py:99-104,108); test deepcopy yếu; `\r` lẻ trong code làm lệch số dòng
  so với `lineOrigin` của app (STATUS.md:47, M-8).
- `os._exit` trong code học viên cho 503 thay vì lỗi của học viên (STATUS.md:47, M-7).
- Test thật gọi Judge0 là test `live`, mặc định skip (backend/tests/test_api.py).

## Nguồn

- API, middleware, ánh xạ kết quả: backend/app/main.py:25-130
- `CodeRunner`, `Judge0Runner`, `runner_from_env`: backend/app/runner.py:20-136
- Harness: backend/app/harness.py:1-120
- Dữ liệu bài + lời giải tham chiếu: backend/app/exercises.json (key = exercise id)
- Phía app: mobile/lib/data/judge_client.dart:57-149
- Quyết định và lý do: docs/DECISIONS.md mục "Chấm bài bằng Python thật qua backend", "Máy chấm qua interface `CodeRunner`", "Harness độc lập máy chấm"
- Run: planning/crew/2026-10-11-exercise-tabs-judge/PLAN.md, STATUS.md, reviews/T-02*.md
