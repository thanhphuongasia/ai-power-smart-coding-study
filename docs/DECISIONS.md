# Decisions

## Vì sao khoá cấu trúc này

File này lưu các quyết định tiền đề (premise decisions) — lựa chọn có cân nhắc đánh đổi, chọn
một hướng và bỏ hướng khác, không phải mô tả "hệ thống hôm nay trông thế nào" (đó là việc của
`docs/ARCHITECTURE.md` và `docs/modules/*.md`). Tách riêng vì lý do chọn một hướng thường sống
lâu hơn bản thân code — code có thể đổi, nhưng câu hỏi "sao lúc đó không chọn X" vẫn cần trả lời
được nhiều tháng sau. File này **append-only**: chỉ thêm mục mới, hoặc sửa mục đã sai vì code đã
đổi (kèm commit ref) — không viết lại cho gọn.

## Cách áp dụng

Đọc lúc thiết kế feature mới trong cùng khu vực (đặc biệt là phase 2 của app mobile) để biết
những lựa chọn đã cân nhắc và bị bỏ — tránh đề xuất lại một hướng đã bị bác mà không biết vì sao.
Đọc trước khi quyết định "có nên thêm lại gói X đã bỏ ở phase 1 không".

## Giới hạn đã biết

File này không phải audit trail đầy đủ mọi lựa chọn nhỏ trong run — chỉ chưng cất các quyết định
có đánh đổi thật, đủ quan trọng để người sau cần biết trước khi đổi hướng.

## Nội dung

### Bỏ Dio/Retrofit/get_it/injectable ở phase 1 mobile app

**Quyết định**: không thêm các gói HTTP client (Dio/Retrofit) và dependency injection
(get_it/injectable) vào `mobile/pubspec.yaml` ở phase 1.

**Vì sao**: chưa có backend thật để gọi (toàn bộ nội dung bài học là seed tĩnh trong
`mobile/lib/data/seed.dart`), và Riverpod (đã dùng cho state management) đã đảm nhiệm việc
inject dependency (vd `clockProvider` bơm đồng hồ giả cho test) — thêm get_it/injectable là
một tầng DI thứ hai không cần thiết.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/PLAN.md, mục "Quyết định", điểm 2;
mobile/pubspec.yaml:33-42 (danh sách dependencies thật).

