# Review mối nối (một reviewer, thấy cả hai đầu của từng bất biến)

Reviewer: crew-review (T2), phạm vi = toàn bộ sổ bất biến + contract, không nhận danh sách file. Kịch bản chạy trên bản sao ngoài git, DB riêng.
Verdict tổng: **PASS với Minor** (lần đầu CẦN SỬA vì bất biến thứ nhất vỡ do chuẩn hoá Unicode; đã sửa ở commit c5783fc và reviewer kiểm lại: 13 test kịch bản mối nối xanh).

INV-01: CÒN ĐÚNG — backend/app/sd/parser.py:373, backend/app/sd/parser.py:73, backend/app/sd/admin.py:88-91, backend/app/sd/learner.py:47-69
INV-02: CÒN ĐÚNG — backend/app/sd/learner.py:72-92, backend/app/sd/attempts.py:53-75, mobile/lib/domain/sd_models.dart:130-171
INV-03: CÒN ĐÚNG — backend/app/sd/attempts.py:53-75, backend/app/mcp_server.py:256-268, mobile/lib/features/system_design/task_screen.dart:620
INV-04: CÒN ĐÚNG — backend/app/sd/learner.py:47-92, mobile/lib/features/system_design/sd_path_screen.dart:31-35, mobile/lib/features/system_design/reader_screen.dart:366
INV-05: CÒN ĐÚNG — mobile/lib/app/router.dart:30-72, mobile/lib/features/shell/app_shell.dart:37-76, mobile/lib/features/shell/app_drawer.dart:80-87
INV-06: CÒN ĐÚNG — backend/app/sd/learner.py:104, backend/app/sd/attempts.py:154-155, backend/app/mcp_server.py:77, backend/app/mcp_auth.py:205-218

## Chi tiết đã kiểm (tóm tắt)

- Lần đầu: nhập lại cùng nội dung ở dạng NFD (copy từ macOS) đổi 22/26 card id, học viên còn 1/9 section done và Phase 2 khoá lại; cả file NFD bị 422 vì nhãn `Đề:`. Sau sửa: cards_added=0, cards_removed=0, 9/9 done, Phase 2 mở; slug Дизайн/한국어/ばが ổn định giữa NFC và NFD.
- Không response /api/sd/* nào chứa rubric/từ khoá/auto_result/verdicts; 422 không echo input; OpenAPI không nhắc rubric; học viên gọi route admin bị 403.
- API trả đúng một bản cho mỗi lần thử, reviewed thắng auto; đổi rubric/nhập lại không làm lệch; chấm lại không replace bị từ chối.
- Client chỉ dùng done/unlocked của server; mở khoá cục bộ chỉ qua next_section_id của PUT; chỗ client suy ra đã nêu bên dưới.
- Mọi query đọc sd_progress/sd_attempts ở route học viên lọc theo user.id; MCP qua authorize_sub mỗi tool call.

## Bất biến chưa khai (Minor, đã ghi vào DEVIATIONS và Backlog)

- BK-1 task.id là slug tên task (đổi tên task mất số lần thử và chuỗi mở khoá).
- BK-2 nhập lại làm Phase 1 mất done thì Phase 2 khoá lại; app báo "Task này chưa mở" sai lý do và ẩn lịch sử dù server vẫn cho GET lịch sử.
- BK-3 reader tăng thanh tiến độ cục bộ sau 409 dù server không ghi.
- BK-4 node "Bối cảnh" không bao giờ done nếu tài liệu không có task.
- Oracle ✓/✗ từng ý rubric cho phép dò từ khoá (bisect, tối đa 20 lần/ngày/task): hệ quả của thiết kế feedback.

## Không xác minh được

Chạy trên thiết bị thật; đua tranh thật giữa nhập lại và PUT progress (hạ tầng test dùng một connection; riêng nhập đồng thời và chấm đồng thời đã có test nhiều luồng).

## Bảng 11 mã NFR

SEC-01: N/A — không thêm kênh truyền mới, /api/sd và MCP chung app FastAPI hiện có (backend/app/main.py:63-71)
SEC-02: PASS — bài làm là nội dung học, không PII/secret (backend/app/tables.py:304-330)
SEC-03: PASS — 422 không echo input (backend/app/main.py:99-104), không secret trong log/URL
SEC-04: PASS — pydantic ở boundary, _bad_text, trần parser (backend/app/sd/learner.py:35-37, backend/app/sd/attempts.py:37-50, backend/app/sd/parser.py:26-43)
SEC-05: PASS — require_admin cấp router, route học viên lọc user.id, MCP authorize_sub mỗi lần (backend/app/sd/admin.py:35, backend/app/sd/learner.py:104, backend/app/mcp_server.py:77)
PERF-01: PASS — _load gom theo lô, không N+1 (backend/app/sd/learner.py:95-114)
PERF-02: PASS — import và tool MCP chạy qua run_in_threadpool (backend/app/sd/admin.py:124, backend/app/mcp_server.py:283)
PERF-03: PASS — trần attempts/list/md/timeout/backoff (backend/app/sd/attempts.py:33-34, mobile/lib/data/sd_repository.dart:37, mobile/lib/features/system_design/reader_screen.dart:27-33)
MNT-01: PASS — biểu thức "phase 2 mở" lặp 4 chỗ nhỏ, chấp nhận (backend/app/sd/learner.py:125, backend/app/sd/attempts.py:101)
MNT-02: PASS — Evaluator là Protocol cắm qua dependency, Flutter qua sdRepositoryProvider (backend/app/sd/evaluator.py:23-39)
MNT-03: PASS — bộ chấm mới chỉ implement Evaluator, không sửa if/else (backend/app/sd/evaluator.py:23)
