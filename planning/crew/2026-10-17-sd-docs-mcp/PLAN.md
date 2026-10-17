# MCP tool quản lý tài liệu System Design — import, xem, sửa, xoá mềm, publish

Run: `planning/crew/2026-10-17-sd-docs-mcp/` · branch `crew/2026-10-17-sd-docs-mcp` · worktree base **origin/main 56baa15**
(thư mục gốc đang ở branch `ci/deploy-vps-on-merge` của phiên khác, có commit chưa push).
Kết thúc: PR → merge main (user đã cho phép) → GitHub Actions tự deploy (`.github/workflows/deploy.yml`) → backfill markdown gốc trên VPS.

## Context

Claude trên claude.ai đã kết nối được `/mcp`. Tab System Design hiện chỉ nạp được tài liệu qua `POST /api/admin/sd/docs`.
MCP chỉ có 3 tool chấm bài (`sd_list_attempts`, `sd_get_attempt`, `sd_submit_feedback`). User muốn Claude import, xem, sửa
và xoá tài liệu SD.

Hai quyết định user đã chọn:
- **Xoá = xoá mềm** (`status='archived'`): ẩn với học viên, giữ nguyên bài nộp và tiến độ, khôi phục được.
- **Claude được publish/unpublish và sửa doc đang published.** Lớp chặn là "Needs approval" của claude.ai.

Hai thứ còn thiếu:
- Bảng `sd_docs` **không lưu markdown gốc** nên không sửa lại được. Thêm cột `source_md`, rồi backfill cho các doc đang có.
- `/mcp` chặn body ở 64KB, trong khi doc tối đa 1MB.

## Thiết kế

- **Migration 0008:** thêm `sd_docs.source_md TEXT NULL`. Đổi `ck_sd_docs_status` thành `IN ('draft','published','archived')`.
- **`app/sd/docs.py` (mới), MỘT đường nghiệp vụ cho cả API admin lẫn MCP.** Tách `_import` ra khỏi `sd/admin.py`, giữ nguyên
  hành vi gồm: parse trước khi khoá, advisory lock theo doc, xoá rồi ghi lại section/task, không chạm `sd_progress`/`sd_attempts`,
  tóm tắt `cards_added/removed`. Thêm:
  - `import_markdown(session, markdown, *, doc_id, status, actor, mode, dry_run)` với `mode`:
    - `create`: id đã tồn tại, kể cả archived → lỗi.
    - `replace`: id phải tồn tại.
    - `upsert`: hành vi cũ của API.

    Luôn lưu `source_md`. `dry_run` parse xong, tính tóm tắt so với bản hiện có, không ghi gì.
  - `list_docs(session, include_archived=False)`, `get_doc(session, doc_id)` trả meta, mục lục chapter → section (số card),
    task (tên, đề, gợi ý, số ý rubric) và `markdown` (`null` nếu doc nhập trước migration).
  - `apply_edits(source, edits)` là hàm thuần: mỗi `{old_text, new_text}` phải khớp **đúng 1 lần**. Có trần: ≤50 edit, mỗi chuỗi
    ≤20k ký tự. Đếm bằng `str.count` (tuyến tính) theo rule `hostile-input-budget`.
  - `set_status(session, doc_id, status)`.
- **`sd/admin.py`:** route gọi service. `StatusIn` nhận thêm `archived`. `GET /docs?include_archived=`. Hợp đồng HTTP cũ giữ nguyên.
- **MCP (`mcp_server.py`), 8 tool, đều qua `_authorized`:**
  - Đọc: `sd_list_docs(include_archived)`, `sd_get_doc(doc_id)`.
  - Ghi:
    - `sd_create_doc(markdown, doc_id?, status='draft', dry_run)`
    - `sd_replace_doc(doc_id, markdown, dry_run)`
    - `sd_edit_doc(doc_id, edits, dry_run)` (cần `source_md`)
    - `sd_set_status(doc_id, status)`
    - `sd_delete_doc(doc_id)` = archive. Báo rõ đây là xoá mềm, khôi phục bằng `sd_set_status`.
  - Lỗi nghiệp vụ trả `isError` kèm danh sách lỗi của parser.
- **Body `/mcp` lên 2MB:** sửa `_body_limit` trong `main.py`, `max_request_body_size` của SDK, và `client_max_body_size` của nginx.
  Cổng JWT chạy trước khi đọc body nên khách chưa xác thực không bắt server đọc được 2MB.
