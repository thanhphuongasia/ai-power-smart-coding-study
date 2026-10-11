# T-06 — second opinion (external agent)

vendor=codex model=<default> (gpt-5.6-sol, reasoning high) · timeout=360s

## Nguyên văn findings

**Answer:** CẦN SỬA tại commit `88c2075`; worktree hiện sạch, không còn file untracked; có 2 Major và 1 Minor.
**Major — backend/app/content_api.py:31-40,81-84:** `/content` đọc version rồi sáu `SELECT` riêng; mô phỏng reload xen giữa cho `KeyError 'removed'`, nên có thể trả 500 hoặc version cũ với cây mới. Cần một snapshot `REPEATABLE READ` và test hai transaction xen kẽ.
**Major — backend/app/content_api.py:114-119; backend/app/main.py:109-111:** DB đã migrate nhưng chưa nạp làm `/run` trả `404 {"detail":"exercise_not_found"}`, trong khi `/content` trả 503. Cần kiểm `ContentMeta` trước khi phân biệt ID lạ.
**Minor — backend/tests/test_content_api.py:56-61:** chỉ test bài dùng chung; kiểm fixture cho `orphans []`, nên nhánh bài không thuộc file chưa được phủ. Thêm orphan và assert xuất hiện một lần ở cuối, đồng thời `/run` vẫn tìm được.
**Before vs After:** Hiện thứ tự, bài dùng chung, allow-list chống lộ `judge_*`, session cùng thread và 7 query cố định đều đúng; sau sửa, reload phải được quan sát nguyên tử và cả hai endpoint thống nhất trạng thái chưa nạp.
**Checklist SEC:** SEC-01 N/A—local-only; SEC-02 N/A—không PII; SEC-03 PASS—không log/leak judge hoặc credential; SEC-04 PASS—Pydantic + ORM parameterized; SEC-05 N/A—không có user/role.
**Checklist PERF/MNT · Example:** PERF-01 PASS—không N+1; PERF-02 PASS—DB sync trong threadpool; PERF-03 PASS—semaphore/body/connect timeout; MNT-01 PASS; MNT-02 PASS—dependency injection; MNT-03 PASS—data-driven. `pytest tests/test_content_api.py`: `1 passed, 8 errors`, cả 8 do sandbox chặn Postgres local (`Operation not permitted`); `git diff --check` sạch.

## Ghi chú của orchestrator (không phải của agent ngoài)

Agent ngoài ghi "1 passed, 8 errors" do sandbox chặn Postgres local — chưa có test pass thật; cần chạy lại ngoài sandbox.
