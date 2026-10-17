# Tool MCP publish riêng: hàng chờ bài code + tài liệu System Design

Run: `planning/crew/2026-10-17-mcp-publish-tool/` · branch `crew/2026-10-17-mcp-publish-tool` từ **origin/main 52da8c8**
(user chọn: `dev` đang chậm hơn `main` 26 commit, nên PR này kéo luôn 26 commit đó vào dev).
Kết thúc: `gh pr create --base dev`, **KHÔNG merge** (memory `pr-to-dev-no-merge`, rule `.claude/rules/orchestration/git-workflow.md` trên dev).

## Context

Bài code ghi qua MCP vào hàng chờ duyệt (`review.submit`), và chỉ admin duyệt được trong app. User muốn Claude publish được qua MCP, nhưng
bằng **tool publish riêng** chứ không tự động: Claude gửi bài trước, rồi publish khi người dùng bảo. Lớp chặn là nút "Needs approval" của claude.ai.
Tài liệu System Design (user chọn cách gọn): thêm `sd_publish_doc`/`sd_unpublish_doc` cho rõ tên, cùng nhóm "publish".
`sd_create_doc` vẫn mặc định draft; sửa doc đang published vẫn lên ngay (doc SD không có bản nháp riêng, để backlog).

## Thiết kế

Thêm 6 tool (4 cho hàng chờ bài code, 2 cho tài liệu SD). Tất cả đi qua `_authorized` và dùng nguyên hàm có sẵn ở `backend/app/review.py`, giống đường của API admin
(`backend/app/admin_api.py:149-174`):

| Tool | Làm gì | Hàm dùng lại |
|---|---|---|
| `list_pending_changes()` (read) | Mục đang chờ: id, kind, item_id, action, author, thời điểm, tên mục (từ after/before) | `review.pending_rows`, `review.change_json` |
| `get_pending_change(change_id)` (read) | Đủ before/after của một mục để xem diff | `review.change_json` |
| `publish_changes(change_ids)` (write) | Duyệt từng id theo thứ tự truyền vào. Mỗi id chạy trong savepoint riêng, id lỗi không chặn id khác | `review.approve(…, reviewer="mcp:<sub>")` |
| `reject_changes(change_ids)` (write) | Bỏ từng mục | `review.reject` |
| `sd_publish_doc(doc_id)` (write) | Doc SD → published (học viên thấy) | `sd/docs.set_status` (wrapper `_sd_doc`) |
| `sd_unpublish_doc(doc_id)` (write) | Doc SD → draft (ẩn khỏi học viên, không xoá) | `sd/docs.set_status` |

Chi tiết:
- **Kết quả theo từng id:** `{id, status: approved|rejected|error, also: [...], error?}`. Gặp `NotPending` (đã duyệt kèm mục khác hoặc đã xử lý) thì báo `skipped`. Lỗi nghiệp vụ (`DependencyMissing` "cần duyệt X trước", `ItemConflict`, `InvalidResult`) giữ nguyên thông điệp để Claude tự sửa thứ tự.
- **Trần:** tối đa 50 id mỗi lần gọi; id phải là số nguyên dương.
- INSTRUCTIONS và message của các tool ghi bài code nói rõ: "đã vào hàng chờ; publish bằng `publish_changes` (hoặc admin duyệt trong app)".
- Schema tool thêm mới, nên sau deploy phải **Disconnect → Connect** connector để claude.ai thấy tool. Ghi trong PR.

## Sổ bất biến