- **Hàng chờ chấm** (`sd/attempts.review_queue`): mặc định bỏ bài nộp của doc archived. `sd_get_attempt` vẫn đọc được.
- **Backfill:** CLI `python -m app.sd.import_file <path> --id <id> --mode replace` (giữ status). Sau deploy, scp 6 file .md lên VPS
  (`airline-reservation.md` trên main, 5 file Python từ commit local `204c8bf`, không commit chúng vào run này) rồi chạy CLI.
  Card id là hash nội dung nên tiến độ học viên giữ nguyên.

Concern:
- Sửa doc published là học viên thấy ngay (doc SD chỉ có một bản). User đã chấp nhận.
- Đổi tên section làm mất tiến độ đọc của section đó. Đây là hành vi sẵn có của parser; tool sẽ báo trong tóm tắt (`cards_removed`).

## Sổ bất biến

```text
INV-01 · Doc archived vô hình với học viên ở mọi đường: list, get, progress, nộp bài, xem bài đã nộp
         phải khớp: backend/app/sd/learner.py:41-45,119 · backend/app/sd/attempts.py:94,151 · backend/app/sd/docs.py (set_status)
         vỡ thì thấy gì: xoá doc qua Claude mà app học viên vẫn hiện doc, hoặc vẫn nộp bài được
INV-02 · Một đường nhập duy nhất: API admin, MCP và CLI đều qua docs.import_markdown → luôn lưu source_md
         phải khớp: backend/app/sd/docs.py · backend/app/sd/admin.py · backend/app/mcp_server.py · backend/app/sd/import_file.py
         vỡ thì thấy gì: doc nhập qua API admin thì sd_edit_doc báo "không có markdown gốc"
INV-03 · Nhập lại/sửa không xoá sd_progress / sd_attempts; card không đổi giữ trạng thái đã đọc
         phải khớp: backend/app/sd/docs.py (import) · backend/app/sd/parser.py (card id = hash) · backend/app/tables.py:236-239
         vỡ thì thấy gì: Claude sửa một lỗi chính tả, học viên mất toàn bộ tiến độ đọc doc đó
INV-04 · Tập trạng thái thống nhất {draft, published, archived}: constraint DB = Literal API admin = tham số tool MCP = bộ lọc học viên
         phải khớp: backend/migrations/versions/0008_*.py · backend/app/tables.py (SdDoc) · backend/app/sd/admin.py (StatusIn) · backend/app/mcp_server.py (sd_set_status)
         vỡ thì thấy gì: sd_delete_doc trả lỗi 500 CheckViolation, hoặc API admin 422 khi đặt archived
INV-05 · Tool tài liệu SD đi qua cùng cổng MCP: JWT trước khi đọc body + authorize_sub mỗi lần gọi; body 2MB chỉ mở cho /mcp
         phải khớp: backend/app/mcp_server.py (McpGate, _authorized) · backend/app/main.py (_body_limit) · deploy/nginx/smart-coding-study.conf
         vỡ thì thấy gì: request chưa xác thực 2MB được đọc hết; sub bị thu hồi vẫn import được doc
INV-06 · Hàng chờ chấm mặc định không chứa bài nộp của doc archived; bài nộp vẫn còn trong DB
         phải khớp: backend/app/sd/attempts.py (review_queue) · backend/app/sd/docs.py (archive không xoá attempts)
         vỡ thì thấy gì: Claude chấm bài mà học viên không còn xem được; hoặc xoá mềm làm mất bài nộp
INV-07 · create không ghi đè doc có sẵn (kể cả archived); replace/edit chỉ trên doc có sẵn
         phải khớp: backend/app/sd/docs.py (mode) · backend/app/mcp_server.py (sd_create_doc/sd_replace_doc)
         vỡ thì thấy gì: tạo doc mới trùng slug với doc đã xoá → âm thầm thay nội dung doc cũ
```

## Task (role · tier · model)

| ID | Việc | Role · tier · model | Wave |
|---|---|---|---|
| T-01 | Migration 0008 + `sd/docs.py` service + `sd/admin.py` dùng service + test | orchestrator · L4 · session | 1 |
| T-02 | 8 tool MCP + body 2MB + test | orchestrator · L4 · session | 2 |
| T-03 | Hàng chờ chấm bỏ doc archived + test học viên với doc archived | crew-impl-standard · T2 · sonnet | 2 |
| T-04 | CLI `import_file` + nginx body `/mcp` + README | crew-impl-light · T1 · haiku | 2 |

T-01 và T-02 (L4) có `crew-review` và `crew-review-external` (`EXTERNAL_AGENT_TIMEOUT=360`). T-03 và T-04 có `crew-review`.
Cuối run có reviewer mối nối. Checkpoint: full pytest sau wave 2.

