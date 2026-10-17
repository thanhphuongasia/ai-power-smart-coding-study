# Course cho tài liệu System Design — phase 1 issue #56

Run: `planning/crew/2026-10-17-sd-courses/` · branch `crew/2026-10-17-sd-courses` · worktree base **origin/main 14518a1**.
Kết thúc: PR → merge main (user đã cho phép) → GitHub Actions tự deploy.

## Context

Issue #56: các doc ở tab Design đang nằm phẳng, không biết doc thuộc khoá học nào. Nhận xét đã đăng
(issuecomment-6229966961) chốt phạm vi phase 1:
- **chỉ phía System Design**: bảng `courses`, `sd_docs.course_id`, tool MCP, API học viên nhóm theo course, màn Flutter;
- **không** gắn course cho `themes`, vì bảng đó bị xoá rồi ghi lại mỗi lần duyệt nội dung (`load_content.py:355`).

## Thiết kế

- **Migration 0009:**
  - `courses (id varchar(100) PK slug, title text, skills text[] default '{}', domain text null, status draft|published|archived default draft, position int default 0, created_at, updated_at)`.
  - `sd_docs.course_id varchar(100) NULL FK courses ON DELETE SET NULL` (có index), và `sd_docs.course_position int NULL`.
- **Service `app/sd/courses.py`:**
  - `create_course`, `update_course` (title, skills, domain, position), `set_course_status`, `list_courses(include_archived)` (kèm doc của từng course).
  - `assign_doc(doc_id, course_id|None, position|None)`.
  - Validate slug giống `docs._check_id`; skills ≤20 phần tử, mỗi phần tử ≤40 ký tự; title ≤200 ký tự.
  - `docs.list_docs`/`get_doc` trả thêm `course_id`, `course_position`. `docs.import_markdown` **không chạm** hai cột này nên nhập lại hay sửa doc vẫn giữ course.
- **Quyền xem doc giữ nguyên:** học viên thấy đúng các doc `published` như trước. Course chỉ để nhóm. Course không published thì doc của nó vào nhóm "Khác".
- **API học viên** `GET /api/sd/docs` (tương thích ngược, chỉ THÊM trường):
  - mỗi item thêm `course_id` (`null` nếu không có course, hoặc course không published);
  - thêm mảng `courses: [{id, title, skills, domain}]`: chỉ course published có ít nhất 1 doc published, theo `position`;
  - item sắp theo: course.position → course_position (null cuối) → created_at; doc không thuộc course published xếp cuối.

  App cũ trên TestFlight bỏ qua key mới và vẫn hiện list phẳng.
- **MCP**, 5 tool mới, đều qua `_authorized`:
  - `sd_list_courses(include_archived)`
  - `sd_create_course(id, title, skills, domain, status='draft', position)`
  - `sd_update_course(course_id, changes)`
  - `sd_set_course_status(course_id, status)`: archived = xoá mềm.
  - `sd_assign_doc(doc_id, course_id|null, position)`.

  `sd_list_docs`/`sd_get_doc` hiện thêm `course_id`.
- **Flutter tab Design** (`sd_docs_screen.dart`): nhóm theo course, có header (tên course + skills); nhóm "Khác" ở cuối. Không có course nào thì giữ list phẳng như cũ. Vào doc vẫn 1 chạm từ tab Design.

## Sổ bất biến

```text
INV-01 · Course KHÔNG đổi quyền xem: học viên thấy đúng tập doc published như khi chưa có course; course chỉ nhóm
         phải khớp: backend/app/sd/learner.py:117-138 · backend/app/sd/courses.py · mobile/lib/features/system_design/sd_docs_screen.dart
         vỡ thì thấy gì: chuyển course về draft/archived → doc biến mất khỏi app dù doc vẫn published
INV-02 · Nhập lại / sửa / đổi status doc giữ nguyên course_id, course_position
         phải khớp: backend/app/sd/docs.py (import_markdown, set_status) · backend/app/sd/courses.py (assign_doc)
         vỡ thì thấy gì: Claude sd_edit_doc một doc → doc rơi khỏi course trong app
INV-03 · Tập trạng thái course {draft,published,archived} thống nhất: constraint DB = service = Literal tool MCP
         phải khớp: backend/migrations/versions/0009_*.py · backend/app/tables.py (Course) · backend/app/sd/courses.py · backend/app/mcp_server.py
         vỡ thì thấy gì: sd_set_course_status archived → 500 CheckViolation
INV-04 · Hợp đồng API: item.course_id ∈ courses[].id hoặc null; key Dart khớp key Python; app cũ bỏ qua key mới không vỡ
         phải khớp: backend/app/sd/learner.py (list_docs) · mobile/lib/domain/sd_models.dart · mobile/lib/data/sd_repository.dart
         vỡ thì thấy gì: app báo lỗi tải tab Design, hoặc doc nằm dưới header của course khác
INV-05 · Xoá course = xoá mềm: doc giữ course_id (khôi phục course là doc về đúng nhóm), không xoá cứng ở đâu
         phải khớp: backend/app/sd/courses.py (set_course_status) · backend/app/tables.py (FK ON DELETE SET NULL chỉ để phòng)
         vỡ thì thấy gì: archive rồi khôi phục course → các doc không còn thuộc course
INV-06 · Mọi tool course đi qua _authorized (thu hồi sub là chặn ngay)
         phải khớp: backend/app/mcp_server.py (_sd_doc / wrapper course)
         vỡ thì thấy gì: sub đã revoke vẫn tạo/sửa course được
INV-07 · Thứ tự doc thống nhất: API học viên và sd_list_courses cùng quy tắc position → course_position → created_at
         phải khớp: backend/app/sd/learner.py · backend/app/sd/courses.py
         vỡ thì thấy gì: Claude xếp thứ tự bài trong course, app hiện thứ tự khác
```