```text
INV-01 · Publish qua MCP đi đúng đường admin duyệt: review.approve (khoá ghi → kiểm live → validation_errors → load_content)
         phải khớp: backend/app/review.py:487-515 · backend/app/admin_api.py:169 · backend/app/mcp_server.py (publish_changes)
         vỡ thì thấy gì: bài sai luật lên production, hoặc publish qua MCP và qua app cho kết quả khác nhau
INV-02 · Mỗi mục publish/reject để lại dấu vết decided_by=mcp:<sub>, decided_at
         phải khớp: backend/app/review.py:510-512,521 · backend/app/mcp_server.py
         vỡ thì thấy gì: không biết mục nào do Claude duyệt, mục nào do admin duyệt
INV-03 · Một id lỗi không làm hỏng id khác trong cùng lần gọi; không id nào nửa vời (savepoint mỗi id)
         phải khớp: backend/app/mcp_server.py (publish_changes)
         vỡ thì thấy gì: publish [A, B], B lỗi dependency → A cũng bị huỷ, hoặc live bị ghi một nửa
INV-04 · Mọi tool hàng chờ đi qua _authorized (thu hồi sub là chặn ngay)
         phải khớp: backend/app/mcp_server.py
         vỡ thì thấy gì: sub đã revoke vẫn publish được
INV-06 · sd_publish_doc/sd_unpublish_doc = đúng sd_set_status published/draft (cùng service, cùng _authorized); học viên thấy/không thấy theo đó
         phải khớp: backend/app/sd/docs.py (set_status) · backend/app/sd/learner.py:41-45 · backend/app/mcp_server.py
         vỡ thì thấy gì: Claude báo đã publish mà tab Design không hiện doc
INV-05 · Đọc nội dung qua MCP (draft = live ⊕ pending) vẫn đúng sau khi publish/reject: lần ghi kế tiếp không 409 oan
         phải khớp: backend/app/review.py:390-396 · backend/app/mcp_server.py (_read/_write)
         vỡ thì thấy gì: publish xong, Claude sửa tiếp bài đó thì báo "người khác vừa sửa"
```

## Task (role · tier · model)

| ID | Việc | Role · tier · model |
|---|---|---|
| T-01 | 4 tool hàng chờ + 2 tool publish SD + INSTRUCTIONS + test + README | orchestrator · L4 · session |

Review: `crew-review` + `crew-review-external` (`EXTERNAL_AGENT_TIMEOUT=540`, prompt hẹp 1 file) + reviewer mối nối.

### T-01 · L4 · orchestrator
- Owned: `backend/app/mcp_server.py`, `backend/tests/test_mcp_publish.py`, `backend/tests/test_mcp.py`, `backend/tests/test_sd_mcp.py`, `backend/README.md`
- Forbidden: `backend/app/review.py`, `backend/app/load_content.py`, `mobile/**`
- Acceptance:
  - MCP create_lesson → `list_pending_changes` thấy mục → `publish_changes([id])` → bài có trong `GET /content`, dòng `content_changes` approved bởi `mcp:<sub>`.
  - publish bài trước file cha đang chờ → error "cần duyệt … trước", bài vẫn pending; publish theo đúng thứ tự thì cả hai lên.
  - id không tồn tại hoặc đã duyệt → skipped, không lỗi cả lô.
  - reject → mục rejected, không lên live.
  - publish project kéo module đầu đi cùng (`also`).
  - sau khi publish, ghi tiếp không 409.
  - sub chưa cấp → isError; quá 50 id → isError.
  - `sd_publish_doc` → doc hiện trong `/api/sd/docs`; `sd_unpublish_doc` → ẩn, tiến độ còn.
  - test hàng chờ cũ xanh; test tập tool (`test_mcp.py`, `test_sd_mcp.py`) cập nhật đúng tên mới.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_mcp_publish.py tests/test_mcp.py tests/test_sd_mcp.py tests/test_review.py`
- Evidence: `git diff --stat -- <owned>`

## Verification (e2e, orchestrator tự chạy)

1. Full pytest (chạy tuần tự).
2. Uvicorn thật + JWKS giả:
   - MCP create_lesson → `GET /content` chưa có bài.
   - `list_pending_changes` → `publish_changes` → `/content` có bài (INV-01).
   - Admin API `GET /api/admin/changes` thấy mục đã approved bởi `mcp:<sub>` (INV-02).
   - Publish lô gồm 1 id hỏng: id còn lại vẫn lên (INV-03).
   - Revoke → bị chặn (INV-04).
3. PR vào dev, không merge. Sau khi user merge và deploy: Disconnect → Connect connector.
