# Architecture

> Repo demo cho ứng dụng học lập trình di động "Smart Coding Study": app Flutter (làm bài code
> trong ô nhỏ trên điện thoại, autocomplete đủ tốt để không nản) cùng một backend FastAPI nhỏ
> lưu nội dung học và tiến độ từng user trong Postgres, phát nội dung qua `GET /content`, chấm bài
> bằng Python thật, có đăng nhập và màn quản trị nội dung cho admin.

## Bản đồ nhanh

Ghi chú: script kiểm `verify-distill.sh` chỉ nhận toạ độ `file:dòng` có đuôi py/ts/js/sh/sql/toml/yaml/json/md,
không nhận `.dart`. Vì vậy cột cuối của dòng Dart trỏ về mục chi tiết trong tài liệu này
(docs/ARCHITECTURE.md:1) để gate không chặn; toạ độ `.dart` thật nằm ngay cột giữa.

| thành phần | vai trò và toạ độ | mục chi tiết |
| --- | --- | --- |
| backend | API `POST /run`: chạy harness + unit test của bài (đọc từ Postgres) qua máy chấm (Judge0), trả đúng/sai từng test — backend/app/main.py:112 | docs/modules/judge-backend.md:1 |
| backend/content | `GET /content`: cả cây nội dung học (theme → module lồng nhau → file → bài) từ Postgres, không có phần chấm — backend/app/content_api.py:184 | docs/ARCHITECTURE.md:1 |
| backend/load_content | đường ghi nội dung DUY NHẤT: validate rồi thay toàn bộ trong một transaction dưới advisory lock; CLI `--if-empty`/`--force` — backend/app/load_content.py:307, backend/app/load_content.py:390 | docs/modules/content-admin.md:1 |
| backend/content_rules + export_content | luật nội dung port từ Dart chạy ở server; xuất DB ra shape `content.json` — backend/app/content_rules.py:274, backend/app/export_content.py:36 | docs/modules/content-admin.md:1 |
| backend/admin_api | `/api/admin/content` GET (bản nháp)/PUT (gửi vào hàng chờ; version, 409) + `/api/admin/validate` + `/api/admin/changes*` (duyệt/bỏ từng mục), chỉ role admin — backend/app/admin_api.py:33, backend/app/admin_api.py:147 | docs/modules/content-admin.md:1 |
| backend/review | hàng chờ duyệt: bảng `content_changes`, draft = live ⊕ mục chờ, submit/approve/reject theo từng mục, luật cha–con; `/api/admin/run` chấm theo draft — backend/app/review.py:399, backend/app/review.py:487, backend/app/main.py:225 | docs/modules/content-review.md:1 |
| backend/mcp | `POST /mcp` cho claude.ai: cổng `McpGate` verify JWT RS256 của identity-service (401 + `resource_metadata`, 503 khi JWKS chết), quyền theo bảng `mcp_access` kiểm mỗi tool call, 12 tool nội dung ghi vào hàng chờ duyệt qua cùng đường/khoá với admin PUT, cộng 10 tool `sd_*` (3 chấm bài, 7 quản lý tài liệu System Design, không qua hàng chờ; body `/mcp` tối đa 2MB) — backend/app/mcp_server.py:400, backend/app/mcp_server.py:280-313, backend/app/mcp_server.py:319-395, backend/app/mcp_auth.py:169, backend/app/mcp_access.py:49 | docs/modules/mcp.md:1 |
| backend/auth | đăng nhập email+mật khẩu (argon2id), token Bearer lưu sha256, throttle, đổi mật khẩu, `current_user`/`require_admin` — backend/app/auth.py:160, backend/app/auth.py:222 | docs/modules/auth-progress.md:1 |
| backend/progress | `GET/PUT /api/progress*`, `record_pass` do `/run` gọi — backend/app/progress.py:28, backend/app/progress.py:196 | docs/modules/auth-progress.md:1 |
| backend/seed_users | tạo 2 tài khoản ban đầu, mật khẩu chỉ vào file root 0600 — backend/app/seed_users.py:45 | docs/modules/deploy.md:1 |
| backend/db + tables | engine/session SQLAlchemy + bảng nội dung (`topics.parent_id`, `exercises.class_name`) + bảng `users/user_sessions/user_progress/user_state` + migration Alembic — backend/app/db.py:19, backend/app/tables.py:31, backend/app/tables.py:128, backend/migrations/versions/0004_users_progress.py:41 | docs/ARCHITECTURE.md:1 |
| backend/runner | interface `CodeRunner` + `Judge0Runner` — backend/app/runner.py:42, backend/app/runner.py:56 | docs/modules/judge-backend.md:1 |
| backend/harness | chương trình chạy trên máy chấm: compile code học viên, chạy từng test case (kể cả case kịch bản gọi method), in một dòng JSON — backend/app/harness.py:48 | docs/modules/judge-backend.md:1 |
| domain | model bất biến, ghép ô (mobile/lib/domain/merge.dart:80), khoá bài (mobile/lib/domain/progression.dart:22), hàm so chuỗi cũ (mobile/lib/domain/answer_checker.dart:68) | docs/ARCHITECTURE.md:1 |
| data | tải nội dung + cache (mobile/lib/data/content_repository.dart:40), provider nội dung (mobile/lib/data/content_providers.dart:11), client gọi `/run` (mobile/lib/data/judge_client.dart:59), đăng nhập (mobile/lib/data/auth_repository.dart:61), client gắn Bearer (mobile/lib/data/api_client.dart:59), tiến độ server (mobile/lib/data/progress_api.dart:116), admin (mobile/lib/data/admin_repository.dart:1) | docs/ARCHITECTURE.md:1 |
| features/exercise | màn bài 3 tab (<900px) hoặc chia đôi đề | editor (≥900px) (mobile/lib/features/exercise/exercise_screen.dart:31), tiến độ/đồng hồ (mobile/lib/features/exercise/session_controller.dart:29), editor autocomplete | docs/modules/exercise-screen.md:1 |
| features/browse | duyệt Home → Theme → Module (lồng nhiều tầng) → danh sách bài, nhóm theo class, có trạng thái khoá (mobile/lib/features/browse/exercise_row.dart:39) | docs/ARCHITECTURE.md:1 |
| features/review, stats, practice, shell | ôn tập, thống kê, luyện, shell (bottom nav 5 tab <700px; ≥700px top bar + ☰ mở drawer — mobile/lib/features/shell/app_shell.dart:22, mobile/lib/features/shell/app_drawer.dart:25); đọc tiến độ từ cùng `progressProvider`, không mô tả chi tiết ở đây (mobile/lib/app/router.dart:30-72) | docs/ARCHITECTURE.md:1 |
| features/admin + account | màn Admin đi từng tầng Projects → module → file/bài (mobile/lib/features/admin/admin_screen.dart:15, mobile/lib/features/admin/admin_theme_screen.dart:1, mobile/lib/features/admin/admin_module_screen.dart:1), form sửa bài responsive 3 breakpoint với ô code tô màu (mobile/lib/features/admin/exercise_editor.dart:386, mobile/lib/features/admin/code_cell.dart:133), màn Chờ duyệt + chi tiết diff + xem thử như học viên (mobile/lib/features/admin/review_screen.dart:1, mobile/lib/features/admin/review_detail_screen.dart:1, mobile/lib/features/exercise/exercise_screen.dart:51), đăng nhập và đổi mật khẩu (mobile/lib/features/account/login_screen.dart:1) | docs/modules/content-admin.md:1 |
| app | theme (mobile/lib/app/theme.dart:1) + router (mobile/lib/app/router.dart:22) + cổng nội dung (mobile/lib/app/content_gate.dart:12) + cổng đăng nhập (mobile/lib/app/auth_gate.dart:13) | docs/ARCHITECTURE.md:1 |
| backend/sd | chế độ học System Design: parser `.md` → chapter/section/card + task (id card = hash NFC của nội dung), API admin nhập tài liệu `/api/admin/sd` (nghiệp vụ nhập/sửa/xoá mềm dùng chung với MCP và CLI ở backend/app/sd/docs.py:74), API học viên `/api/sd` (khoá/mở tính ở server; `GET /api/sd/docs` kèm `courses` nhóm theo course, backend/app/sd/learner.py:120), lần thử + chấm từ khoá + hàm chấm sâu cho MCP — backend/app/sd/parser.py:366, backend/app/sd/admin.py:57, backend/app/sd/learner.py:48, backend/app/sd/attempts.py:85, backend/app/sd/evaluator.py:29 | docs/modules/sd-study.md:1 |
| backend/sd tables | 5 bảng `sd_docs/sd_sections/sd_tasks/sd_progress/sd_attempts` + bảng `courses` (nhóm doc, chỉ để hiển thị; `sd_docs.course_id`/`course_position`) + migration `0007`, `0008` (cột `source_md`, status `archived`), `0009` (courses; backend/migrations/versions/0009_courses.py:22); tiến độ và lần thử chỉ FK `users`, không FK tới nội dung — backend/app/tables.py:241, backend/app/tables.py:290, backend/migrations/versions/0007_system_design.py:22, backend/migrations/versions/0008_sd_source_archive.py:21 | docs/modules/sd-study.md:1 |
| features/system_design + tab Design | tab thứ 5: danh sách tài liệu, lộ trình `DuoPath` (mobile/lib/features/system_design/duo_path.dart:80), màn đọc tự đánh dấu (mobile/lib/features/system_design/reader_screen.dart:124), bối cảnh + task + bản nháp theo người dùng (mobile/lib/features/system_design/task_screen.dart:186); model và repository (mobile/lib/domain/sd_models.dart:1, mobile/lib/data/sd_repository.dart:33); route khai ở router, đã khớp index ở shell/drawer — backend/app/sd/learner.py:48 (nơi server tính khoá/mở mà các màn này chỉ vẽ lại) | docs/modules/sd-study.md:1 |
| deploy | triển khai lên VPS dùng chung: nginx cổng 443 (HTTPS, domain `codewithphuong.jacons-corp.com`, cert Let's Encrypt; :80 và :8090 trả 308) phục vụ web tĩnh và chuyển `/content`, `/run`, `/api/*` vào uvicorn 127.0.0.1:8100; một lệnh `deploy/deploy.sh` (migration, nạp nội dung chỉ khi DB rỗng, seed user) — deploy/deploy.sh:1, deploy/deploy.sh:87-97, deploy/nginx/smart-coding-study.conf:8-27 | docs/modules/deploy.md:1 |
| deploy/ios | build bản iOS cho TestFlight: `flutter build ipa` trỏ cùng origin HTTPS; icon tạm sinh bằng script — deploy/ios-build.sh:11-35, deploy/IOS-TESTFLIGHT.md:1, mobile/tool/make_app_icon.py:1 | docs/modules/deploy.md:1 |
| shared | widget dùng chung (card, chip, nút, progress bar...) (mobile/lib/shared/widgets.dart:1) | docs/ARCHITECTURE.md:1 |

## backend — chấm bài bằng Python thật

### Là gì

Backend là một server FastAPI nhỏ với hai việc. Một: phát nội dung học (theme → module, module lồng nhau được → file → bài →
ô TODO) cho app qua `GET /content`, đọc từ Postgres. Hai: nhận `{exercise_id, code}` từ app, chạy
code đó cùng các test case của bài bằng Python thật rồi trả kết quả từng test. Test case và lời
giải tham chiếu nằm trong cùng Postgres nhưng không bao giờ ra khỏi `/content`, nên app không sửa
được bài kiểm tra. Backend không tự chạy code
học viên — nó nhờ một "máy chấm" bên ngoài qua interface `CodeRunner`, hiện là Judge0 CE công
khai. Chi tiết xem `docs/modules/judge-backend.md`.

### Cách hoạt động

| Bước | Ai làm | file:dòng |
| --- | --- | --- |
| Kiểm body (≤64KB, có Content-Length) và `code` ≤ 8000 ký tự | middleware + `RunRequest` | backend/app/main.py:42-56 |
| Tra bài trong Postgres bằng session ngắn (đóng trước khi chờ máy chấm); không có bài → 404 | `lookup_judge` | backend/app/main.py:120-122, backend/app/content_api.py:156-182 |
| Ghép payload `{code, function, class_name, cases}` | `run()` | backend/app/main.py:124-131 |
| Gửi `HARNESS_SOURCE` làm source, payload làm stdin cho máy chấm (tối đa 4 đồng thời) | `runner.run` | backend/app/main.py:130-131 |
| Máy chấm hỏng/429/5xx/không hiểu → `503 runner_unavailable` | `RunnerUnavailable` | backend/app/main.py:132-134 |
| DB không kết nối được → `503 database_unavailable`; chưa nạp nội dung → `503 content_not_loaded` | exception handler | backend/app/main.py:75-84 |
| Quá giờ → `status: timeout`; còn lại parse dòng `__JUDGE_RESULT__` | `harness.parse_result` | backend/app/main.py:137-145 |

```python
class CodeRunner(Protocol):
    async def run(self, source: str, stdin: str) -> Execution: ...
```
(backend/app/runner.py:42-43)

### Ranh giới

Không chống gian lận: code học viên chạy cùng tiến trình với harness, nên cố tình in dòng kết quả
giả là tự lừa mình (chấp nhận cho app học; hệ quả: server vẫn ghi passed cho kết quả giả, nhưng tiến độ chỉ
của chính người đó, không xếp hạng). `/run` và `/content` vẫn công khai; đăng nhập, tiến độ và quản trị là
các API `/api/*` có xác thực (xem hai mục dưới). Mặc định chạy local (`127.0.0.1:8000`; trên VPS xem mục deploy) và cần Postgres
(`DATABASE_URL`, backend/app/db.py:11-15).

## Luồng nội dung — content.json → Postgres → /content → cache trong app

### Là gì

Postgres là nguồn chính của nội dung học: cả `/content` lẫn `/run` đọc từ đó nên id bài ở hai API luôn khớp.
File `backend/content/content.json` chỉ còn để seed lần đầu (deploy chỉ nạp khi DB rỗng) và làm bản xuất; admin
sửa thẳng DB qua `/api/admin/content`. Backend phát nội dung cho app qua `GET /content`; app lưu bản tải gần nhất
trên máy để mở được khi mất mạng. App không chứa nội dung học nào.

### Cách hoạt động

| Chặng | Làm gì | file:dòng |
| --- | --- | --- |
| Soạn | `content.json` = cây nội dung + `judge: {solution, cases}` mỗi bài; bài method có `class_name` | backend/content/content.json:195,266 |
| Ghi | MỌI đường ghi (CLI và admin PUT) đi qua `load_content`: `validation_errors` (schema, id, case, sơ đồ, trần kích thước + `content_rules`), khoá `pg_advisory_xact_lock`, xoá hết rồi ghi lại trong một transaction, `version` = sha256 phần công khai | backend/app/load_content.py:217-283, backend/app/load_content.py:298-387 |
| Lưu | bảng `themes/topics/code_files/exercises/file_exercises/blocks/content_meta` | backend/app/tables.py:18-108 |
| Phát | `GET /content`: 6 SELECT kẹp giữa hai lần đọc `version`, đọc lại (tối đa 3) nếu version đổi giữa chừng; `response_model` không có `judge` | backend/app/content_api.py:44-61,184-186 |
| Tải + cache | `GET /content` timeout 5s; thành công thì ghi cache; lỗi gì cũng rơi về cache; không có cache thì `ContentUnavailable` (mobile/lib/data/content_repository.dart:58-98) | docs/ARCHITECTURE.md:1 |
| Cổng | `ContentGate` chờ/lỗi/dữ liệu + banner khi dùng cache; `main()` override `contentIndexProvider` (mobile/lib/app/content_gate.dart:17-71, mobile/lib/main.dart:10-21) | docs/ARCHITECTURE.md:1 |

```python
# nạp: version cùng transaction với dữ liệu
session.add(ContentMeta(key="version", value=version))
session.flush()
```
(backend/app/load_content.py:385-386)

### Ranh giới

Sửa `content.json` rồi deploy KHÔNG còn tác dụng khi DB đã có nội dung (`--if-empty` bỏ qua); muốn sửa bằng file thì
`export_content` → sửa → `load_content --force` (backend/app/load_content.py:407-409, backend/README.md:34-62). Đổi `id`
bài hoặc `label` ô làm tiến độ cũ mồ côi: tiến độ khoá theo hai thứ đó (bỏ qua id lạ, không mất dữ liệu khác). `/content` không có
xác thực và không phân trang (trả cả cây một lần). Mọi lỗi `/content` đều hiện cùng một banner
"dùng nội dung đã lưu" — app không phân biệt mạng hỏng với server trả dữ liệu sai.

## Cây nội dung — module lồng nhau + bài method

### Là gì

Nội dung học là một cây: theme chứa module, module chứa file và có thể chứa module con (không giới hạn
độ sâu), file chứa bài. Ví dụ seed "Airline Reservation System" có module cấp 1 và module con
"Schedule — lịch bay" bên trong (backend/content/content.json:36-51). Một bài có thể là hàm rời hoặc là
method của một class (`FlightService.add_flight`); bài method chỉ chấm được bằng case kịch bản. Hai thứ
này (module con, tên class) cùng đi từ file soạn tới DB, tới `/content`, tới app, và tới máy chấm.

### Cách hoạt động

| Khái niệm | Soạn / DB | Phát qua `/content` | Trong app |
| --- | --- | --- | --- |
| Module con | key `modules` (đệ quy) trong `content.json`; DB lưu `topics.parent_id` (FK về chính nó, CASCADE) + `topics.position` là thứ tự preorder trong theme — backend/app/tables.py:31-41, backend/migrations/versions/0002_module_tree_class.py:22-27 | `topics` cấp 1 theo theme, `modules` lồng theo `parent_id` — backend/app/content_api.py:72-80,95-107 | `Topic.modules`, `allFiles`/`allModules` duyệt preorder (file của module trước, rồi module con) — mobile/lib/domain/models.dart:116-135 |
| Tên class | `Exercise.class_name` là cột nullable, không phải bảng riêng — backend/app/tables.py:67 | `class_name` trong payload bài; cũng nằm trong `Judge` để `/run` dùng — backend/app/content_api.py:29,133,164 | `Exercise.className`, `qualifiedName` — mobile/lib/domain/models.dart:316-320 |
| Sơ đồ class | key bắt buộc `diagram` mỗi theme; DB cột JSONB `themes.diagram` — backend/app/content_schema.py:76-113, backend/app/tables.py:30, backend/migrations/versions/0003_theme_diagram.py:22-38 | `diagram` nằm trong payload theme, không thêm query — backend/app/content_api.py:118 | `StudyTheme.diagram` (`ClassDiagram`), highlight suy từ code bài bằng `classScope` — mobile/lib/domain/models.dart:53,224-243, mobile/lib/domain/class_scope.dart:27-55 |

Nạp cây bằng duyệt trước (cha trước con) nên `position` tăng đúng thứ tự và FK `parent_id` luôn trỏ vào
hàng đã flush:

```python
def _walk_topics(topics: list[dict], parent_id: str | None = None):
    for tp in topics:
        yield tp, parent_id
        yield from _walk_topics(tp.get("modules", []), tp.get("id"))
```
(backend/app/load_content.py:42-46; ghi DB: backend/app/load_content.py:184-191)

Vị trí ô (nhãn "trong hàm / trong method / trong class" ở tiêu đề ô) không được lưu ở đâu cả mà suy ra từ
template: tìm dòng marker `# TODO <nhãn>`, lấy dòng cha gần nhất có thụt lề nhỏ hơn, phân loại
`def`/`class`, và nếu `def` đó nằm dưới một dòng `class` thì là method (mobile/lib/domain/merge.dart:135-175).
Cha là marker ô khác thì dùng dòng đầu đáp án mẫu của ô đó.

### Ranh giới

Tên class chỉ là thuộc tính của bài: không có bảng `classes`, và cùng một class (`FlightService`) có nhiều
bài chỉ lặp chuỗi tên (backend/app/tables.py:67). Nhóm bài theo class ở màn Topic dựa vào
`className` liền kề khác nhau trong cùng file (mobile/lib/features/browse/topic_detail_screen.dart:55-64).
Hạ cấp migration 0002 làm mất quan hệ cha–con và `class_name`; chấp nhận được vì bảng nội dung chỉ là bản
dẫn xuất của `content.json`, nạp lại là có đủ (backend/migrations/versions/0002_module_tree_class.py:33-35).
Sơ đồ class của theme soạn tay (quan hệ không suy ra được từ code mẫu) và loader chỉ kiểm tính nhất quán nội bộ: tên class duy nhất, `from`/`to` có thật, `via` ⊆ methods của `from` (backend/app/load_content.py:70-87); schema chỉ nhận key `from` (backend/app/content_schema.py:96). Việc sơ đồ khớp code bài do test hợp đồng bên Dart kiểm (mobile/test/content_contract_test.dart:367-426), không phải runtime. Tab Challenge hiện mục "SƠ ĐỒ CLASS" cho bài method có class trong sơ đồ (mobile/lib/features/exercise/challenge_tab.dart:44-45,101-105).
`/content` không kiểm module con có cùng theme với cha hay không (chỉ đúng nếu DB do loader ghi); sửa DB tay
có thể làm sai (planning/crew/2026-10-11-project-tree-airline/STATUS.md, Backlog T-07).

## Chấm bài method — case kịch bản

### Là gì

Hàm rời gọi được bằng `func(*args)`. Method thì cần một đối tượng đã dựng: phải tạo `FlightService`, thêm vài
chuyến bay, rồi mới gọi `search`. Vì vậy case chấm có thêm dạng "kịch bản": một danh sách câu lệnh chuẩn bị
(`steps`), một biểu thức gọi (`call`), và kỳ vọng là giá trị trả về hoặc loại exception ném ra.
Hai dạng case cùng nằm trong `judge.cases`; harness phân biệt bằng việc case có key `call` hay không.

### Cách hoạt động

| | Case cũ (hàm rời) | Case kịch bản (method) |
| --- | --- | --- |
| Hình dạng | `{args, expect: {return}}` hoặc `{args, expect: {arg, value}}` (backend/app/harness.py:150-156) | `{steps?: [..], call: "..", expect: {return}}` hoặc `expect: {raises: "TênLỗi"}` (backend/app/harness.py:48-53) |
| Cách chạy | `func(*deepcopy(args))` trên namespace sau khi `exec` code học viên (backend/app/harness.py:157-161) | `exec` từng `step` rồi `eval` `call` trong bản sao nông của namespace, mỗi case một bản mới (backend/app/harness.py:58-66) |
| Dừng khi nào | exception → dừng, các case sau không chạy (backend/app/harness.py:161-167) | exception khi `expect.return` → dừng; khi `expect.raises` → là kết quả case, chạy tiếp (backend/app/harness.py:68-86) |
| Nơi | backend/app/harness.py:150-172 | backend/app/harness.py:48-87,142-148 |

```python
if class_name:
    cls = namespace.get(class_name)
    if not isinstance(cls, type):
        error = {"kind": "runtime", "line": None,
                 "message": "Không tìm thấy class %s trong code" % class_name}
```
(backend/app/harness.py:123-131) — `raises` so theo tên trong MRO của exception nên bắt cả lớp con (backend/app/harness.py:75-78).
Đổi tên class hay method thì báo "Không tìm thấy class/method ..." thay vì lỗi lạ (backend/app/harness.py:132-139).

Lỗi soạn bài bị chặn lúc nạp, không để tới harness (nếu không học viên thấy lỗi như do code mình sai):
`steps`/`call` phải `compile` được, `expect` phải có `return` hoặc `raises` (backend/app/load_content.py:49-67),
và bài có `class_name` bắt buộc mọi case là dạng `call` vì harness không gọi method theo `args`
(backend/app/load_content.py:111-117).

### Ranh giới

`steps`/`call` do tác giả viết trong content DB, không bao giờ từ client (backend/app/harness.py:145). Bản sao
nông của namespace nghĩa là thuộc tính gán thẳng lên class ở một case vẫn rò sang case sau; test cho việc này
chưa có (planning/crew/2026-10-11-project-tree-airline/STATUS.md, Backlog harness). Backlog thêm: `SystemExit`
trong `steps`, và `project.output` của bài `raises` chỉ ghi loại lỗi chứ không kèm message.

## Domain + Data

### Là gì

Tầng dữ liệu thuần Dart, không phụ thuộc Flutter UI: cấu trúc nội dung học (theme → topic/module lồng nhau → file →
exercise → block, một block = một ô TODO) và các hàm thuần (ghép ô, khoá bài). Nội dung hiển thị
(đề, ví dụ, template, gợi ý, lời giải từng ô) không nằm trong app: app tải từ `GET /content` và
giữ thành một đối tượng `Content` (cây + hàm tra cứu) mà mọi màn đọc qua `contentIndexProvider`.
Tiến độ học không nằm ở tầng này mà đến từ server sau đăng nhập (xem mục Tài khoản + tiến độ).

### Cách hoạt động

Một bài có `template` là code khoá, mỗi ô TODO là một dòng `# TODO <nhãn>` ở đúng thụt lề:

```json
"template": "def split_chunks(text, size):\n    chunks = []\n    # TODO A\n        # TODO B\n    # TODO C",
```
(backend/content/content.json:112)

`mergeCells` thay mỗi dòng marker bằng nội dung ô (đã dedent, thụt theo marker) và trả `lineOrigin`
để biết dòng nào thuộc ô nào (mobile/lib/domain/merge.dart:80-102). Lỗi trả về là số dòng của code
đã ghép nên client tra `lineOrigin[line-1]` để tô đúng ô (mobile/lib/features/exercise/run_result_view.dart:23-30).

So với phase 1: việc chấm không còn là `runBlock` so chuỗi với `acceptedAnswers` — backend chạy test thật,
còn `runBlock` chỉ phục vụ ôn tập và gợi ý phụ "kiểm tra lại ô này" (mobile/lib/domain/answer_checker.dart:68,
mobile/lib/features/exercise/code_tab.dart:177-189). Đơn vị làm bài không còn là block tuần tự mỗi block một màn:
cả bài nằm trên một màn và mỗi block là một ô (`Block.label` A/B/C). "Đã xong" không còn là `completedBlocks` đếm
block mà là `ExerciseProgress.passed` (mobile/lib/features/exercise/session_controller.dart:38,47).

### Ranh giới

Hợp đồng `/run` được giữ khớp bằng hai bên tự viết (Python `RunResponse` và Dart `JudgeClient._parse`)
cộng test fixture tay — không sinh code từ một schema chung (mobile/lib/data/judge_client.dart:109-146,
backend/app/main.py:67-88). Hình dạng `/content` cũng giữ khớp bằng hai bên tự viết: model pydantic
(backend/app/content_schema.py:66-102) và `Content.fromJson` (mobile/lib/domain/content.dart:14), có test fixture
đọc thẳng `backend/content/content.json` (mobile/test/support/content_fixture.dart:12). `contentIndexProvider`
không có mặc định — quên override thì ném `UnimplementedError` (mobile/lib/data/content_providers.dart:11-13).

## features/exercise — màn bài 3 tab + session

### Là gì

Màn người học thực sự làm bài. `ExerciseScreen` hiển thị đồng hồ, thanh 3 tab và kiểm bài đã mở
khoá chưa; mỗi tab là một widget riêng. `SessionController` lo đồng hồ/idle/timeout, còn
`ProgressController` giữ tiến độ (đã pass, code đang gõ, gợi ý đã dùng, ô đã xem lời giải). Chi tiết
xem `docs/modules/exercise-screen.md`, `docs/modules/exercise-session.md`,
`docs/modules/exercise-autocomplete.md`.

### Cách hoạt động

Ba tab (mobile/lib/features/exercise/exercise_screen.dart:293-295, nội dung ở dòng 302-304):
**Challenge** (`ChallengeTab`, mobile/lib/features/exercise/challenge_tab.dart:14) hiện đề bài, "dùng để làm gì"
và hai ví dụ (nhỏ + dự án thật); **Code** (`CodeTab`, mobile/lib/features/exercise/code_tab.dart:23) là notebook
gồm đoạn khoá và các ô TODO, bấm Run thì ghép → gọi backend → hiện bảng test (mobile/lib/features/exercise/code_tab.dart:97-137);
**Solution** (`SolutionTab`, mobile/lib/features/exercise/solution_tab.dart:15) mở lời giải từng ô và ghi
`solutionViewed` (mobile/lib/features/exercise/solution_tab.dart:59-65).

Chỉ khi backend trả `passed` thì tiến độ mới đổi:

```dart
if (result.status == JudgeStatus.passed) {
  ref.read(progressProvider.notifier).markPassed(_exercise.id);
}
```
(mobile/lib/features/exercise/code_tab.dart:128-130)

Ô còn rỗng thì Run không gọi backend mà đánh dấu ô rỗng (mobile/lib/features/exercise/code_tab.dart:100-111).
Bài chưa mở khoá hiện `_LockedView` thay vì 3 tab (mobile/lib/features/exercise/exercise_screen.dart:38-39).

Từ bề rộng 900px (`AppBreakpoint.split`) màn luyện đổi bố cục: ẩn `TabBar`, chia cột trái Đề/Lời giải (42%)
và cột phải `CodeTab(inlineEditor: true)` (58%); dưới 900px giữ đúng ba tab và mở ô bằng route `CellEditorPage`
(mobile/lib/features/exercise/exercise_screen.dart:292-298,448-458). Ở chế độ inline, ô đang mở là editor ngay trong notebook và có dải
bước A/B/C; hai layout dùng chung `_isDone`/`_onCellChanged`/`_run` của `CodeTab`, nên "ô đúng" chỉ có một nơi quyết định
(mobile/lib/features/exercise/code_tab.dart:37-47,77,156,197).

### Ranh giới

Tiến độ vẫn nằm trong bộ nhớ Riverpod (`ProgressController` không `autoDispose`), mất khi kill app.
Rời màn khi đang Run thì kết quả `passed` về sau bị bỏ (`if (!mounted) return`,
mobile/lib/features/exercise/code_tab.dart:126), nên tiến độ không được ghi.

## features/browse — Home / Theme / Topic

### Là gì

Các màn đưa người học từ danh sách chủ đề tới đúng bài tập: Home liệt kê theme, Theme detail liệt kê
topic, Topic detail liệt kê thẻ module con (nếu có) rồi file/exercise. Mỗi dòng bài (`ExerciseRow`) hiện trạng thái Mới / Đang
dở / Đã xong / Khoá, và Home có thẻ "Tiếp tục" cho bài đang dở.

### Cách hoạt động

Route (mobile/lib/app/router.dart): `/` là HomeScreen trong tab shell (dòng 31), `/theme/:themeId` là
ThemeDetailScreen (dòng 62), `/topic/:topicId` là TopicDetailScreen (dòng 68), `/exercise/:exerciseId` là
ExerciseScreen 3 tab (dòng 85) — thay cho BlockListScreen + CellScreen và route `/exercise/:id/block/:index` cũ.

`ExerciseRow` không tự viết điều kiện khoá, nó đọc `exerciseUnlockedProvider`
(mobile/lib/features/browse/exercise_row.dart:39); thẻ "Tiếp tục" đọc `inProgressExerciseProvider`
(mobile/lib/features/exercise/session_providers.dart:30-42).

### Ranh giới

Module lồng nhiều tầng đi qua cùng route `/topic/:topicId`: module con là thẻ trên Topic detail bấm vào mở chính màn đó với id con (mobile/lib/features/browse/topic_detail_screen.dart:49-50,146-147); trong file, bài của cùng một class được nhóm dưới tiêu đề `class <Tên>` (mobile/lib/features/browse/topic_detail_screen.dart:55-64,173-183).

Hai thứ tên gần giống nhau: `completedBlocks` nay chỉ là getter suy ra từ `passed` (xong thì bằng
tổng số ô, chưa xong thì 0), không còn nói "đã gõ đúng bao nhiêu block". Dựng tay
`ExerciseProgress(passed: true)` mà quên `totalBlocks` thì `completedBlocks` ra 0
(mobile/lib/features/exercise/session_controller.dart:47).

## app — theme + router

### Là gì

Tầng `app/` giữ hai thứ chạm tới toàn bộ ứng dụng: bảng màu/kiểu chữ/khoảng cách dùng chung
(`theme.dart`) và bảng route (`router.dart`). Giao diện theo bộ "The Coach": nền sáng là mặc định
(mobile/lib/app/theme_mode.dart:9), tối vẫn chọn được qua nút đổi giao diện. Widget không đọc thẳng
màu hằng mà đọc qua `context.palette` (một `ThemeExtension` đổi theo sáng/tối), nên một vai trò màu
chỉ có một tên và hai giá trị.

### Cách hoạt động

| Thứ | Cách làm | Nguồn |
|---|---|---|
| Palette | `AppColors` (tối) và `AppLightColors` (sáng) cùng vai trò token; `AppPalette` gom lại, có đủ `copyWith`/`lerp` | mobile/lib/app/theme.dart:8-30,92-232 (docs/ARCHITECTURE.md:1) |
| Khối code | `codeSurface`/`codeInk` luôn tối ở cả hai theme, để khối code đọc giống nhau dù trang sáng | mobile/lib/app/theme.dart:24-25,45-46 (docs/ARCHITECTURE.md:1) |
| Ngưỡng bề rộng | `AppBreakpoint.nav = 700`, `AppBreakpoint.split = 900` — nơi duy nhất định nghĩa | mobile/lib/app/theme.dart:84-87 (docs/ARCHITECTURE.md:1) |
| Font | Nunito (variable, một file) + JetBrains Mono, bundle trong `assets/fonts/` | mobile/pubspec.yaml:64-76 (docs/ARCHITECTURE.md:1) |
| Chế độ sáng/tối | mặc định `ThemeMode.light`, vòng sáng → tối → hệ thống | mobile/lib/app/theme_mode.dart:9-18 (docs/ARCHITECTURE.md:1) |

Font không tải qua mạng (không dùng gói `google_fonts`). Nunito chỉ có bản *variable font* (một
file chứa mọi độ đậm, chọn bằng trục `wght`), nên mỗi kiểu chữ vừa đặt `fontWeight` vừa đặt
`FontVariation('wght', n)` để engine thật sự áp trục đó:

```dart
static const TextStyle title = TextStyle(
  fontFamily: kSansFamily,
  fontSize: 20,
  fontWeight: FontWeight.w800,
  fontVariations: [FontVariation('wght', 800)],
);
```
(mobile/lib/app/theme.dart:3,272-278)

Ngưỡng 700/900 nằm ở một chỗ để các nơi dùng không lệch nhau: shell, `ScreenHeader`, màn luyện, Home
đều so với `AppBreakpoint`, không có số 700/900 cứng nào khác trong `lib/` (planning/crew/2026-10-12-issue29-reskin/reviews/SEAM.md, INV-03).
Sáng là mặc định nên `main.dart`, cổng nội dung và cổng đăng nhập đều đọc cùng `themeModeProvider`;
nếu một trong ba đọc nguồn khác, màn chờ sẽ tối trong khi app sáng (INV-07 cùng file).

### Ranh giới

`router.dart` không có redirect: chặn đăng nhập nằm ở `AuthGate` bọc ngoài toàn app (chưa có phiên thì hiện
màn Login, chưa tải xong tiến độ thì spinner) (mobile/lib/app/auth_gate.dart:13-36, mobile/lib/main.dart:19). Route mở
thẳng được khi đã đăng nhập, kể cả `/exercise/:exerciseId` (việc khoá bài do `ExerciseScreen` tự kiểm; xem mục
features/exercise). Route `/admin` không tự chặn học viên: UI chỉ ẩn nút, server mới từ chối bằng 403.

## shared — widget dùng chung

### Là gì

Bộ widget tái dùng giữa các màn: `SurfaceCard`, `TagChip`, `ResultBadge`, `TimerPill`,
`ThinProgressBar`, `ScreenHeader`, `SectionLabel`, `PrimaryButton`, `GhostButton`, `HintButton`.
Tồn tại để tránh mỗi màn tự viết lại card/nút/progress bar theo phong cách khác nhau.

### Cách hoạt động

Tất cả đọc màu từ `context.palette` và kích thước từ `AppSpace`/`AppRadius`/`AppText`, không hardcode
giá trị. Nút `PrimaryButton`/`GhostButton` kiểu "nổi khối" (bóng cứng bên dưới) nhưng vẫn là
`ElevatedButton`/`OutlinedButton` bên trong (mobile/lib/shared/widgets.dart:310,351), vì test của màn
Soạn bài tập tìm đúng hai widget đó. `ScreenHeader` tự thêm nút ☰ khi bề rộng ≥ 700px và widget không
nằm trong `AppShell` (mobile/lib/shared/widgets.dart:208-211).

### Ranh giới

Nút bóng cứng chỉ là trang trí ngoài `ElevatedButton`/`OutlinedButton`, nên nút vô hiệu vẫn là `onPressed == null`
(mobile/lib/shared/widgets.dart:310,351). `shared/widgets.dart` import ngược `features/shell` để biết có đang nằm trong shell hay không
(mobile/lib/shared/widgets.dart:3) — lớp dưới biết lớp trên, chưa tách.


## Tài khoản + tiến độ — đăng nhập, token Bearer, tiến độ theo user trên server

### Là gì

App giờ có người dùng. Đăng nhập bằng email và mật khẩu (băm argon2id); server trả một token ngẫu nhiên, app gửi nó trong
header `Authorization: Bearer` ở mọi lần gọi `/api/*`, còn DB chỉ lưu sha256 của token. Tiến độ học (bài đã xong, bản nháp
code, gợi ý, ô đã xem lời giải, lịch ôn, chuỗi ngày học) lưu trong Postgres theo user nên tải lại trang hay đổi máy vẫn còn.
Phân quyền kiểm ở server; UI ẩn nút Admin chỉ để gọn. Chi tiết xem `docs/modules/auth-progress.md`.

### Cách hoạt động

| Chặng | Làm gì | file:dòng |
| --- | --- | --- |
| Đăng nhập | 401 `invalid_credentials`; sai 5 lần/15 phút theo (IP, email) hoặc 30 lần/IP thì 429; phiên sống 30 ngày | backend/app/auth.py:222-245, backend/app/auth.py:35-41 |
| Kiểm quyền | không token hợp lệ: 401 `not_authenticated`; thiếu role admin: 403 `admin_required` | backend/app/auth.py:184-194 |
| Chế độ mở | env `AUTH_OPEN_AS=<email>`: không token (hoặc token sai) = user đó, token thật thắng; `/api/me` có `open`; đổi mật khẩu 403 `open_mode`; app vào thẳng bằng phiên token rỗng (xem `docs/modules/auth-progress.md`) | backend/app/auth.py:166-189, mobile/lib/data/auth_repository.dart:114-123 |
| Tiến độ | `GET /api/progress` (ẩn id bài không còn), `PUT /api/progress/{id}` và `/state`; không nhận `passed` | backend/app/progress.py:179-256 |
| Ghi passed | chỉ `/run` ghi, khi máy chấm trả passed và request có Bearer hợp lệ | backend/app/progress.py:28-44, backend/app/main.py:184-190 |
| Bảng | `users`, `user_sessions`, `user_progress` (khoá `(user_id, exercise_id)`, KHÔNG FK tới bài), `user_state` | backend/app/tables.py:128-184 |
| App | `AuthGate` đặt sau `ContentGate`; vào app khi `/api/progress` của đúng phiên đã tải; draft đẩy sau 800 ms, hint/xem lời giải/lịch ôn đẩy ngay (mobile/lib/app/auth_gate.dart:13-36, mobile/lib/features/exercise/session_controller.dart:74-86) | docs/modules/auth-progress.md:1 |

### Ranh giới

Chưa có đăng ký tự do, quản lý user, quên mật khẩu; user chỉ tạo qua `seed_users` (backend/app/seed_users.py:27-30). Đồng bộ "mới nhất thắng", không gộp.
Bộ đếm đăng nhập sai nằm trong RAM nên mất khi restart và chỉ đúng với một process uvicorn (backend/app/auth.py:5-7).
Mật khẩu và token đi qua HTTPS (deploy/nginx/smart-coding-study.conf:22-30); chưa bật HSTS (header buộc trình duyệt luôn dùng https) (planning/crew/2026-10-11-testflight-prep/STATUS.md Backlog).

## Quản trị nội dung — DB là nguồn chính, một đường ghi

### Là gì

Admin sửa nội dung ngay trong app: màn Admin đi từng tầng theme → module → file/bài (mỗi tầng một màn, có breadcrumb) và form sửa từng bài. Bấm "Kiểm tra" chạy bộ luật
nội dung ở server mà không ghi, bấm "Gửi duyệt" gửi cả bộ nội dung kèm số phiên bản đang giữ; server diff ra từng mục và đưa vào hàng chờ, học viên vẫn chỉ thấy bản đã duyệt (live).
Nếu người khác đã gửi trước thì server trả 409 để không ai âm thầm xoá việc của nhau. Claude qua MCP cũng chỉ vào hàng chờ. Admin duyệt hoặc bỏ từng mục ở màn "Chờ duyệt" (hoặc Claude gọi `publish_changes` qua MCP khi người dùng bảo, cùng hàm `review.approve`); CLI và duyệt cùng đi qua một hàm ghi `load_content`, nên bộ luật và khoá ghi không thể lệch nhau. Chi tiết xem
`docs/modules/content-admin.md` và `docs/modules/content-review.md`.

### Cách hoạt động

| Chặng | Làm gì | file:dòng |
| --- | --- | --- |
| API | `GET /api/admin/content` (bản nháp, có `judge`), `POST /api/admin/validate`, `PUT /api/admin/content` → 200 / 409 / 422 (vào hàng chờ), `GET /api/admin/changes`, `POST .../approve`, `POST .../reject`; cả router gắn `require_admin` | backend/app/admin_api.py:33, backend/app/admin_api.py:94-174 |
| Luật | schema + trần kích thước + id/case/sơ đồ + luật port từ Dart (marker, ghép đáp án == solution, ≤3 ô, 3 gợi ý, không ô sau `return`, sơ đồ khớp code) | backend/app/load_content.py:217-283, backend/app/content_rules.py:274-310 |
| Ghi | PUT: kiểm `base_version` (hash bản nháp) rồi upsert mục chờ trong `pg_advisory_xact_lock`; chỉ `approve` (và CLI `--force`) mới gọi `load_content` lên nội dung đang chạy | backend/app/review.py:399-434, backend/app/review.py:487-514, backend/app/load_content.py:298-300 |
| CLI | `load_content --if-empty` (deploy) / `--force`; `export_content` xuất DB ra shape `content.json` | backend/app/load_content.py:390-416, backend/app/export_content.py:36-69 |
| App | `AdminController` giữ bản nháp và `version`; Gửi duyệt không nạp lại `/content`, chỉ duyệt một mục mới nạp lại (mobile/lib/features/admin/admin_controller.dart:517-519, mobile/lib/features/admin/admin_controller.dart:629-631) | docs/modules/content-review.md:1 |

### Ranh giới

Server không chạy lời giải mẫu khi Gửi duyệt (không thực thi code ở server admin); việc đó là của nút Run, và preview của admin chấm bằng `/api/admin/run` theo bản nháp mà không ghi tiến độ (backend/app/main.py:225-242). Chưa hỗ trợ chuyển module sang project/module cha khác: gửi duyệt bị 422 `unsupported_move` (backend/app/review.py:87-95). Không có lịch sử phiên bản: khôi phục dùng `export_content` và git.
Luật nội dung có hai bản cài đặt, Dart (`mergeCells`, preview/test) và Python (`content_rules.py`, server), không có test so trực tiếp nhau (backend/app/content_rules.py:8-11).
Lưu là thay toàn bộ nội dung, nên học viên đang mở bài giữ bản cũ tới lần tải kế.

## Chế độ học System Design — tài liệu `.md` → card → lộ trình → thực chiến

### Là gì

Bên cạnh chế độ code (bài tập chấm bằng test), app có một chế độ đọc và viết thiết kế hệ thống. Admin nhập một file markdown; backend cắt thành chương, section và "card" (mỗi đoạn, bảng, khối code là một card). Học viên đọc các section theo thứ tự tuỳ ý (có chế độ xem trước không tính tiến độ và nút đặt lại tiến độ), và khi đọc hết mọi section thì mở phần thực chiến: tự viết lời giải cho từng task, thấy điểm theo từ khoá ngay, rồi nhờ Claude chấm sâu hơn qua MCP. Chế độ này có bảng, API và màn hình riêng, không đi qua `load_content` hay hàng chờ duyệt. Chi tiết đầy đủ ở `docs/modules/sd-study.md`.

### Cách hoạt động

| Việc | Ở đâu | file:dòng |
| --- | --- | --- |
| Cắt markdown thành section/card/task; chuẩn hoá NFC trước khi băm; mọi trần được kiểm trước khi tích luỹ | `parse_markdown` | backend/app/sd/parser.py:366-373, backend/app/sd/parser.py:28-45 |
| Nhập lại tài liệu trong một transaction dưới advisory lock, không chạm tiến độ/lần thử | `_import` | backend/app/sd/admin.py:57-93 |
| Server tính `done` của section, Phase 2 và task (`unlocked` của section luôn `true`); response không có rubric/từ khoá | `_sections_state`, `_tasks_state` | backend/app/sd/learner.py:48-92 |
| PUT tiến độ chỉ thêm card đã đọc; không còn 409 khoá section | `put_progress` | backend/app/sd/learner.py:185-227 |
| `DELETE /api/sd/docs/{id}/progress` đặt lại tiến độ đọc (giữ bài đã nộp), khoá mọi section của doc trước khi xoá | `reset_progress` | backend/app/sd/learner.py:230-243 |
| Nộp bài: chấm từ khoá ngay, chụp rubric lúc nộp, tối đa 20 lần/task/24 giờ, câu trả lời ≤8KB | `submit_attempt` | backend/app/sd/attempts.py:85-140 |
| Một bản duy nhất cho học viên: `reviewed` (Claude) thắng `auto` (từ khoá) | `attempt_view` | backend/app/sd/attempts.py:53-75 |
| Claude đọc hàng đợi, đọc bài (kèm `answer_notice`), ghi feedback từng ý; ghi đè bản đã chấm cần `replace=true` | `review_queue`, `review_detail`, `submit_feedback` | backend/app/sd/attempts.py:194-309 |

```python
class Evaluator(Protocol):
    def evaluate(self, answer: str, rubric: list[dict]) -> dict:
```
(backend/app/sd/evaluator.py:23-24)

Phía Flutter, tab Design là tab thứ 5, thêm cuối ở ba nơi phải khớp index (branch của router, destination của `NavigationBar`, mục drawer); danh sách node trong lộ trình do `DuoPath` vẽ từ `done`/`unlocked` mà server trả, không tự tính; mọi section mở sẵn (backend/app/sd/learner.py:71) và mọi task Phase 2 mở cùng lúc khi Phase 1 xong (backend/app/sd/learner.py:77). Màn đọc vuốt snap theo card bằng `SdCardSnapPhysics` (mobile/lib/features/system_design/card_snap_physics.dart:23) và có menu mục lục (mobile/lib/features/system_design/reader_menu.dart:66) (mục chi tiết: docs/modules/sd-study.md:1).

### Ranh giới

Không dùng chung bảng hay hàng chờ duyệt với chế độ code: tiến độ và lần thử chỉ FK `users`, vì nhập lại tài liệu xoá rồi ghi lại section/task và FK cascade sẽ xoá tiến độ (backend/app/tables.py:236-238). Không gọi LLM trực tiếp: chấm sâu là việc của Claude qua MCP. Học viên chỉ có route `/api/sd`, luôn lọc theo `user.id` (backend/app/sd/learner.py:104, backend/app/sd/attempts.py:154-155). Chưa có màn admin trong app để nhập `.md`, và chưa có SRS cho card System Design.

## deploy — web + API cùng một origin trên VPS

### Là gì

Phần triển khai đưa app lên một VPS dùng chung với dịch vụ khác để có một link thử trên trình duyệt.
Trình duyệt và app iOS chỉ nói chuyện với một địa chỉ duy nhất, `https://codewithphuong.jacons-corp.com` (cổng 443 của nginx; iOS chặn HTTP thường nên bắt buộc HTTPS). nginx trả file web Flutter đã
build sẵn, và chuyển các đường dẫn của backend (`/content`, `/run`, `/api/*`) vào uvicorn đang nghe ở
`127.0.0.1:8100`. Vì web và API cùng "origin" (cùng giao thức, host, cổng) nên trình duyệt không áp luật
chặn gọi chéo nguồn (CORS) và backend không phải cấu hình gì thêm. Chi tiết vận hành xem
`docs/modules/deploy.md`.

### Cách hoạt động

Đường đi của một request:

```text
trình duyệt / app iOS --HTTPS--> nginx :443 (domain, cert Let's Encrypt)
  :80 và :8090 (link cũ http://<ip>:8090) -> 308 sang https://<domain>$request_uri
  nếu /content, /run hoặc /api/* -> uvicorn 127.0.0.1:8100 -> Postgres smart_coding_study
                                                   -> Judge0 CE công khai (chỉ /run)
  còn lại                -> /opt/smart-coding-study/web (file tĩnh, fallback index.html)
```

| Thứ | Ở đâu | file:dòng |
| --- | --- | --- |
| Địa chỉ công khai, hằng số `PUBLIC_URL="https://$DOMAIN"` (không còn override), truyền vào bản build web làm `API_URL` | biến `DOMAIN`, `PUBLIC_URL` | deploy/deploy.sh:16, deploy/deploy.sh:18 |
| Kiểm cert Let's Encrypt tồn tại trước mọi thay đổi; thiếu thì in lệnh certbot và dừng | `ssh ... test -f .../fullchain.pem` | deploy/deploy.sh:30-33 |
| Build web ở máy dev (VPS không có Flutter), rồi rsync lên server | bước 1-2 của script | deploy/deploy.sh:35-49 |
| User hệ thống riêng `smartcs`, không shell | `useradd` nếu chưa có | deploy/deploy.sh:59 |
| Role + DB Postgres riêng; mật khẩu sinh trên server, đi qua stdin của psql | `openssl rand` + `pg` | deploy/deploy.sh:62-80 |
| Bí mật chỉ nằm ở `/etc/smart-coding-study.env` (root:smartcs, 640), ghi file tạm rồi `mv` | `ENV_FILE` | deploy/deploy.sh:56-75 |
| Migration; nạp nội dung CHỈ khi DB rỗng (DB là nguồn chính, deploy không ghi đè); seed user | `alembic upgrade head`, `app.load_content --if-empty`, `app.seed_users` | deploy/deploy.sh:87-97 |
| Mật khẩu ban đầu chỉ vào `/etc/smart-coding-study/initial-passwords` (root, 0600, thư mục 0700); log deploy chỉ có số lượng; file dev bị loại khỏi rsync và xoá trên server | `INITIAL_PASSWORDS_FILE` | deploy/deploy.sh:45, deploy/deploy.sh:96-101 |
| Cài unit systemd, `enable` + `restart` | `smart-coding-study-api` | deploy/deploy.sh:112-116 |
| nginx: kiểm cert, `nginx -t` trước, lỗi thì trả site cũ và dừng, sạch mới `reload` | khối nginx | deploy/deploy.sh:118-133 |
| Smoke test qua HTTPS (`curl --resolve <domain>:443:127.0.0.1`): `/content` và `/` 200, `/api/me` không token 200 (chế độ mở) hoặc 401 (tắt), `:8090` phải 308; sai thì `rollback_site` trả site nginx cũ rồi reload | `curl` + `rollback_site` | deploy/deploy.sh:135-158 |
| Build iOS: kiểm Xcode + `DEVELOPMENT_TEAM`, `curl /content` qua HTTPS, `flutter build ipa --dart-define=API_URL=https://<domain>`, build number `yyMMddHH` | `deploy/ios-build.sh` | deploy/ios-build.sh:11-35 |

Cấu hình nginx có ba server: `:8090` và `:80` chỉ `return 308` sang https (308 giữ method/body của POST `/run`), `:443 ssl` chứa mọi location (deploy/nginx/smart-coding-study.conf:8-27). Server 443 mở `/content` và `/run` bằng `location =`, thêm
`location /api/` (timeout 15s) và `location /api/admin/` (body tới 4200k, timeout 60s vì admin gửi cả bộ nội dung);
mọi đường dẫn khác rơi vào `try_files ... /index.html` để router của web hoạt động:

```nginx
location = /run {
    proxy_pass http://127.0.0.1:8100;
    ...
    proxy_read_timeout 18s;
}
location / {
    try_files $uri $uri/ /index.html;
}
```

Unit systemd (deploy/systemd/smart-coding-study-api.service:7-19; uvicorn chạy `--proxy-headers` để rate limit theo IP thật, deploy/systemd/smart-coding-study-api.service:12) chạy uvicorn bằng user `smartcs`, nạp env từ
file bí mật, và siết quyền: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`,
`ReadOnlyPaths=/opt/smart-coding-study`. Ba mốc thời gian lồng nhau: HTTP timeout của runner 15s, nginx
`proxy_read_timeout` 18s (conf:56), client app 20s (mobile/lib/data/judge_client.dart:63). Body: nginx cho tới
80k (conf:33), lớn hơn giới hạn 64KB của backend để chính backend trả 413 (backend/app/main.py:30-31); riêng `/api/admin/` nginx 4200k, backend 4MB.

### Ranh giới

Chỉ chạm tài nguyên tên `smart-coding-study`/`smartcs` vì VPS dùng chung (deploy/deploy.sh:10-12). Chưa bật HSTS; token lưu localStorage 30 ngày. Không ký/upload app lên Apple: user tự làm theo deploy/IOS-TESTFLIGHT.md. `/run` vẫn
công khai và không giới hạn tốc độ: ai có link đều chạy được code, và code được chuyển tới Judge0 công khai nên IP VPS
có thể bị Judge0 chặn nếu bị lạm dụng (deploy/README.md:66-69).
Không có CI deploy: chỉ chạy tay từ máy có Flutter và SSH tới host `vps`.

## Giới hạn đã biết

Tiến độ đã lưu trên server theo user (xem mục Tài khoản + tiến độ); phần chưa bền là lỗi mạng giữa chừng: thay đổi chỉ được đẩy lại ở
lần đổi kế tiếp, không flush khi app vào nền. Về máy chấm, code học viên được gửi tới Judge0 CE
công khai của bên thứ ba, giới hạn theo IP: đủ cho dev local, không đủ production và không dùng cho dữ liệu nhạy cảm
(backend/app/runner.py:1-9). Bản web đã chạy trên VPS (xem mục deploy), còn mobile native chỉ chạy local — iOS simulator gọi `127.0.0.1`; điện thoại thật và Android
emulator (`10.0.2.2`, cleartext) chưa làm, và harness không chống gian lận (xem mục backend ở trên,
planning/crew/2026-10-11-exercise-tabs-judge/PLAN.md:192-200).

Còn lệch nhỏ giữa client và server đã biết, chưa sửa: client không chặn code dài hơn 8000 ký tự nên 422 hiện như
"máy chấm bận"; timeout client 20 giây có thể ngắn hơn trường hợp xấu nhất của server; `\r` lẻ làm lệch `lineOrigin`
(planning/crew/2026-10-11-exercise-tabs-judge/STATUS.md:47, mục SEAM M-1/M-2/M-8).

Nội dung và chấm bài cùng cần backend + Postgres đang chạy: lần mở app đầu tiên (chưa có cache) mà
không tới được server thì chỉ thấy màn lỗi + "Thử lại" (mobile/lib/app/content_gate.dart:21-32). Địa chỉ
là `API_URL` (mobile/lib/data/content_repository.dart:12-17); macOS thiếu `network.client` entitlement
và Android release thiếu `INTERNET`/`10.0.2.2` (planning/crew/2026-10-11-content-api-postgres/STATUS.md, mục SEAM).
Nội dung đổi khi người học đang mở bài thì ô code đã dựng giữ bản cũ; đọc `/content` có cửa sổ ABA
rất hẹp khi nạp lại đúng lúc đọc (backend/app/content_api.py:42-59; STATUS.md, Backlog T-04/05 và T-06).

Phần chưa tự quan sát: `flutter run` trên simulator hay thiết bị thật chưa chạy. Run 2026-10-11 kiểm e2e bằng
widget test tạm dùng `JudgeClient` thật gọi backend thật + Judge0 thật, chưa phải bấm tay trên simulator
(planning/crew/2026-10-11-exercise-tabs-judge/STATUS.md:28-31); phần "xem Solution → Stats không tính sạch" chỉ có
widget test, chưa chạy e2e.

Deploy VPS (run 2026-10-11-deploy-vps-web): `/run` có thể trả 504 khi tải cao vì hàng đợi Semaphore(4)
(backend/app/main.py:36) cộng 15s Judge0 vượt `proxy_read_timeout` 18s; domain lặp ở ba file (deploy/deploy.sh:16, deploy/ios-build.sh:11, deploy/nginx/smart-coding-study.conf:12) và cổng 8100 ở nginx/systemd, chỉ smoke test (phía server) bắt được lệch; thư mục tạm `/root/.smart-coding-study-deploy` không tự dọn nếu script chết giữa chừng
(deploy/deploy.sh:40). Review chéo bằng model họ khác không chạy được (Codex timeout 2 lần).

Hàng chờ duyệt (run content-review-queue, planning/crew/2026-10-11-content-review-queue/STATUS.md Backlog): `GET /api/admin/changes` không phân trang và `merge_pending` deepcopy mỗi mục chờ (O(k·N)); CLI `load_content --force` đổi thứ tự trong lúc có mục chờ thì approve áp lại thứ tự của draft; học viên đang mở app chỉ thấy bản duyệt khi tự refresh. Chi tiết `docs/modules/content-review.md`.

System Design (run 2026-10-12-system-design-mode, planning/crew/2026-10-12-system-design-mode/STATUS.md Backlog): màn đọc dựng cả tài liệu một lần (1000 card ≈ 12k element; trần server 3000 card, backend/app/sd/parser.py:33); `task.id` là slug tên task nên đổi tên task mất lần thử (backend/app/sd/parser.py:13); nhập lại làm Phase 1 mất `done` thì Phase 2 khoá lại và app báo sai lý do; điểm ✓/✗ từng ý cho phép dò từ khoá (tối đa 20 lần/ngày/task, backend/app/sd/attempts.py:33); còn rủi ro dư prompt injection ở lớp ngôn ngữ vì `answer` đi vào ngữ cảnh của Claude (backend/app/sd/attempts.py:176-180). Chi tiết: docs/modules/sd-study.md:1.

Tài khoản, tiến độ và quản trị (run users-progress-admin, planning/crew/2026-10-11-users-progress-admin/STATUS.md Backlog; HTTPS đã có từ run testflight-prep):
code học viên in giả dòng kết quả "passed" thì server vẫn ghi passed (backend/app/main.py:184-190); "xong bài" có thể lệch local/server khi token
hết hạn đúng lúc Run vì `/run` không trả 401 (reviews/SEAM.md mục 1); PUT tiến độ không tuần tự hoá và không flush khi app vào nền; lịch ôn theo
`block.id` mồ côi khi admin đổi nhãn ô; form admin chỉ cảnh báo 4 trong 12 luật nội dung; chưa có trang quản lý user. Test backend dùng chung một DB test nên hai
pytest song song đỏ lẻ tẻ (backend/README.md:54-60). Luồng UI thật trên Chrome/VPS chưa được reviewer tự chạy; e2e chạy bằng script API (20/20) và widget test.