## Task (role · tier · model)

| ID | Việc | Role · tier · model | Wave |
|---|---|---|---|
| T-01 | Migration 0009 + model + `sd/courses.py` + `docs.py` trả course + test | orchestrator · L4 · session | 1 |
| T-02 | 5 tool MCP course + cập nhật test tập tool | orchestrator · L4 · session | 2 |
| T-03 | API học viên `GET /api/sd/docs` thêm `courses` + `course_id` + thứ tự + test | crew-impl-standard · T2 · sonnet | 2 |
| T-04 | Flutter: model + repository + màn tab Design nhóm theo course + test | crew-impl-standard · T2 · sonnet | 2 |

T-01 và T-02 có `crew-review` và `crew-review-external` (`EXTERNAL_AGENT_TIMEOUT=600`, prompt hẹp ≤2 file). T-03, T-04 có `crew-review`.
Cuối run có reviewer mối nối. T-04 làm song song T-03 theo **hợp đồng API ghi trong plan này**.

### T-01 · L4 · orchestrator
- Owned: `backend/migrations/versions/0009_courses.py`, `backend/app/tables.py`, `backend/app/sd/courses.py`, `backend/app/sd/docs.py`, `backend/tests/test_sd_courses.py`, `backend/tests/test_sd_schema.py`
- Forbidden: `mobile/**`, `backend/app/load_content.py`, `backend/app/sd/learner.py`
- Acceptance:
  - CRUD course + validate.
  - archive course giữ `course_id` của doc.
  - `assign_doc` vào course archived bị từ chối; gỡ (`null`) được.
  - nhập lại doc giữ `course_id`.
  - migration chạy lên và xuống; head = 0009.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_sd_courses.py tests/test_sd_docs.py tests/test_sd_schema.py`
- Evidence: `git diff --stat -- <owned>`

### T-02 · L4 · orchestrator (sau T-01)
- Owned: `backend/app/mcp_server.py`, `backend/tests/test_mcp_sd_courses.py`, `backend/tests/test_mcp.py`, `backend/tests/test_sd_mcp.py`
- Forbidden: `backend/app/sd/learner.py`, `mobile/**`
- Acceptance:
  - 5 tool chạy qua HTTP thật.
  - sub chưa cấp → isError.
  - Literal status đúng.
  - `sd_list_docs` có `course_id`.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_mcp_sd_courses.py tests/test_mcp.py tests/test_sd_mcp.py`
- Evidence: `git diff --stat -- <owned>`

### T-03 · L3 · crew-impl-standard (sau T-01)
- Owned: `backend/app/sd/learner.py`, `backend/tests/test_sd_learner_courses.py`
- Forbidden: `backend/app/sd/courses.py`, `backend/app/sd/docs.py`, `backend/app/mcp_server.py`, `mobile/**`
- Acceptance:
  - đúng hợp đồng API ở trên.
  - tập doc học viên thấy không đổi khi course draft/archived (INV-01).
  - thứ tự đúng.
  - test cũ `test_sd_learner.py` xanh, không sửa assert.
  - không N+1 (một truy vấn courses).
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_sd_learner_courses.py tests/test_sd_learner.py`
- Evidence: `git diff --stat -- <owned>`

### T-04 · L3 · crew-impl-standard (song song T-03, theo hợp đồng)
- Owned: `mobile/lib/domain/sd_models.dart`, `mobile/lib/data/sd_repository.dart`, `mobile/lib/features/system_design/sd_docs_screen.dart`, `mobile/test/sd_repository_test.dart`, `mobile/test/sd_docs_screen_test.dart`
- Forbidden: `backend/**`, file Flutter khác
- Acceptance:
  - parse `courses`/`course_id`; thiếu key (server cũ) vẫn chạy.
  - màn nhóm theo course, "Khác" cuối; không có course → list phẳng như cũ.
  - chạm doc vẫn mở reader.
  - `flutter analyze` sạch trên file owned.
- Validation: `cd mobile && flutter test test/sd_repository_test.dart test/sd_docs_screen_test.dart && flutter analyze lib/domain/sd_models.dart lib/data/sd_repository.dart lib/features/system_design/sd_docs_screen.dart`
- Evidence: `git diff --stat -- <owned>`

## Verification (e2e — orchestrator tự chạy)

1. Full pytest (tuần tự); `flutter test` toàn bộ.
2. Uvicorn thật + JWKS giả (DB e2e):
   - Claude tạo course draft, gán 2 doc → API học viên: doc vẫn hiện nhưng `course_id=null` (INV-01).
   - publish course → `courses` có course, item mang `course_id`, thứ tự theo `course_position` (INV-07).
   - `sd_edit_doc` một doc → vẫn trong course (INV-02).
   - archive course → doc về "Khác", vẫn thấy; khôi phục → doc về course (INV-05).
   - revoke sub → tool course bị từ chối (INV-06).
3. Sau merge + deploy:
   - curl `/api/sd/docs` thấy `courses` (rỗng tới khi có course).
   - web: mở tab Design vẫn tải được (app cũ/mới).

Backlog đã biết: course cho `themes` (bảng nối không FK); API admin cho course; màn quản lý course trong app.
