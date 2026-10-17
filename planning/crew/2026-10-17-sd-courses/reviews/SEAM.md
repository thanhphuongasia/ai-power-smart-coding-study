# SEAM review — 2026-10-17-sd-courses

INV-01: CÒN ĐÚNG — backend/app/sd/learner.py:121,124,129-132,152 · mobile/lib/features/system_design/sd_docs_screen.dart:112-145 — Tập doc lấy từ `status == "published"` không join course; course draft/archived chỉ làm `course_id=null` nên doc rơi vào "Khác", không biến mất.
INV-02: CÒN ĐÚNG — backend/app/sd/docs.py:136-153 · backend/app/sd/courses.py:194-196 — import_markdown chỉ set title/context/source_md/status, SdDoc(...) mới không set course; grep ngoài courses.py chỉ thấy docs.py:242-281 (đọc), learner, mcp (tham số), tables; admin.py:55,80 và import_file.py chỉ gọi import_markdown/set_status; `assign_doc` là đường ghi duy nhất.
INV-03: CÒN ĐÚNG — backend/migrations/versions/0009_courses.py:34 · backend/app/tables.py:245 · backend/app/sd/courses.py:158 (STATUSES từ docs.py:32) · backend/app/mcp_server.py:450 — Cả bốn đều {draft,published,archived}; create tách riêng draft|published (courses.py:24, mcp_server.py:417) khớp nhau.
INV-04: CÒN ĐÚNG — backend/app/sd/learner.py:152,157-160 · mobile/lib/domain/sd_models.dart:34-48,87-89 · mobile/lib/data/sd_repository.dart:82-95 — Key Python `course_id`, `courses[].id/title/skills/domain` đúng key Dart đọc; item.course_id luôn thuộc `courses` hoặc null; Dart parse lỏng, thiếu key (server cũ) vẫn chạy; không tra ra course thì course=null → "Khác".
INV-05: CÒN ĐÚNG — backend/app/sd/courses.py:157-170 · backend/app/tables.py:274-276 — set_course_status chỉ đổi status, không đụng sd_docs; không có đường xoá cứng course trong app/; assign vào course archived bị từ chối (courses.py:187-189).
INV-06: CÒN ĐÚNG — backend/app/mcp_server.py:407-465 · backend/app/mcp_server.py:327-330 — Cả 5 tool course đi qua `_sd_doc`, wrapper gọi `_authorized` mỗi lần.
INV-07: CÒN ĐÚNG — backend/app/sd/courses.py:33,91,106 · backend/app/sd/learner.py:29,121,129,133 · mobile/lib/features/system_design/sd_docs_screen.dart:112-136 — Cả hai dùng chung `DOC_ORDER` (course_position nulls last → created_at → id) và course theo (position, id); app giữ thứ tự server (Map giữ thứ tự chèn) nên không lệch.

## Mối nối khác

- Minor — course cùng `position` có thể lệch thứ tự: backend/app/sd/courses.py:106 sắp `Course.id` theo collation Postgres, backend/app/sd/learner.py:129,133 sắp `course_id` theo codepoint Python. Id có `-` lẫn chữ/số + trùng `position` (mặc định 0) thì `sd_list_courses` có thể khác app. Giảm: đặt position khác nhau cho mỗi course.
- Minor — backend/app/sd/docs.py:242-261 `course_id` thô (kể cả course draft/archived) khác nghĩa với `course_id` của API học viên (null nếu chưa published). Hai API riêng nên không vỡ, chỉ cần nhớ.
- Ghi nhận — backend/app/sd/courses.py:196 gỡ doc khỏi course xoá luôn `course_position`; gán lại phải đặt lại vị trí (đã có trong backlog).

## Không kiểm được
- Không chạy lại test/e2e (orchestrator báo 10/10 + flutter xanh); verdict dựa trên đọc code và grep toàn backend/app.
