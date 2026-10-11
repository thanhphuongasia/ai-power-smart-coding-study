# T-02 — second opinion từ agent ngoài (lần 2)

Vendor: codex · model: gpt-5.6-sol (provider openai) · timeout=360s
Phạm vi: backend/app/runner.py, backend/app/main.py, backend/tests/test_api.py (đối chiếu backend/app/harness.py). Chỉ đọc.

## Findings (nguyên văn từ agent ngoài)

- **Critical — Correctness/Security — `backend/app/harness.py:73-76,112-115`, `backend/app/main.py:97-103`:** Code học viên chạy cùng process (`exec(compiled, namespace)`) nên có thể monkey-patch `json.dumps`; output hợp lệ giả mạo vẫn được `RunResponse.model_validate(...)` chấp nhận. Đã tái hiện response `200` với `status:"passed"` dù không có hàm cần chấm.
- **Major — Security/Async — `backend/app/main.py:29-31,36-38,87-88`:** `Field(max_length=8000)` chỉ kiểm tra sau khi toàn bộ JSON đã được đọc; extra field mặc định bị bỏ qua, nên request body vẫn không giới hạn. `_RUN_SLOTS = asyncio.Semaphore(4)` chỉ giới hạn job đang chạy, không giới hạn số coroutine/body đang chờ, tạo đường local memory-DoS.
- **Major — Correctness — `backend/app/runner.py:66,118-124`, `backend/app/main.py:105-114`:** `_INFRA_ERRORS = {1, 2, 13, 14}` khiến status `6` và mọi status lạ rơi vào `Execution("error", ...)`, rồi API trả lỗi học viên `200`; nhưng `6` là Compilation Error của harness cố định, phải là lỗi máy chấm `503`. [Judge0 status reference](https://ce.judge0.com/)
- **Major — Correctness — `backend/app/main.py:70-76,86-91`, `backend/app/runner.py:127-135`:** Dependency gọi `runner_from_env()` trước khối `try`; `raise ValueError(...)` khi `CODE_RUNNER` sai thoát thành `500 Internal Server Error`, không phải JSON `503 runner_unavailable`. Đã tái hiện trực tiếp.
- **Minor — Tests — `backend/tests/test_api.py:117-124,165-166,210-226`:** Chỉ test forged result sai shape, code dài trong field, và status `{1,2,13,14}`; thiếu valid forged result, body/queue quá lớn, status `6`/unknown, và cấu hình runner sai. Không thấy finding về lộ `JUDGE0_TOKEN`; không có finding async khác ngoài hàng chờ không giới hạn.

## Ghi chú của orchestrator (không thuộc output agent ngoài)

- Agent ngoài báo 31 passed, 1 skipped khi chạy pytest trong backend/ (đã kiểm: `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider tests/test_api.py`).
- Chạy từ root repo lỗi import `app` và `.venv` không tồn tại — chỉ là cách gọi sai, không phải lỗi code.
- Finding Critical (monkey-patch `json.dumps`) và Major (status 6) cần kiểm lại bởi người/agent khác trước khi sửa; agent ngoài đã tự tái hiện được hai trường hợp này.
