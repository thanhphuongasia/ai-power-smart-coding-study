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