**Còn đúng tới khi nào**: tới khi phase 2 (issue #5, backend thật) quyết định app cần gọi API —
lúc đó phải quyết định lại có đưa Dio/Retrofit trở lại hay dùng `http` package đơn giản hơn.

**Cập nhật (run 2026-10-11-exercise-tabs-judge, commit 8b2ce52)**: phần "không HTTP client"
đã bị thay — app giờ gọi backend chấm bài bằng gói `http` (đơn giản, không Dio/Retrofit). Phần
"không get_it/injectable" vẫn đúng: Riverpod (`judgeClientProvider`) vẫn là DI duy nhất
(mobile/lib/data/judge_client.dart:149, mobile/pubspec.yaml: dependency `http`). Xem mục
"Chấm bài bằng Python thật qua backend" bên dưới.

**Cập nhật (run 2026-10-11-content-api-postgres, commit 11b3837)**: câu "toàn bộ nội dung bài học là
seed tĩnh trong `mobile/lib/data/seed.dart`" không còn đúng — `seed.dart` đã bị xoá, nội dung đến
từ `GET /content` (mobile/lib/data/content_repository.dart:72-88); xem mục "Nội dung học ở
Postgres" bên dưới. `http` vẫn là HTTP client duy nhất.

### Bỏ Hive (lưu tiến độ qua restart) ở phase 1

**Quyết định**: tiến độ làm bài (block đã xong, draft code, hint đã dùng) chỉ sống trong bộ nhớ
Riverpod (`ProgressController`), không ghi xuống đĩa bằng Hive hay cơ chế nào khác.

**Vì sao**: phase 1 ưu tiên chứng minh UX màn làm bài (đặc biệt autocomplete) trước khi đầu tư
vào lưu trữ bền vững — mất tiến độ khi kill app là chấp nhận được cho một bản demo.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/PLAN.md, mục "Quyết định", điểm 2 và mục
"Phạm vi phase 1" (liệt kê Hive ở "Ngoài phạm vi").

**Còn đúng tới khi nào**: tới phase 2 (issue #5) — đã liệt kê Hive là việc cần làm ở đó.

**Đã lỗi thời (commit c17baa1)**: tiến độ giờ lưu trên server theo user, không còn chỉ ở RAM — xem mục "Tiến độ theo user lưu trên server" cuối file.

### ~~Run = so khớp đáp án đã chuẩn hoá, không chạy Python thật~~ (SUPERSEDED)

**SUPERSEDED bởi run 2026-10-11-exercise-tabs-judge (commit 8b2ce52)**: Run giờ gửi code đã ghép lên
backend và chấm bằng Python thật + unit test — xem "Chấm bài bằng Python thật qua backend" ở dưới.
`runBlock`/`normalizeCode` còn trong repo nhưng chỉ phục vụ chế độ ôn tập "gõ lại" và gợi ý phụ
"kiểm tra lại ô này" (mobile/lib/features/review/review_screen.dart:151,
mobile/lib/features/exercise/code_tab.dart:177-189). Nội dung gốc giữ lại để biết vì sao từng chọn vậy:

**Quyết định**: nút Run trong màn Cell không thực thi code Python — nó chuẩn hoá code người học
gõ (`normalizeCode`) rồi so với danh sách `acceptedAnswers` viết sẵn trong seed cho từng block.

**Vì sao**: dựng sandbox chạy Python thật an toàn trên thiết bị di động (hoặc gọi server chấm
bài) là một hạng mục lớn, vượt phạm vi một app demo phase 1 tập trung vào UX làm bài.

**Đánh đổi đã chấp nhận**: cách viết đúng nhưng khác cấu trúc code với mọi `acceptedAnswers` đã
liệt kê sẽ bị chấm sai. Bù lại, `normalizeCode` đã bỏ qua khác biệt không quan trọng (khoảng
trắng thừa, nháy đơn/kép) để giảm bớt false negative do lỗi gõ vặt.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/PLAN.md, mục "Quyết định", điểm 3;
mobile/lib/domain/answer_checker.dart:11-90.

### Bundle font thay vì dùng gói `google_fonts`

**Quyết định**: hai font family (IBM Plex Sans, JetBrains Mono) được bundle sẵn dạng `.ttf`
trong `mobile/assets/fonts/` và khai trực tiếp trong `pubspec.yaml`, thay vì dùng gói
`google_fonts` như PLAN.md ban đầu định.

**Vì sao**: `google_fonts` tải font qua mạng lúc chạy lần đầu — test chạy trong môi trường
không có mạng (CI, sandbox) dễ fail, và đi ngược hướng "app hoạt động không cần mạng" mà phase 1
đang nhắm tới (không có backend).

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/DEVIATIONS.md, dòng đầu tiên ("Plan: giữ
`google_fonts`"); mobile/pubspec.yaml:64-76.

### Overtype/auto-close xử lý trong `set value` của controller, không trong `CodeModifier`

**Quyết định**: logic overtype (gõ trùng dấu đóng sẵn có thì nhảy qua thay vì chèn thêm) và xoá
cặp ngoặc rỗng được implement bằng cách override `set value` của một `CodeController` con
(`_PythonCodeController`), không phải bằng một `CodeModifier` như PLAN.md ban đầu định.

**Vì sao**: viết logic này trong `CodeModifier` khiến package `flutter_code_editor` (bên thứ ba)
tự ném `RangeError` khi modifier trả về text không đổi — đã thử và xác nhận lỗi trước khi đổi
hướng.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/DEVIATIONS.md, dòng "Plan: overtype qua
CodeModifier"; mobile/lib/features/exercise/code_input.dart:572-573 (override `set value`; `_overtype` từ dòng 585; số dòng cập nhật ở run 2026-10-11-exercise-tabs-judge).

### `start()` của session phải idempotent (không reset đồng hồ mỗi lần vào block mới)

**Quyết định**: gọi `SessionController.start()` nhiều lần trong cùng một phiên (vd từ
`initState` của mỗi block) không reset đồng hồ về 0, trừ khi phiên trước đó đã timeout hoặc
chưa từng khởi động.

**Vì sao**: thiết kế ban đầu (T-04) cho `start()` luôn reset — đúng theo contract của riêng
task đó. Khi ghép với T-06 (mỗi block gọi lại `start()` lúc mount màn hình), đồng hồ cả bài bị
nhảy về `00:00` mỗi lần chuyển block — lỗi mối nối giữa hai task đã review PASS riêng lẻ, phát
hiện và sửa bằng task hẹp T-04b.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/STATUS.md, dòng "T-04b start() idempotent
(timer reset mỗi block — lỗi mối nối T-04↔T-06)";
mobile/lib/features/exercise/session_controller.dart:184-205 (số dòng cập nhật ở run 2026-10-11-exercise-tabs-judge).

### Chấm bài bằng Python thật qua backend, không còn so chuỗi (thay quyết định "Run = so chuỗi" và "không backend")

**Quyết định**: nút Run gửi code đã ghép (template khoá + các ô học viên) tới backend FastAPI
`POST /run`; backend chạy harness + unit test của bài bằng Python thật rồi trả `passed/failed/
error/timeout`. Test case và lời giải tham chiếu chỉ nằm ở backend (`backend/app/exercises.json`),
app không giữ.

**Vì sao**: so chuỗi chấm sai mọi cách viết đúng nhưng khác `acceptedAnswers`, và không cho biết
test nào hỏng. Backend riêng cũng để về sau tự host được; client không sửa được test.

**Đánh đổi đã chấp nhận**: app cần backend chạy (mặc định `http://127.0.0.1:8000`, đổi bằng
`--dart-define=JUDGE_URL`); chỉ chạy local trên simulator iOS (`NSAllowsLocalNetworking`);
backend chưa chạy thì Run báo "không kết nối được máy chấm", không chấm được.

**Cập nhật (run 2026-10-11-content-api-postgres, commit 11b3837)**: hai chi tiết trong mục này đã
đổi. (1) Test case + lời giải không còn ở `backend/app/exercises.json` (đã xoá) mà ở Postgres, nạp từ
`backend/content/content.json` (backend/app/load_content.py:98-123, backend/app/content_api.py:141-149).
(2) `--dart-define=JUDGE_URL` đã được thay bằng `--dart-define=API_URL` dùng chung cho `/content` và
`/run` (mobile/lib/data/content_repository.dart:9-17, mobile/lib/data/judge_client.dart:7,65).
Phần còn lại của quyết định (chấm bằng Python thật, app không giữ test) vẫn đúng.

**Nguồn**: planning/crew/2026-10-11-exercise-tabs-judge/PLAN.md, "Quyết định thiết kế" 1, 10;
backend/app/main.py:89-130; mobile/lib/data/judge_client.dart:57-107; mobile/ios/Runner/Info.plist:28-31.

### Máy chấm qua interface `CodeRunner`; dùng Judge0 CE công khai bây giờ, tự host sau

**Quyết định**: backend chỉ phụ thuộc `CodeRunner` (một hàm `run(source, stdin) -> Execution`).
Bản duy nhất hiện có là `Judge0Runner` gọi `https://ce.judge0.com` (Python 3.12, id 100). Đổi sang
self-host có hai đường không đụng harness/API/app: tự host Judge0 (chỉ đổi `JUDGE0_URL`) hoặc viết
`DockerRunner` cùng interface (đổi `CODE_RUNNER`).

**Vì sao**: cần chấm được ngay để làm UX, nhưng không muốn khoá vào một máy chấm. Chưa viết
`DockerRunner` vì chưa có lần dùng thứ hai thật (luật "abstraction khi có lần hai").

**Đánh đổi đã chấp nhận**: code học viên đi qua server Judge0 công khai của bên thứ ba, giới hạn
tần suất theo IP — đủ cho dev local, không đủ production (khi đó phải tự host). Backend cũng giới
hạn 4 request đồng thời tới máy chấm.

**Nguồn**: backend/app/runner.py:1-9,42-43,128-136; backend/app/main.py:31-32;
planning/crew/2026-10-11-exercise-tabs-judge/PLAN.md, "Quyết định thiết kế" 2 và "Giới hạn đã biết".

### Harness độc lập máy chấm, test case dạng JSON

**Quyết định**: `backend/app/harness.py` là một chương trình thư viện chuẩn đọc stdin JSON
`{code, function, cases}` và in đúng một dòng `__JUDGE_RESULT__{json}`; backend gửi harness làm
`source`, payload làm `stdin`. Test case là JSON: `{"args": [...], "expect": {"return": v}}` hoặc
`{"args": [...], "expect": {"arg": i, "value": v}}` (hàm sửa tham số tại chỗ).

**Vì sao**: máy chấm nào cũng chỉ cần "chạy python với stdin" nên đổi runner không đổi cách chấm;
JSON cho phép hiển thị "input / mong đợi / nhận được" thay vì chỉ đúng/sai.

**Đánh đổi đã chấp nhận**: code học viên chạy cùng tiến trình với harness nên cố tình in dòng kết
quả giả hoặc monkey-patch `json.dumps` thì tự mở khoá bài của mình — không chống gian lận (review
external gắn Critical, bị bác vì đã khai trong PLAN). Harness so bằng `==` nên `True == 1` coi là
bằng nhau. Case ném exception thì dừng, các case sau không chạy.

**Nguồn**: backend/app/harness.py:1-16,48-109; backend/app/exercises.json:1-5;
planning/crew/2026-10-11-exercise-tabs-judge/DEVIATIONS.md (dòng "T-02 review external").

**Cập nhật (commit 11b3837)**: dạng JSON của test case vẫn đúng; chỉ nơi lưu đổi — `exercises.json`
đã xoá, case nằm ở trường `judge.cases` trong `backend/content/content.json:197` (ví dụ split-chunks)
và cột `judge_cases` của bảng `exercises` (backend/app/tables.py:50-66).

### Ghép ô TODO ở client (Dart), không ở backend

**Quyết định**: template của bài chứa dòng `# TODO A`, `# TODO B`...; `mergeCells` thay mỗi dòng
marker bằng nội dung ô (đã dedent) thụt theo đúng thụt lề của dòng marker, và trả thêm `lineOrigin`
(dòng nào đến từ ô nào). Backend nhận code đã ghép và trả `error.line` 1-based; client tra
`lineOrigin[line-1]` để tô đúng ô.

**Vì sao**: học viên không phải gõ thụt lề; ghép ở một chỗ duy nhất thì ánh xạ dòng lỗi → ô chỉ có
một nơi đúng.

**Nguồn**: mobile/lib/domain/merge.dart:28,80-102; mobile/lib/features/exercise/run_result_view.dart:23-30.

### "Bài đã xong" chỉ có một nguồn: `ExerciseProgress.passed`

**Quyết định**: `passed` chỉ được đặt khi backend trả `passed` (`markPassed`). `completedBlocks` cũ
thành getter suy ra (`passed ? totalBlocks : 0`); "đang làm dở" = `!passed` và có draft không rỗng.
Mọi nơi hiện/đếm tiến độ (ExerciseRow, Home, Stats, Review, Practice) đọc từ đây.

**Vì sao**: trước đó "xong" suy từ đếm block gõ đúng; có hai nguồn thì Run pass mà Home vẫn ghi "Mới".

**Nguồn**: mobile/lib/features/exercise/session_controller.dart:29-52,93-98;
mobile/lib/features/exercise/code_tab.dart:127-130; mobile/lib/features/exercise/session_providers.dart:28-42.

### Khoá bài kế tiếp trong cùng `CodeFile`, một quy tắc duy nhất

**Quyết định**: bài k trong một `CodeFile` mở khi k = 0 hoặc bài k-1 (cùng file) đã passed; bài đã
passed luôn mở; bài nằm ở nhiều file mở nếu mở ở bất kỳ file nào chứa nó; không khoá xuyên
file/topic. `ExerciseRow`, màn bài và nút "Bài tiếp theo" cùng dùng `isExerciseUnlocked`.

**Vì sao**: bản đầu của run để ExerciseRow và ExerciseScreen khoá khác nhau (bài passed khi bài trước
chưa pass) — sửa bằng task T-11, gom về một hàm.

**Giới hạn**: `nextExerciseAfter` chỉ xét file ĐẦU TIÊN chứa bài, còn `isExerciseUnlocked` xét mọi file
— bài dùng chung nhiều file có thể cho "Bài tiếp theo" khác phạm vi khoá (SEAM M-5, chưa sửa).

**Nguồn**: mobile/lib/domain/progression.dart:1-44; mobile/lib/features/exercise/session_providers.dart:44-52;
mobile/lib/features/exercise/exercise_screen.dart:38-40; planning/crew/2026-10-11-exercise-tabs-judge/DEVIATIONS.md (dòng INV-08).

### Ô đã xem lời giải không tính điểm; không có nút "chép vào ô"

**Quyết định**: mở lời giải một ô ghi nhãn vào `solutionViewed`; Stats không tính ô đó là "sạch" (cùng
điều kiện không dùng gợi ý), Review kéo hạn ôn của thẻ đó về sớm. Học viên vẫn phải tự gõ ô đó.

**Vì sao**: xem lời giải là cách học hợp lệ nhưng không được tính như tự làm được.

**Chưa chốt (backlog T-07)**: thẻ ôn của ô đã xem lời giải bị kéo hạn về ngày mai vĩnh viễn → ôn mỗi
ngày mãi; reviewer đề nghị hỏi user có muốn vậy không — chưa có câu trả lời.

**Nguồn**: mobile/lib/features/exercise/solution_tab.dart:59-65; mobile/lib/features/stats/stats_screen.dart:28-41;
mobile/lib/features/review/review_controller.dart:122-148.

### Nội dung học ở Postgres; `content.json` là nguồn soạn, app không còn chứa nội dung

**Quyết định**: toàn bộ nội dung học (theme → topic → file → exercise → ô TODO, challenge, template,
gợi ý, lời giải từng ô) cùng phần chấm (`judge.solution`, `judge.cases`) nằm trong Postgres, quản lý
schema bằng Alembic và truy cập bằng SQLAlchemy **sync** (psycopg 3). File soạn duy nhất là
`backend/content/content.json`; `seed.dart` (nội dung viết cứng trong Dart) và `exercises.json` bị xoá.
Phần còn lại của `mobile/lib/data/` là `demo_seed.dart`, chỉ giữ tiến độ demo (bài đã pass, nháp,
hoạt động, lịch ôn, Admin PendingContent), không có nội dung học.

**Vì sao**: thêm/sửa bài không còn phải sửa Dart và build lại app; test case và nội dung ở cùng một
nơi nên id bài ở `/content` và `/run` luôn khớp. SQLAlchemy sync vì chỉ ~5 bài, không cần async DB;
`/run` bọc lệnh tra DB bằng `run_in_threadpool` để không chặn event loop.

**Đánh đổi đã chấp nhận**: backend giờ cần Postgres chạy (mặc định
`postgresql+psycopg://localhost:5432/smart_coding_study`, đổi bằng `DATABASE_URL`). Sửa thẳng trong DB sẽ
bị lần nạp sau ghi đè — nguồn soạn là `content.json`. Chưa có màn soạn nội dung. Tiến độ khoá theo
`exercise.id` + `block.label` nên đổi id trên server làm tiến độ cũ mồ côi.

**Nguồn**: backend/app/db.py:11-26; backend/app/tables.py:18-108; backend/migrations/versions/0001_content_tables.py;
backend/app/main.py:106-114; backend/README.md:1-60; mobile/lib/data/demo_seed.dart:1-8;
planning/crew/2026-10-11-content-api-postgres/PLAN.md, "Quyết định thiết kế" 1, 2, 6, 7.

**Đã đổi một phần (commit c17baa1)**: `content.json` không còn là nguồn soạn — DB là nguồn chính, admin sửa qua `/api/admin/content`, deploy chỉ nạp khi DB rỗng; đã có màn soạn nội dung; `demo_seed.dart` bị xoá. Xem "DB là nguồn chính của nội dung" cuối file. Phần còn lại (Postgres + Alembic + SQLAlchemy sync) vẫn đúng.

### Nạp nội dung: thay toàn bộ trong một transaction, kiểm hình dạng bằng pydantic

**Quyết định**: `python -m app.load_content [path]` đọc `content.json`, kiểm, xoá hết bảng nội dung rồi
ghi lại **trong một transaction**; lỗi giữa chừng thì rollback, DB giữ bản cũ. `version` =
sha256 của phần công khai (bỏ `judge`), nên cùng nội dung thì cùng version (idempotent) và `version`
được ghi cùng transaction với dữ liệu. Việc kiểm hình dạng dùng đúng bộ model pydantic (strict,
`extra="forbid"`) mà `GET /content` dùng làm `response_model`.

**Vì sao**: nạp từng phần dễ để lại bài trùng hoặc bài đã xoá khỏi file mà vẫn còn trên `/content`.
Dùng chung một bộ model cho "nạp" và "trả ra" vì run đã bị sót một lỗ: ban đầu `load_content` chỉ
kiểm id/quan hệ, nên `content.json` sai kiểu vẫn nạp được, `/content` trả 200 nhưng app parse lỗi và
âm thầm dùng cache (correction T-10). Model `strict` vì Dart kiểm kiểu nghiêm (`"1"` không thành `1`).

**Đánh đổi đã chấp nhận**: xoá-rồi-ghi lại khoá bảng trong lúc nạp; với 5 bài thì chấp nhận được.
`validate` chưa kiểm vài trường (ví dụ `indent_level` âm vẫn qua).

**Nguồn**: backend/app/load_content.py:1-5,37-39,46-95,98-156,159-173; backend/app/content_schema.py:1-102;
planning/crew/2026-10-11-content-api-postgres/DEVIATIONS.md (dòng "Plan không có T-10").

**Bổ sung (commit c17baa1)**: `load_content` giờ cũng là đường ghi duy nhất của admin, có khoá `pg_advisory_xact_lock` và bộ luật nội dung mở rộng (`content_rules.py`); CLI bắt buộc `--if-empty` hoặc `--force`.

### `GET /content` công khai, không trả `judge`; đọc lại khi version đổi giữa chừng

**Quyết định**: `GET /content` trả cả cây trong một lần (`{version, themes, exercises}`), không bao giờ
chứa `judge_solution`/`judge_cases`. Việc dựng payload là 6 SELECT cố định (một query mỗi bảng) kẹp giữa hai
lần đọc `version`; nếu `version` đầu ≠ cuối (một lần nạp lại commit xen giữa) hoặc cây lệch
(`KeyError`) thì đọc lại, tối đa 3 lần. Chưa nạp nội dung lần nào → `503 content_not_loaded`;
DB không kết nối được → `503 database_unavailable`.

**Vì sao**: ở READ COMMITTED, 6 câu SELECT riêng lẻ có thể thấy hai bản khác nhau nếu nạp lại xen
vào. Vì `version` được ghi cùng transaction với dữ liệu, so version đầu/cuối là cách rẻ hơn mở
transaction REPEATABLE READ.

**Đánh đổi đã chấp nhận**: cửa sổ hẹp ABA (A→B→A đúng lúc đọc) không bị bắt; đọc không ổn định 3 lần
liên tiếp thì `RuntimeError` → 500; lỗi cạn pool (`TimeoutError`) chưa thành 503. REPEATABLE READ
sẽ đóng triệt để (backlog T-06).

**Nguồn**: backend/app/content_api.py:34-59,141-171; backend/app/main.py:69-78; backend/app/content_schema.py:80-85;
planning/crew/2026-10-11-content-api-postgres/STATUS.md (Backlog T-06 r2).

### `/run` đọc test case từ DB bằng session ngắn, trả kết nối trước khi chờ máy chấm

**Quyết định**: `/run` tra `function` + `cases` của bài qua `get_judge_lookup`: mở một `SessionLocal`
riêng, đọc rồi đóng ngay, rồi mới gửi cho máy chấm. Không dùng session per-request giữ suốt request.

**Vì sao**: máy chấm mất vài giây; giữ session suốt request thì mỗi `/run` chiếm một kết nối pool trong
lúc chờ, nhiều request đồng thời làm cạn pool và `/content` chết theo.

**Đánh đổi đã chấp nhận**: bài không có → 404 `exercise_not_found`, nhưng nếu DB chưa nạp gì thì
`/run` báo 503 `content_not_loaded` (không báo nhầm "không có bài"). Timeout kết nối DB 5s trùng với
timeout client 5s của app.

**Nguồn**: backend/app/content_api.py:141-166; backend/app/main.py:106-120; backend/app/db.py:19.

### App tải nội dung qua API, cache `shared_preferences`, `ContentGate` đứng ngoài app widget

**Quyết định**: `ContentRepository.load()` thử `GET /content` (timeout 5s) trước; thành công thì ghi
cache (body + version); mọi lỗi (mạng, timeout, HTTP ≠ 200, JSON/schema hỏng) rơi về cache; không có cache
dùng được thì ném `ContentUnavailable`. Cache chỉ được ghi khi bản tải về parse được. `ContentGate`
bọc `SmartCodingStudyApp` ở `main()`: chờ → màn tải, lỗi → màn lỗi + "Thử lại", có nội dung → dựng app, kèm
banner "Đang dùng nội dung đã lưu" nếu nguồn là cache. `contentIndexProvider` không có giá trị mặc
định; `ProviderScope` ở gốc override nó bằng `contentProvider.requireValue.content`, nên mọi nơi trong app
đọc nội dung qua một provider đồng bộ.

**Vì sao**: 11 file `lib` đọc nội dung đồng bộ; bọc cả app bằng một cổng thay vì đổi mọi chỗ đọc sang
`AsyncValue`. Cổng nằm ngoài app widget và có cấu trúc cây cố định (child luôn là phần tử thứ 2 của
`Column`, chỉ ô banner đổi) để "Thử lại" từ cache sang mạng không unmount app — người học không mất
chữ đang gõ (review T-08 F1, correction T-08b).

**Đánh đổi đã chấp nhận**: mọi lỗi `/content` đều thành cùng một banner "dùng cache"; nội dung đổi
khi đang mở bài thì ô code đã dựng giữ bản cũ (CodeTab dựng ô ở `initState`); mở bài đã bị xoá sau
"Thử lại" → `StateError`. Cache ghi body rồi version nên kill giữa chừng có thể lệch (version chưa ai đọc).

**Nguồn**: mobile/lib/data/content_repository.dart:40-115; mobile/lib/data/content_providers.dart:9-35;
mobile/lib/app/content_gate.dart:12-73; mobile/lib/main.dart:10-21;
planning/crew/2026-10-11-content-api-postgres/DEVIATIONS.md (dòng "Plan không có T-08b"), reviews/SEAM.md.

### Một biến `API_URL` thay `JUDGE_URL`

**Quyết định**: app có một địa chỉ backend `API_URL` (mặc định `http://127.0.0.1:8000`) dùng chung cho
`/content` và `/run`; `JudgeClient` lấy địa chỉ từ cùng hàm `apiBaseUrl()` với `ContentRepository`.
`JUDGE_URL` bị bỏ.

**Vì sao**: `/content` và `/run` giờ là cùng một server; hai biến dễ trỏ lệch nhau.

**Đánh đổi đã chấp nhận**: chỉ chạy local trên iOS simulator — macOS thiếu `network.client` entitlement,
Android release thiếu `INTERNET` và `10.0.2.2` (ngoài phạm vi run).

**Nguồn**: mobile/lib/data/content_repository.dart:9-17; mobile/lib/data/judge_client.dart:7,65;
backend/README.md:22-23; planning/crew/2026-10-11-content-api-postgres/STATUS.md (Backlog SEAM).

### Deploy lên VPS dùng chung: một origin qua nginx, backend riêng user, bí mật một file

**Quyết định** (run 2026-10-11-deploy-vps-web):
- Web Flutter và API cùng origin `http://<ip>:8090`: nginx phục vụ web tĩnh, chỉ proxy `= /content` và
  `= /run` vào uvicorn `127.0.0.1:8100` — không CORS (deploy/nginx/smart-coding-study.conf:18-39).
- Backend chạy dưới user hệ thống `smartcs` (không shell), systemd siết quyền (`NoNewPrivileges`,
  `ProtectSystem=strict`, `ReadOnlyPaths`...) (deploy/systemd/smart-coding-study-api.service:7-19).
- DB và role Postgres riêng (`smart_coding_study`/`smartcs`); mọi bí mật chỉ ở
  `/etc/smart-coding-study.env` (root:smartcs, 640), mật khẩu sinh trên server và đi qua stdin psql
  (deploy/deploy.sh:37-61).
- `deploy.sh` idempotent: env/DB chỉ tạo khi chưa có; nginx `nginx -t` trước, lỗi thì trả site cũ và không
  reload (deploy/deploy.sh:45,59,85-94).
- Build web ở máy dev vì VPS không có Flutter (deploy/deploy.sh:17-18).

**Vì sao**: VPS dùng chung với dịch vụ khác nên mọi thứ phải cô lập theo tên `smart-coding-study`/`smartcs`
và không được làm hỏng nginx chung; cùng origin loại bỏ cấu hình CORS và cho đúng một link thử.
Review chặn hai lỗi trước khi deploy: mật khẩu lộ qua argv/log và thư mục `/tmp` dùng chung
(commit 7d8a5f5, 458ce00).

**Rủi ro đã chấp nhận (tạm thời)**: link công khai, không mật khẩu, không `limit_req` trên `/run`, code
chuyển tới Judge0 công khai nên IP VPS có thể bị chặn; HTTP thường, chưa domain/HTTPS
(deploy/README.md:36-41). Không có second opinion khác họ model (Codex timeout 2 lần).

**Nguồn**: deploy/deploy.sh:1-108; deploy/README.md:11-41; planning/crew/2026-10-11-deploy-vps-web/DEVIATIONS.md,
reviews/SEAM.md.

**Bổ sung (commit c17baa1)**: nginx proxy thêm `location /api/` và `location /api/admin/`; deploy nạp nội dung chỉ khi DB rỗng và seed user; link không còn "không mật khẩu" cho phần `/api/*` (nhưng `/content`, `/run` vẫn công khai; vẫn HTTP thường).

**Cập nhật (commit a25b41d)**: origin không còn `http://<ip>:8090` mà là `https://codewithphuong.jacons-corp.com` (nginx 443); `:8090` và `:80` chỉ trả 308 sang domain — xem mục "HTTPS bằng domain riêng" cuối file. Các nhận xét "HTTP thường" ở mục này là hiện trạng trước commit đó.
### Module lồng nhau = `topics.parent_id` + `position` theo thứ tự duyệt trước (preorder)

**Quyết định**: module con là hàng `topics` tự tham chiếu qua `parent_id` (FK về `topics.id`, CASCADE, nullable);
`content.json` thêm key `modules` (đệ quy, rỗng = `[]`) vào mỗi topic. `position` là số thứ tự preorder (cha trước con)
trong cả theme, nên ràng buộc unique `(theme_id, position)` giữ nguyên. Tên bảng/route (`theme`, `topic`) không đổi.

**Vì sao**: `/content` vẫn đọc topics bằng một SELECT rồi ghép cha–con trong bộ nhớ, số query không tăng; không cần
truy vấn đệ quy hay bảng phụ. Đổi tên bảng/route chỉ để khớp từ "module" tốn nhiều hơn lợi.

**Đánh đổi đã chấp nhận**: thứ tự anh em chỉ đúng nếu loader là nơi duy nhất ghi; `/content` không kiểm module con
cùng theme với cha (sửa DB tay có thể sai). Client mất vòng lặp 4 tầng cố định: mọi chỗ duyệt cây phải đi qua
`Theme.allFiles`/`allTopics`/`Topic.allModules`.

**Nguồn**: backend/app/tables.py:5,31-41; backend/app/load_content.py:42-46,184-191; backend/app/content_api.py:72-80,95-107;
mobile/lib/domain/models.dart:60-75,116-135; planning/crew/2026-10-11-project-tree-airline/PLAN.md (Quyết định thiết kế 1).

### `class_name` là thuộc tính của bài, không phải bảng

**Quyết định**: bài method mang `exercises.class_name` (nullable; `null` = hàm rời). Template của bài chứa cả khung class
(method khác là code khoá). Màn Topic nhóm bài theo class bằng cách so `className` của hai bài liền kề. Mở khoá/bài kế
vẫn theo file, class chỉ là nhóm hiển thị.

**Vì sao**: đơn giản nhất mà đủ cho "file → class → method"; chưa có dữ liệu nào cần gắn vào class ngoài tên. Tách bảng
`classes` khi có nhu cầu thật (vd metadata riêng cho class).

**Đánh đổi đã chấp nhận**: tên class lặp ở nhiều bài; hai bài cùng class nhưng không liền kề sẽ có hai tiêu đề class.

**Nguồn**: backend/app/tables.py:67; backend/app/content_schema.py:52; mobile/lib/domain/models.dart:316-320;
mobile/lib/features/browse/topic_detail_screen.dart:55-64; PLAN.md (Quyết định thiết kế 2, 5).

### Case chấm dạng kịch bản (`steps`/`call`/`expect return|raises`) và kiểm lúc nạp

**Quyết định**: ngoài hai dạng case `args`, harness nhận case kịch bản `{steps?, call, expect}` với `expect` là
`{"return": v}` hoặc `{"raises": "TênLỗi"}`. Mỗi case chạy `exec` các step rồi `eval` `call` trong bản sao nông của
namespace; `raises` so tên trong MRO của exception. Payload `/run` thêm `class_name`; harness báo "Không tìm thấy
class/method" nếu thiếu. `load_content.validate` chặn trước: step/call phải compile được, `expect` phải có `return`
hoặc `raises`, và bài có `class_name` chỉ được có case dạng `call`.

**Vì sao**: method cần đối tượng đã dựng nên không gọi được bằng `func(*args)`. Lỗi soạn bài mà lọt tới harness sẽ hiện
cho người học như thể code của họ sai, nên bắt ở lúc nạp. `steps`/`call` là nội dung do tác giả viết trong DB, không
bao giờ đến từ client.

**Đánh đổi đã chấp nhận**: bản sao nông nên thuộc tính gán lên class rò giữa các case (chưa có test); `SystemExit` trong
`steps` chưa test. Case `expect.raises` không dừng bài, khác case `return` ném exception (dừng).

**Nguồn**: backend/app/harness.py:48-87,123-148; backend/app/main.py:118-125; backend/app/load_content.py:49-67,111-117;
backend/app/content_api.py:29,164; PLAN.md (Quyết định thiết kế 3), STATUS.md (Backlog harness).

### Vị trí ô (hàm/method/class) suy từ template, không lưu

**Quyết định**: nhãn "trong hàm / trong method / trong class" ở tiêu đề ô do `cellLocation` suy từ template: tìm dòng
marker, lấy dòng cha gần nhất có thụt lề nhỏ hơn rồi phân loại. Thay cách cũ ánh xạ từ `indent_level` (sai cho method
vì thân method đã ở indent 2). `indent_level` vẫn còn như metadata.

**Vì sao**: template đã chứa toàn bộ cấu trúc nên không cần dữ liệu thứ hai có thể lệch với nó.

**Đánh đổi đã chấp nhận**: heuristic thụt lề sai ở ca lạ (comment `#` thụt ít hơn, `async for/with`, header nhiều dòng,
`self.x` gán ở ô trước); nhãn không kèm tên method cho vừa tiêu đề ô 375px.

**Nguồn**: mobile/lib/domain/merge.dart:135-175; mobile/lib/features/exercise/code_tab.dart:444;
mobile/lib/features/exercise/cell_editor_page.dart:18,113; DEVIATIONS.md của run (dòng "nhãn vị trí").

### Hạ cấp migration 0002 mất dữ liệu cây/class: chấp nhận

**Quyết định**: `downgrade` của migration 0002 bỏ `topics.parent_id` và `exercises.class_name`, không bảo toàn quan hệ cha–con
hay tên class.

**Vì sao**: bảng nội dung chỉ là bản dẫn xuất của `backend/content/content.json`; chạy lại `python -m app.load_content` là có
lại đủ. Bảo toàn dữ liệu ở downgrade là công sức cho thứ tái tạo được.

**Đánh đổi đã chấp nhận**: hạ cấp rồi quên nạp lại thì cây mất tầng. Không áp cho dữ liệu không dẫn xuất từ file (nếu sau
này bảng nội dung có dữ liệu nhập tay thì quyết định này phải xét lại).

**Nguồn**: backend/migrations/versions/0002_module_tree_class.py:22-35.

### Sơ đồ class soạn tay theo theme, lưu ở `themes.diagram` (JSONB)

**Quyết định**: mỗi theme có key bắt buộc `diagram = {classes[{name,file,attributes[{name,type,group}],methods[]}], relations[{from,to,kind,label,via[]}]}`, soạn tay trong `content.json`, lưu một cột JSONB `themes.diagram` (migration 0003) và phát nguyên trạng trong `/content`. Theme chưa có sơ đồ phải ghi `{"classes": [], "relations": []}`. `kind` chỉ nhận association/aggregation/composition/dependency; `group` chỉ nhận core/support.

**Vì sao**: quan hệ giữa class không suy ra được từ code mẫu (vd FlightService dùng SimpleNamespace thay vì Flight thật), nên phải soạn tay. JSONB nằm sẵn trong SELECT `themes` nên `/content` không thêm query.

**Đánh đổi đã chấp nhận**: sơ đồ có thể lệch code; test hợp đồng chỉ chặn thuộc tính/method không có thật (xem mục INV-02 bên dưới), không chặn quan hệ hay nhãn sai nghĩa. Hạ cấp 0003 bỏ cột, chấp nhận vì nội dung là bản dẫn xuất của `content.json`.

**Nguồn**: backend/app/content_schema.py:76-113; backend/app/tables.py:29-30; backend/migrations/versions/0003_theme_diagram.py:22-38; backend/app/content_api.py:118; mobile/lib/domain/models.dart:53,95.

### Ngữ nghĩa `via` của quan hệ và cách hiện trên app

**Quyết định**: `via` là danh sách method của class `from` tác động lên class `to`. Loader bắt `via` phải là tập con methods của `from`, `from`/`to` phải là class có trong sơ đồ, tên class không trùng. Trên app, class của bài hiện đủ hộp; class đối diện hiện thu gọn: nếu nó là `from` thì chỉ liệt kê các method trong `via`, nếu là `to` thì chỉ tên (kèm nhãn quan hệ). Quan hệ mà bản code mẫu đã rút gọn thì nhãn nói thẳng điều đó (vd SeatMap → Flight có `via` rỗng, nhãn "thiết kế; bản rút gọn chưa giữ mã chuyến"); quan hệ FlightController → FlightService là association vì service được tiêm qua `__init__`.

**Vì sao**: code mẫu mỗi bài là bản rút gọn độc lập, sơ đồ thể hiện quan hệ thiết kế; nhãn phải nói rõ chỗ lệch để người học không hiểu nhầm.

**Đánh đổi đã chấp nhận**: Booking/SeatMap → Flight có thể là dependency theo UML chặt (nhãn đã nói rõ); loader chưa kiểm `via` rỗng/trùng, thuộc tính trùng, quan hệ tự trỏ (planning/crew/2026-10-11-class-diagram/STATUS.md, Backlog).

**Nguồn**: backend/app/load_content.py:70-87; mobile/lib/features/exercise/class_diagram.dart:195-240 (`otherIsFrom`, `r.via`); mobile/lib/domain/models.dart:240-243; backend/content/content.json:152-210.

### Schema chỉ nhận key `from`, bỏ alias `from_`

**Quyết định**: `DiagramRelation.from_` khai `Field(alias="from")` và KHÔNG bật `populate_by_name`, nên key `from_` trong `content.json` bị `extra="forbid"` từ chối ngay ở schema. Hợp đồng JSON vẫn là `from` ở cả backend lẫn Dart.

**Vì sao**: bản đầu cho phép cả hai tên; `from_` lọt qua schema rồi tới `_diagram_errors` với endpoint `None`. External review bắt lỗi này (Major) và run sửa bằng cách bỏ alias thứ hai.

**Đánh đổi đã chấp nhận**: tác giả nội dung phải gõ đúng `from` (từ khoá Python) dù tên field Python là `from_`.

**Nguồn**: backend/app/content_schema.py:89-100; backend/tests/test_load_content.py:221; planning/crew/2026-10-11-class-diagram/DEVIATIONS.md.

### Phần được highlight trên sơ đồ suy từ code bài (`classScope`), không lưu

**Quyết định**: app ghép `accepted_answers[0]` của mọi ô vào template (`mergeCells`), tìm `def <function_name>(`, rồi trong thân method lấy mọi `self.<x>` không phải lời gọi (`self.x(`) làm thuộc tính được tô; method của bài cũng được tô. Bài hàm rời (`class_name` null) hoặc class không có trong sơ đồ thì không hiện mục "SƠ ĐỒ CLASS".

**Vì sao**: code đã chứa thông tin này, lưu thêm một danh sách "thuộc tính của bài" chỉ tạo bản thứ hai có thể lệch (cùng lập luận với vị trí ô suy từ template).

**Đánh đổi đã chấp nhận**: regex theo dòng nên `def` viết một dòng hoặc nhiều dòng cho thuộc tính rỗng (hiện 0 bài dính), `self.x` trong comment/string vẫn bị đếm, `classScope` chạy lại mỗi lần build (Backlog của run).

**Nguồn**: mobile/lib/domain/class_scope.dart:24-55; mobile/lib/features/exercise/challenge_tab.dart:36-45,101-105; mobile/lib/features/exercise/class_diagram.dart:138,165.

### Test hợp đồng INV-02 kiểm trong đúng thân class, không kiểm chuỗi con

**Quyết định**: `mobile/test/content_contract_test.dart` lấy thân `class <Name>` chính xác (dòng bắt đầu cột 0, đến dòng kế tiếp không rỗng ở cột 0), rồi yêu cầu mỗi thuộc tính khai trong sơ đồ có `self.<attr> =` và mỗi method có `def <m>(` trong ít nhất một thân như vậy ở code ghép của các bài cùng theme. Class có method mà không bài nào chứa `class <Name>` thì fail. INV-03: mọi bài có `class_name` phải có class đó trong sơ đồ theme.

**Vì sao**: vòng review đầu của T-05 bắt 2 Major: tìm chuỗi con trên cả đoạn code làm `class FlightService` khớp nhầm `class FlightServiceX` hoặc member của class khác. Chỉ thân class chính xác mới chặn được.

**Đánh đổi đã chấp nhận**: test không kiểm nhãn quan hệ khớp code, cũng không kiểm quan hệ.

**Nguồn**: mobile/test/content_contract_test.dart:13-27,367-426; planning/crew/2026-10-11-class-diagram/reviews/T-05.md.

### Bài nghiệp vụ có thời gian: `now` truyền vào, hoàn/chênh giá dùng giá lưu trên đặt chỗ

**Quyết định**: các method nghiệp vụ của `ReservationService` (`cancel`, `change_seats`, `change_flight`) nhận `now: datetime` làm tham số thay vì gọi `datetime.now()`; case chấm dựng giờ cố định. Số tiền hoàn/chênh lệch tính theo `price` đã lưu trong đặt chỗ lúc `book`, không đọc giá hiện tại của chuyến. Biên 24 giờ: còn đúng 24 giờ vẫn được huỷ, dưới 24 giờ (kể cả đã bay) thì `ValueError`.

**Vì sao**: judge phải xác định, kết quả Run không được đổi theo ngày giờ chạy (INV-02 của run). Dùng giá hiện tại thì khách bị hoàn sai số đã trả; case chấm cố ý sửa giá chuyến sau khi đặt để mutant "đọc giá hiện tại" bị bắt.

**Đánh đổi đã chấp nhận**: luật 24h/hoàn tiền là chính sách mẫu, không theo hãng cụ thể; giảm ghế sát giờ bị cấm (không hoàn tiền) là lựa chọn của bài. Backlog: `change_seats` chưa có case `new_seats == 0` và `now == giờ bay` (code khoá, không ở ô người học).

**Nguồn**: backend/content/content.json:2278-2290 (params có `now`), :2355-2359 (`refund = res["seats"] * res["price"]` + giải thích), :2372 (solution: `hours_left(rid, now) < 24`), :2379 (case đổi `price` sau khi đặt); planning/crew/2026-10-11-reservation-rules-outbox/PLAN.md mục "Quyết định thiết kế" 1-2, STATUS.md Backlog.

### Bài dùng chung nhiều project: cùng tên file + cùng exercise id; tiến độ theo exercise id

**Quyết định**: `reliability/outbox.py` có mặt ở theme `airline` (module `airline-reliability`) và `twitter-feed` (module `feed-reliability`) với cùng danh sách `exercise_ids` (`outbox-save`, `outbox-relay`); bài chỉ lưu một lần trong `exercises`. App nhận ra dùng chung bằng `locateFilesNamed(tên file)` rồi hiện nhãn "Dùng ở N theme". Hệ quả: tập "đã passed" khoá theo exercise id, nên làm xong bài ở project này thì bài đó cũng tính xong ở project kia; thứ tự mở khoá (bài trước trong file) tính theo từng file nên vẫn mở độc lập. Mỗi theme dùng chung phải có đủ các class của bài trong `diagram` của chính nó (Outbox, OutboxRelay, Broker).

**Vì sao**: một bài viết một lần, dùng ở nhiều ngữ cảnh (huỷ vé, đăng/like bài); tránh hai bản lệch nhau. Mô hình cây vốn cho phép id bài xuất hiện ở nhiều file (docs/modules/content-model.md).

**Đánh đổi đã chấp nhận**: không có tiến độ riêng theo theme cho bài dùng chung; câu chữ của bài phải trung tính theo project (review T-02 ghi nhận lỗi câu chữ riêng Airline). Ví dụ trong bài phải tự đủ, không dựa vào ngữ cảnh một theme.

**Nguồn**: backend/content/content.json:205-250 và :603-648 (diagram/khai file hai theme), :498-501 và :708-711 (cùng `exercise_ids`); mobile/lib/domain/content.dart:123-132 (`locateFilesNamed`); mobile/lib/domain/progression.dart:18-30 (`passed.contains(exerciseId)`); mobile/lib/features/browse/topic_detail_screen.dart:656,710; mobile/test/content_contract_test.dart:105-111.

### Test hợp đồng sơ đồ lặp theo mọi theme chứa bài (thay vì theme đầu tiên tìm được)

**Quyết định**: INV-02/INV-03 trong `content_contract_test.dart` không còn dùng `locateExercise(id).theme` (chỉ trả một theme). Với mỗi theme, gom các bài có trong `theme.allFiles`, kiểm member của sơ đồ trên code ghép của chúng; và với bài có `class_name`, class phải có trong `diagram` của MỌI theme chứa bài đó.

**Vì sao**: bài dùng chung thuộc 2 theme; test cũ chỉ kiểm theme đầu nên sơ đồ theme thứ hai có thể thiếu class mà test vẫn xanh.

**Đánh đổi đã chấp nhận**: test dài hơn và vòng lặp lồng; số đếm cứng (22 bài, 17 bài method) phải cập nhật tay mỗi lần thêm bài.

**Nguồn**: mobile/test/content_contract_test.dart:398-410 (themeCodes theo `theme.allFiles`), :442-461 (lặp theo theme); backend/tests/test_load_content.py:65 (22 bài); planning/crew/2026-10-11-reservation-rules-outbox/reviews/T-02.md (m3).

### Review nội dung bài phải chạy mutant lời giải sai qua harness

**Quyết định**: chấm một bài mới không dừng ở "lời giải mẫu pass, thân `pass` fail". Reviewer dựng các lời giải sai hợp lý (mutant: dùng giá hiện tại, bỏ dedup, `pop` trước `publish`, `continue` sau lỗi, ghi state trước validate…) và chạy qua harness; mutant nào pass ở ô người học là finding. Mutant chỉ sống ở code khoá (ngoài ô) thì chấp nhận.

**Vì sao**: run này, T-01 cần 3 vòng review chính vì mutant lọt: "giá hiện tại" ở cancel/change_seats, `new−old` ở change_flight; T-02 lọt mutant "đánh dấu seen trước khi kiểm type". Chỉ chạy lời giải mẫu không bắt được case chấm thiếu.

**Đánh đổi đã chấp nhận**: tốn công review; harness không có timeout riêng — mutant `while pending … continue` lặp vô hạn, chỉ dừng nhờ giới hạn runner/Judge0 (backend/app/runner.py:75; Backlog của run).

**Nguồn**: planning/crew/2026-10-11-reservation-rules-outbox/reviews/T-01.md:3-5, reviews/T-02.md:3-5, STATUS.md Backlog.

### Tài khoản: email + mật khẩu argon2id, token Bearer opaque lưu sha256

**Quyết định** (run 2026-10-11-users-progress-admin, commit c17baa1): mật khẩu băm argon2id (`argon2-cffi`), mật khẩu mới ≥10 ký tự. Phiên là token ngẫu nhiên `secrets.token_urlsafe(32)` gửi qua `Authorization: Bearer`; bảng `user_sessions` chỉ lưu sha256 của token, hạn 30 ngày. Đổi mật khẩu bắt buộc mật khẩu cũ và thu hồi các phiên KHÁC. Đăng nhập sai quá 5 lần/15 phút theo (IP, email) hoặc 30 lần/IP thì 429, đếm trong RAM. Không token/hết hạn → 401, không đủ role → 403, kiểm ở server mỗi request (role đọc lại từ DB). `/run` và `/content` vẫn công khai; `/run` kèm token sai thì chấm như khách.

**Vì sao**: token opaque thu hồi được ngay và không cần quản lý khoá ký như JWT; lộ bảng phiên không lộ token dùng lại được. Throttle trong RAM đủ cho một process uvicorn.

**Đánh đổi đã chấp nhận**: HTTP thường nên mật khẩu/token chưa mã hoá khi truyền (user chốt "link test HTTP", cần domain + HTTPS trước khi dùng thật); token ở localStorage (web) lộ nếu XSS; throttle mất khi restart; user chỉ tạo qua `seed_users`, chưa có quản lý user.

**Nguồn**: backend/app/auth.py:1-281; backend/app/seed_users.py:1-79; deploy/README.md:70-73; planning/crew/2026-10-11-users-progress-admin/PLAN.md (mục 1, 2), DEVIATIONS.md (SEC-01).

### Tiến độ theo user lưu trên server; `passed` chỉ do server ghi; không FK tới bài

**Quyết định**: bảng `user_progress` khoá `(user_id, exercise_id)` với `exercise_id` là chuỗi KHÔNG có khoá ngoại tới `exercises`; `user_state` giữ lịch ôn và activity. `PUT /api/progress/{id}` không nhận `passed` (`extra="forbid"`, `passed` không nằm trong `set_`); chỉ `/run` ghi `passed=true` khi máy chấm trả passed cho user có token hợp lệ. App tải snapshot lúc đăng nhập (AuthGate chặn tới khi xong), đẩy thay đổi: draft gom 800 ms, còn lại đẩy ngay; lỗi mạng giữ local. Đồng bộ "mới nhất thắng".

**Vì sao**: `load_content` xoá-rồi-ghi toàn bộ nội dung; FK cascade sẽ xoá sạch tiến độ mỗi lần admin lưu (INV-04). Cho client tự khai `passed` thì gửi request tay là "xong bài" (INV-05).

**Đánh đổi đã chấp nhận**: tiến độ có thể mồ côi (id/nhãn bị đổi hoặc xoá): server ẩn id lạ, client bỏ nhãn lạ. "Xong bài" có thể lệch local/server khi token hết hạn đúng lúc Run (`/run` không trả 401). Code học viên in giả dòng "passed" vẫn được ghi (harness cùng tiến trình) — chấp nhận vì tiến độ chỉ ảnh hưởng chính người đó, bác bỏ finding external của run.

**Nguồn**: backend/app/progress.py:28-44,108-111,179-256; backend/app/tables.py:153-184; backend/app/main.py:178-184; mobile/lib/features/exercise/session_controller.dart:74-110; planning/crew/2026-10-11-users-progress-admin/PLAN.md (INV-04, INV-05), DEVIATIONS.md (bác bỏ external T-01 F1), reviews/SEAM.md.

### DB là nguồn chính của nội dung; một đường ghi; deploy không ghi đè

**Quyết định**: Postgres là nguồn chính. Cả CLI và `PUT /api/admin/content` đi qua `load_content` (validate + thay toàn bộ trong một transaction dưới `pg_advisory_xact_lock`). `PUT` kiểm `base_version` (sha256 toàn bộ nội dung, kể cả `judge`) dưới cùng khoá; lệch thì 409. `deploy.sh` chạy `load_content --if-empty`; ghi đè có chủ ý dùng `--force`; sửa bằng file thì `export_content` → sửa → `--force`. Luật nội dung port từ test Dart sang `content_rules.py` để chạy trên mọi bộ nội dung. Server không chạy lời giải mẫu khi Lưu.

**Vì sao**: admin sửa thẳng DB thì deploy ghi đè sẽ xoá việc của họ; luật chỉ ở test Dart thì admin lưu được bài mà học viên gõ đúng vẫn bị chấm sai (INV-06). Không chạy code ở server admin để tránh thực thi code ngoài máy chấm.

**Phương án đã bỏ / lệch plan**: (1) luật "mọi module có ≥1 bài" của Dart không port — server cho module rỗng để admin xoá bài cuối hoặc dựng khung trước (luật "theme có ≥1 module" thì có, sau review); (2) thêm cờ tắt luật cho fixture test — bỏ, sửa fixture cho đủ luật; (3) vòng 4 review T-03 — user chọn đóng sau 3 vòng, orchestrator tự sửa lỗi CPU của kiểm sơ đồ và thêm test hiệu năng (<1s ở payload xấu nhất); (4) bác bỏ external "bài mồ côi lọt validate" vì bài không thuộc file nào là thiết kế được hỗ trợ.

**Đánh đổi đã chấp nhận**: sửa `content.json` rồi deploy không còn tác dụng; không có lịch sử phiên bản; luật nội dung có hai bản cài (Dart/Python), không test so trực tiếp; thêm luật chỉ có ở server (id ≤100 ký tự, trần số lượng/độ dài).

**Nguồn**: backend/app/load_content.py:1-48,293-420; backend/app/admin_api.py:1-124; backend/app/content_rules.py:1-320; backend/app/export_content.py:1-73; deploy/deploy.sh:70-79; planning/crew/2026-10-11-users-progress-admin/PLAN.md (mục 5, INV-06), DEVIATIONS.md.

### Mật khẩu ban đầu chỉ vào file root 0600, không in ra, không qua chat

**Quyết định**: `seed_users` tạo `test@gmail.com` (learner) và `phuongtt.tech1508@gmail.com` (learner + admin) với mật khẩu ngẫu nhiên, APPEND vào `INITIAL_PASSWORDS_FILE` (VPS: `/etc/smart-coding-study/initial-passwords`, file 0600 mở `O_NOFOLLOW`, thư mục 0700; dev: `backend/.initial-passwords`, gitignore); stdout chỉ in số lượng. Ghi file TRƯỚC khi commit DB. User đã có thì không đổi mật khẩu. Rsync loại file dev và deploy xoá bản dev trên server.

**Vì sao**: mật khẩu không được lọt stdout/log/git/chat/URL (INV-03). Ghi file trước commit: commit lỗi chỉ thừa dòng vô hại, ngược lại ra tài khoản không ai biết mật khẩu.

**Đánh đổi đã chấp nhận**: chủ VPS phải tự đọc file qua ssh rồi đổi mật khẩu và xoá file; nhiều dòng cùng email (seed lỗi giữa chừng) thì dòng cuối đúng. Bác bỏ external T-04 LOW "stdout in đường dẫn file" vì đường dẫn không phải bí mật.

**Nguồn**: backend/app/seed_users.py:1-79; deploy/deploy.sh:27,70-83; deploy/README.md:44-54; planning/crew/2026-10-11-users-progress-admin/PLAN.md (mục 7, INV-03), DEVIATIONS.md.

### Demo không đăng nhập bằng cờ `AUTH_OPEN_AS`, không gỡ code auth

**Quyết định**: biến môi trường `AUTH_OPEN_AS=<email>` bật chế độ mở: request không có token hợp lệ được coi là user đó (token thật vẫn thắng). `/api/me` trả thêm `open`; app thấy `open: true` thì vào thẳng bằng phiên token rỗng, không gửi Bearer, ẩn đăng xuất/đổi mật khẩu; `POST /api/auth/password` ở phiên mở trả 403 `open_mode`. `deploy.sh` bật mặc định cho `test@gmail.com`, tắt bằng `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh`.

**Vì sao**: user đang demo và không muốn mật khẩu; một cờ giữ nguyên toàn bộ code auth, tắt cờ là về hành vi cũ (INV-01), gỡ auth thì mất tiến độ theo user và phân quyền admin. Đổi mật khẩu bị chặn vì phiên ảo không có phiên để giữ lại, nên đổi sẽ xoá hết phiên thật của user (review mối nối #1).

**Phương án đã bỏ / lệch plan**: bác bỏ finding "Critical" của external về giá trị `DEPLOY_AUTH_OPEN_AS` phá quote/chèn lệnh qua ssh: chỉ operator đặt được, nhưng sửa rẻ nên kiểm dạng email ở local và server. Thêm chặn đổi mật khẩu ngoài plan ban đầu.

**Đánh đổi đã chấp nhận**: ai có link là `test@gmail.com` (admin, gồm `/api/admin/*`); mặc định deploy là BẬT; phiên mở trong RAM nên server tắt cờ giữa chừng thì app không tự về màn đăng nhập tới khi tải lại.

**Nguồn**: backend/app/auth.py:163-189, 224-226, 282-296; backend/app/main.py:147; mobile/lib/data/auth_repository.dart:84-123; mobile/lib/data/api_client.dart:68-72; deploy/deploy.sh:14-21, 96-100, 128-131; planning/crew/2026-10-11-auth-open-mode/PLAN.md (INV-01..04), DEVIATIONS.md, reviews/SEAM.md.

### Admin đi từng tầng (drill-down), không dùng accordion/cây phẳng

**Quyết định**: trang Admin chia thành các màn riêng theo tầng `/admin` → `/admin/theme/:themeId` → `/admin/module/:moduleId` → `/admin/exercise/:id`, mỗi màn có breadcrumb, thẻ lớn, menu ⋯ và một thanh lưu ghim dùng chung; không gộp cả cây vào một màn xổ ra/thu vào (accordion).

**Vì sao**: cây phẳng nhiều icon sửa/thêm/xoá chữ to rất rối trên điện thoại (ảnh user gửi); user chọn drill-down. Mỗi tầng ít phần tử, chạm to, back và URL web đúng theo tầng, và các hành động hiếm (đổi tên, xoá) gom vào ⋯. Controller/API giữ nguyên (chỉ thêm `addTheme`, `addExercise(functionName, className)`), nên dirty/409/422/xác nhận Hủy sửa không đổi.

**Phương án đã bỏ**: accordion trong một màn (user không chọn; run không ghi lý do chi tiết hơn). Chấm đỏ lỗi hiện ở thẻ bài/module/project thay cho danh sách lỗi dài.

**Đánh đổi đã chấp nhận**: đi sâu tốn nhiều chạm hơn cây một màn; breadcrumb phải xử lý cả stack push và mở thẳng URL (`adminGoToLevel`); chấm đỏ phụ thuộc định dạng chuỗi lỗi server `bài <id>`, nên lỗi không kèm id bài chỉ hiện ở chip "N lỗi". Seam review ban đầu bắt lỗi regex bỏ sót `bài <id> ô <X>:`, đã sửa trước khi commit.

**Nguồn**: mobile/lib/app/router.dart:88-110; mobile/lib/features/admin/admin_widgets.dart:14-35,117-130; planning/crew/2026-10-11-admin-ux-levels/PLAN.md, reviews/SEAM.md, reviews/T-02.md.

### HTTPS bằng domain riêng + Let's Encrypt, không dùng sslip.io hay ngoại lệ ATS

**Quyết định** (run 2026-10-11-testflight-prep): phục vụ web và API tại `https://codewithphuong.jacons-corp.com` (nginx cổng 443, cert Let's Encrypt lấy một lần bằng `certbot certonly --nginx`, chỉ lấy cert, không để certbot sửa conf; `certbot.timer` có sẵn tự gia hạn). Web (`PUBLIC_URL`) và iOS (`API_URL`) cùng trỏ origin này. `deploy.sh` kiểm cert tồn tại TRƯỚC mọi thay đổi (thiếu thì dừng, in lệnh certbot), smoke test qua HTTPS bằng `curl --resolve`, và `rollback_site` trả site nginx cũ nếu smoke lỗi. `PUBLIC_URL` không còn là biến ghi đè được.

**Vì sao**: TestFlight cần app gọi server qua HTTPS (iOS chặn HTTP thường, ATS). User đã có domain trỏ về VPS và tài khoản certbot sẵn trên VPS dùng chung, nên cert hợp lệ do CA công khai cấp là đường ít bất ngờ nhất: cùng cách các site khác trên VPS đang làm, cert tự gia hạn, không cần cấu hình đặc biệt trong app.

**Phương án đã bỏ**: (1) sslip.io (domain kiểu `<ip>.sslip.io`) — phụ thuộc dịch vụ ngoài và giới hạn phát cert của CA, địa chỉ khó nhớ; (2) ngoại lệ ATS (khai `NSAllowsArbitraryLoads` trong Info.plist) — vẫn truyền mật khẩu/token không mã hoá và có nguy cơ bị Apple hỏi lý do khi duyệt; app chỉ giữ `NSAllowsLocalNetworking` cho dev. Lý do bỏ hai phương án này suy từ PLAN.md (mục Context/Thiết kế) chứ run không ghi tranh luận riêng.

**Đánh đổi đã chấp nhận**: deploy phụ thuộc cert có sẵn trên VPS (chưa có thì dừng); domain lặp ở `deploy/deploy.sh`, `deploy/ios-build.sh` và `server_name`/`return` trong file nginx, đổi domain phải sửa cả ba; chưa bật HSTS; chế độ mở vẫn khiến mọi người cài TestFlight là `test@gmail.com` (admin).

**Nguồn**: deploy/deploy.sh:16-18, 30-33, 142-158; deploy/nginx/smart-coding-study.conf:1-30; deploy/ios-build.sh:11-12, 27-29; planning/crew/2026-10-11-testflight-prep/PLAN.md, STATUS.md, reviews/SEAM.md (INV-01, INV-02).

### Chuyển hướng 308, không phải 301, cho `:80` và `:8090`

**Quyết định**: server `:8090` (link cũ `http://<ip>:8090`) và server `:80` của domain đều `return 308 https://codewithphuong.jacons-corp.com$request_uri`. Smoke test của deploy đòi `:8090` trả đúng 308.

**Vì sao**: 308 buộc client giữ nguyên method và body khi theo chuyển hướng, còn 301 cho phép (và nhiều client làm) đổi POST thành GET. App có `POST /run` và các `POST/PUT /api/*`; client cũ còn trỏ vào `:8090` sẽ gửi body đến đích đúng. Review external (Codex) của T-01 nêu điểm này; plan ban đầu ghi 301 và được sửa thành 308. Kiểm thật: POST `/run` qua `:8090` giữ POST và trả kết quả `passed`.

**Đánh đổi đã chấp nhận**: client rất cũ không hiểu 308 có thể không theo chuyển hướng (không đo); domain hardcode trong hai `return`.

**Nguồn**: deploy/nginx/smart-coding-study.conf:7-20; deploy/deploy.sh:156-158; planning/crew/2026-10-11-testflight-prep/DEVIATIONS.md, STATUS.md.

### MCP: đăng nhập OAuth qua identity-service, backend chỉ là resource server

**Quyết định** (run 2026-10-11-mcp-content): claude.ai kết nối `https://codewithphuong.jacons-corp.com/mcp` bằng OAuth 2.1 + PKCE với identity-service (đăng nhập GitHub). Backend này chỉ verify JWT RS256 qua JWKS (`iss`, `aud == <PUBLIC_BASE_URL>/mcp`, `exp`), không phát token, không giữ secret. Được sửa nội dung hay không do bảng `mcp_access` (`sub` → user admin) quyết, kiểm lại ở MỖI tool call; cấp/thu hồi bằng CLI `python -m app.mcp_access` hoặc `/api/admin/mcp-access`. Bên identity-service chỉ thêm resource vào `OAuth2:AllowedResources`.

**Vì sao**: docs Anthropic cấm đặt token trong URL, và tính năng request headers cho connector còn ở dạng beta, nên app key tĩnh hay key trong URL không phải đường được hỗ trợ ổn định. identity-service đã có sẵn DCR (đăng ký client động) + PKCE chạy thật cho connector của app khác (expense-tracker), nên dùng lại rẻ hơn dựng mới. Ai có GitHub cũng lấy được token cho resource này, và JWT sống 60 phút không thu hồi được, nên thêm allowlist `mcp_access` (fail-closed: bảng rỗng thì không ai ghi được) kiểm mỗi request.

**Phương án đã bỏ**: (1) app key tĩnh trong header — phụ thuộc tính năng beta; (2) key trong URL — docs Anthropic cấm; (3) tự viết authorization server trong backend này — thêm bề mặt bảo mật (phát token, lưu secret) khi đã có dịch vụ chạy thật. Lý do này lấy từ yêu cầu của user trong run và Context của PLAN.md.

**Đánh đổi đã chấp nhận**: backend phụ thuộc identity-service sống (JWKS chết thì `/mcp` trả 503, có grace 1 giờ cho khoá đã cache); chuỗi resource phải khớp ở ba nơi (PRM, `aud`, `AllowedResources`) và đổi domain là sửa cả hai repo; redeploy identity-service chạm các app khác (chỉ đổi config); đổi mật khẩu app không thu hồi quyền MCP vì quyền gắn tài khoản identity, cắt bằng `revoke`.

**Nguồn**: backend/app/mcp_auth.py:1-13,169-218; backend/app/mcp_server.py:246-274; backend/app/tables.py:187-201; planning/crew/2026-10-11-mcp-content/PLAN.md (Context, Thiết kế, INV-03, INV-04, INV-06), DEVIATIONS.md.

### Mọi sửa nội dung vào hàng chờ theo mục; live và draft là hai khái niệm tách biệt

**Quyết định** (run 2026-10-11-content-review-queue): học viên chỉ đọc "live" (các bảng nội dung). Admin PUT và MCP không còn ghi live mà ghi các dòng `pending` vào bảng `content_changes` (migration 0006), mỗi dòng ứng một mục project/module/file/bài. "Draft" = live cộng mọi dòng pending; admin editor, MCP đọc/ghi và `GET /api/admin/content` đều làm việc trên draft, `base_version` = hash draft. Chỉ hai đường ghi live: `approve` từng mục (khoá, so mục live với `before`, validate toàn bộ live mới, rồi `load_content`) và CLI `load_content --force`. Preview của admin dùng lại `ExerciseScreen` với `/api/admin/run` chấm theo draft và không ghi tiến độ. Sửa lại mục "DB là nguồn chính ... một đường ghi": "một đường ghi" nay nghĩa là một hàm `load_content` cho nội dung đang chạy, còn PUT và MCP chỉ gửi duyệt.

**Vì sao**: Claude qua MCP và admin editor trước đó ghi thẳng, nên một bản sửa sai lộ ngay cho học viên. User muốn xem thử đúng màn học viên và duyệt/bỏ từng bài, project/module/file là mục duyệt riêng.

**Quyết định con**: (1) mỗi mục lưu `order` đầy đủ của anh em thay vì anchor `prev`, nên áp theo thứ tự nào cũng ra đúng draft và round-trip đúng khi đổi thứ tự; (2) diff chỉ coi là "đổi chỗ" những mục không thuộc dãy con chung dài nhất, để chèn một bài vào đầu file không biến mọi bài sau thành mục chờ; (3) ràng buộc cha–con khi duyệt: tạo con trước cha thì 422 `dependency_missing`, project mới kéo module cấp 1 mới, xoá project/module kéo các mục XOÁ trong nhánh, bài không bao giờ bị xoá ngầm, reject kéo theo mục không còn áp được.

**Phương án đã bỏ / lệch plan**: (1) hỗ trợ chuyển module sang cha khác — sau 3 vòng review vẫn còn Major (đảo cha–con, kéo module có sẵn vào project mới), user chọn chặn đầu vào: 422 `unsupported_move`, MCP trả ToolError; (2) anchor `prev` — bỏ vì không round-trip khi đổi thứ tự; (3) Chrome e2e — thay bằng widget test từ Home và e2e HTTP 22 bước (cửa sổ hidden từng làm sai kết quả).

**Đánh đổi đã chấp nhận**: CLI `load_content --force` khi có mục chờ cùng thùng chứa thì approve áp lại thứ tự draft; duyệt xoá module có bài đã được admin xoá giờ thành công; hàng chờ chưa phân trang; học viên đang mở app chỉ thấy bản mới khi tự refresh. Vận hành: test backend cần `TEST_DATABASE_URL` DB riêng, vì process fuzz của reviewer trên DB test dùng chung giữ khoá làm suite chậm.

**Nguồn**: backend/app/review.py:1-571; backend/app/admin_api.py:94-174; backend/app/mcp_server.py:91-125; backend/app/tables.py:203-232; backend/app/main.py:219-236; mobile/lib/features/exercise/exercise_screen.dart:51-75; planning/crew/2026-10-11-content-review-queue/PLAN.md (Thiết kế, INV-01..07), DEVIATIONS.md, STATUS.md, reviews/SEAM.md.

### Màn Soạn bài tập: ô code là TextField + HighlightingController, 3 breakpoint, mọi mục mở mặc định

**Quyết định** (run 2026-10-12-exercise-editor-redesign, PR #26, theo mockup đã duyệt): (1) ô code là một `TextField` giữ nguyên Key, controller là `HighlightingController extends TextEditingController` ghi đè `buildTextSpan` để tô màu bằng tokenizer Python/JSON, màu lấy từ `context.palette`; (2) bố cục theo `LayoutBuilder` với ngưỡng 1100 (mục lục | form | panel ghép thử) và 700 (form | panel; dưới 700 là một cột), panel ghép thử chỉ dựng ở một chỗ tại một thời điểm; (3) mọi mục và ô mở mặc định.

**Vì sao**: (1) controller giữ `controller.text` là nguồn sự thật nên `_Form.toJson`, `_previewMerge` và so với `judge.solution` không đổi, không thêm package; (3) test cũ tìm Key trong Judge/Challenge/ô B, mục đóng thì widget rời cây và `find.byKey` rỗng. Lệch mockup có chủ ý (mockup đóng vài mục).

**Phương án đã bỏ / lệch plan**: overlay chữ lên TextField và package editor (không dùng); `SurfaceCard` cho thẻ ô — dựng container riêng vì SurfaceCard bọc InkWell, chạm vùng trống sẽ đóng/mở (DEVIATIONS.md). Nút "Thu gọn tất cả" có trong plan nhưng chưa làm (state đóng/mở nằm trong widget).

**Đánh đổi đã chấp nhận**: đóng riêng một thẻ ô thì lỗi nhãn không hiện chữ (INV-06 vỡ một phần, Minor); mục lục không tự mở mục đóng; chưa test biên 700/1100; chưa kiểm bằng mắt trên web.

**Nguồn**: mobile/lib/features/admin/code_cell.dart:133-181; mobile/lib/features/admin/exercise_editor.dart:690-693,962-1004; planning/crew/2026-10-12-exercise-editor-redesign/PLAN.md (Quyết định thiết kế 1-5), DEVIATIONS.md, reviews/SEAM.md