### T-01 · L4 · orchestrator
- Owned: `backend/migrations/versions/0008_sd_source_archive.py`, `backend/app/tables.py`, `backend/app/sd/docs.py`, `backend/app/sd/admin.py`, `backend/tests/test_sd_docs.py`
- Forbidden: `mobile/**`, `backend/app/sd/parser.py`, `backend/app/sd/learner.py`, `backend/app/mcp_server.py`
- Acceptance:
  - test cũ của API admin SD xanh, không sửa assert.
  - `source_md` được lưu qua mọi mode.
  - create trùng id (kể cả archived) → lỗi; replace với id lạ → lỗi.
  - dry_run không đổi DB.
  - nhập lại không đụng `sd_progress`/`sd_attempts`.
  - `apply_edits`: 0 lần khớp hoặc >1 lần khớp → lỗi nêu rõ; có test thời gian đầu vào xấu nhất <1 giây.
  - migration chạy lên và xuống được.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_sd_docs.py tests/test_sd_admin.py` (tên file test admin SD có sẵn kiểm ở P2)
- Evidence: `git diff --stat -- <owned>`
- Thứ tự: migration + `import_markdown` (giữ hành vi cũ) trước, rồi edit/list/get.

### T-02 · L4 · orchestrator (sau T-01)
- Owned: `backend/app/mcp_server.py`, `backend/app/main.py`, `backend/tests/test_mcp_sd_docs.py`
- Forbidden: `backend/app/sd/parser.py`, `backend/app/mcp_auth.py`, `mobile/**`
- Acceptance:
  - không token → 401.
  - sub chưa cấp → isError.
  - create draft → học viên không thấy; publish → học viên thấy; edit giữ tiến độ; delete → học viên 404 và bài nộp còn; khôi phục được.
  - body 1.5MB có token qua được, không token → 401 (không đọc body).
  - lỗi parser trả isError.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_mcp_sd_docs.py tests/test_mcp.py`
- Evidence: `git diff --stat -- <owned>`

### T-03 · L3 · crew-impl-standard (sau T-01)
- Owned: `backend/app/sd/attempts.py`, `backend/tests/test_sd_archive.py`
- Forbidden: `backend/app/sd/docs.py`, `backend/app/sd/learner.py`, `backend/app/mcp_server.py`, `mobile/**`
- Acceptance:
  - `review_queue` mặc định bỏ bài nộp của doc archived, có tham số để xem cả bài đó.
  - test học viên: doc archived không có trong list; get, progress, nộp bài, xem bài đều 404; bài nộp còn trong DB.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_sd_archive.py`
- Evidence: `git diff --stat -- <owned>`

### T-04 · L1 · crew-impl-light (sau T-01)
- Owned: `backend/app/sd/import_file.py`, `backend/tests/test_sd_import_file.py`, `deploy/nginx/smart-coding-study.conf`, `backend/README.md`
- Forbidden: `backend/app/sd/docs.py`, `backend/app/mcp_server.py`, `mobile/**`
- Acceptance:
  - CLI gọi `docs.import_markdown` (`--mode create|replace|upsert`, `--id`, `--status`, `--dry-run`); in tóm tắt; lỗi → exit 1.
  - nginx `/mcp` đặt `client_max_body_size 2100k`.
  - README có mục tool SD + backfill.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_sd_import_file.py && bash -n ../deploy/deploy.sh`
- Evidence: `git diff --stat -- <owned>`

## Verification (e2e — orchestrator tự chạy)

1. Full suite `.venv/bin/python -m pytest -q` (chạy tuần tự, DB test dùng chung).
2. Uvicorn thật + JWKS giả (bộ e2e của run trước), DB e2e riêng. Đi qua mối nối:
   - nhập doc qua **API admin** → `sd_get_doc` qua MCP trả `markdown` (INV-02).
   - `sd_create_doc` draft → API học viên không thấy → `sd_set_status published` → học viên thấy, đọc 2 card (progress)
     → `sd_edit_doc` sửa một card khác → progress 2 card cũ còn (INV-03).
   - học viên nộp bài → `sd_delete_doc` → học viên list/get/nộp đều 404, `sd_attempts` còn, `sd_list_attempts` không chứa (INV-01, INV-06)
     → `sd_set_status published` khôi phục, tiến độ còn.
   - `sd_create_doc` trùng id doc archived → lỗi (INV-07).
   - body 1.5MB không token → 401 (INV-05).
3. Sau merge, CI deploy xong:
   - curl `/mcp` 401.
   - backfill 6 doc bằng CLI `--mode replace`, so số card trước/sau phải bằng nhau.
   - user nhờ Claude `sd_list_docs`, rồi `sd_get_doc` một bài Python.

Backlog đã biết: màn admin SD trong app Flutter; xoá cứng (purge) doc archived.
