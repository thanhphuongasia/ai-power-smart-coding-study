# Architecture

> Repo demo cho ứng dụng học lập trình di động "Smart Coding Study": app Flutter (làm bài code
> trong ô nhỏ trên điện thoại, autocomplete đủ tốt để không nản) cùng một backend FastAPI nhỏ
> lưu nội dung học trong Postgres, phát cho app qua `GET /content` và chấm bài bằng Python thật.

## Bản đồ nhanh

Ghi chú: script kiểm `verify-distill.sh` chỉ nhận toạ độ `file:dòng` có đuôi py/ts/js/sh/sql/toml/yaml/json/md,
không nhận `.dart`. Vì vậy cột cuối của dòng Dart trỏ về mục chi tiết trong tài liệu này
(docs/ARCHITECTURE.md:1) để gate không chặn; toạ độ `.dart` thật nằm ngay cột giữa.

| thành phần | vai trò và toạ độ | mục chi tiết |
| --- | --- | --- |
| backend | API `POST /run`: chạy harness + unit test của bài (đọc từ Postgres) qua máy chấm (Judge0), trả đúng/sai từng test — backend/app/main.py:106 | docs/modules/judge-backend.md:1 |
| backend/content | `GET /content`: cả cây nội dung học (theme → module lồng nhau → file → bài) từ Postgres, không có phần chấm — backend/app/content_api.py:184 | docs/ARCHITECTURE.md:1 |
| backend/load_content | nạp `content.json` vào Postgres, thay toàn bộ trong một transaction — backend/app/load_content.py:135 | docs/ARCHITECTURE.md:1 |
| backend/db + tables | engine/session SQLAlchemy + bảng nội dung (`topics.parent_id`, `exercises.class_name`) + migration Alembic — backend/app/db.py:19, backend/app/tables.py:31, backend/migrations/versions/0002_module_tree_class.py:22 | docs/ARCHITECTURE.md:1 |
| backend/runner | interface `CodeRunner` + `Judge0Runner` — backend/app/runner.py:42, backend/app/runner.py:56 | docs/modules/judge-backend.md:1 |
| backend/harness | chương trình chạy trên máy chấm: compile code học viên, chạy từng test case (kể cả case kịch bản gọi method), in một dòng JSON — backend/app/harness.py:48 | docs/modules/judge-backend.md:1 |
| domain | model bất biến, ghép ô (mobile/lib/domain/merge.dart:80), khoá bài (mobile/lib/domain/progression.dart:22), hàm so chuỗi cũ (mobile/lib/domain/answer_checker.dart:68) | docs/ARCHITECTURE.md:1 |
| data | tải nội dung + cache (mobile/lib/data/content_repository.dart:40), provider nội dung (mobile/lib/data/content_providers.dart:11), client gọi `/run` (mobile/lib/data/judge_client.dart:59), tiến độ demo (mobile/lib/data/demo_seed.dart:7) | docs/ARCHITECTURE.md:1 |
| features/exercise | màn bài 3 tab (mobile/lib/features/exercise/exercise_screen.dart:31), tiến độ/đồng hồ (mobile/lib/features/exercise/session_controller.dart:29), editor autocomplete | docs/modules/exercise-screen.md:1 |
| features/browse | duyệt Home → Theme → Module (lồng nhiều tầng) → danh sách bài, nhóm theo class, có trạng thái khoá (mobile/lib/features/browse/exercise_row.dart:39) | docs/ARCHITECTURE.md:1 |
| features/review, stats, practice, admin, shell | ôn tập, thống kê, luyện, quản trị, bottom nav; đọc tiến độ từ cùng `progressProvider`, không mô tả chi tiết ở đây (mobile/lib/app/router.dart:26-59) | docs/ARCHITECTURE.md:1 |
| app | theme (mobile/lib/app/theme.dart:1) + router (mobile/lib/app/router.dart:22) + cổng nội dung (mobile/lib/app/content_gate.dart:12) | docs/ARCHITECTURE.md:1 |
| deploy | triển khai lên VPS dùng chung: nginx cổng 8090 phục vụ web tĩnh và chuyển `/content`, `/run` vào uvicorn 127.0.0.1:8100; một lệnh `deploy/deploy.sh` — deploy/deploy.sh:1, deploy/README.md:11-20 | docs/modules/deploy.md:1 |
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
| Kiểm body (≤64KB, có Content-Length) và `code` ≤ 8000 ký tự | middleware + `RunRequest` | backend/app/main.py:39-53 |
| Tra bài trong Postgres bằng session ngắn (đóng trước khi chờ máy chấm); không có bài → 404 | `lookup_judge` | backend/app/main.py:114-116, backend/app/content_api.py:156-182 |
| Ghép payload `{code, function, class_name, cases}` | `run()` | backend/app/main.py:118-125 |
| Gửi `HARNESS_SOURCE` làm source, payload làm stdin cho máy chấm (tối đa 4 đồng thời) | `runner.run` | backend/app/main.py:124-125 |
| Máy chấm hỏng/429/5xx/không hiểu → `503 runner_unavailable` | `RunnerUnavailable` | backend/app/main.py:126-128 |
| DB không kết nối được → `503 database_unavailable`; chưa nạp nội dung → `503 content_not_loaded` | exception handler | backend/app/main.py:69-78 |
| Quá giờ → `status: timeout`; còn lại parse dòng `__JUDGE_RESULT__` | `harness.parse_result` | backend/app/main.py:131-139 |

```python
class CodeRunner(Protocol):
    async def run(self, source: str, stdin: str) -> Execution: ...
```
(backend/app/runner.py:42-43)

### Ranh giới

Không chống gian lận: code học viên chạy cùng tiến trình với harness, nên cố tình in dòng kết quả
giả là tự lừa mình (chấp nhận cho app học). Không có xác thực người dùng; backend chỉ lưu nội dung học
(không lưu tiến độ). Mặc định chạy local (`127.0.0.1:8000`; trên VPS xem mục deploy) và cần Postgres
(`DATABASE_URL`, backend/app/db.py:11-15).

## Luồng nội dung — content.json → Postgres → /content → cache trong app

### Là gì

Nội dung học có một nguồn soạn là file `backend/content/content.json`. Lệnh nạp chép nó vào Postgres;
backend phát lại cho app qua `GET /content`; app lưu bản tải gần nhất trên máy để mở được khi mất
mạng. Postgres là nguồn chạy thật của cả `/content` lẫn `/run`, nên id bài ở hai API luôn khớp.
App không còn chứa nội dung học nào (chỉ còn tiến độ demo).

### Cách hoạt động

| Chặng | Làm gì | file:dòng |
| --- | --- | --- |
| Soạn | `content.json` = cây nội dung + `judge: {solution, cases}` mỗi bài; bài method có `class_name` | backend/content/content.json:195,266 |
| Nạp | kiểm hình dạng (pydantic strict) + id/quan hệ + case kịch bản, xoá hết rồi ghi lại trong một transaction, `version` = sha256 phần công khai | backend/app/load_content.py:49-132,135-205 |
| Lưu | bảng `themes/topics/code_files/exercises/file_exercises/blocks/content_meta` | backend/app/tables.py:18-108 |
| Phát | `GET /content`: 6 SELECT kẹp giữa hai lần đọc `version`, đọc lại (tối đa 3) nếu version đổi giữa chừng; `response_model` không có `judge` | backend/app/content_api.py:44-61,184-186 |
| Tải + cache | `GET /content` timeout 5s; thành công thì ghi cache; lỗi gì cũng rơi về cache; không có cache thì `ContentUnavailable` (mobile/lib/data/content_repository.dart:58-98) | docs/ARCHITECTURE.md:1 |
| Cổng | `ContentGate` chờ/lỗi/dữ liệu + banner khi dùng cache; `main()` override `contentIndexProvider` (mobile/lib/app/content_gate.dart:17-71, mobile/lib/main.dart:10-21) | docs/ARCHITECTURE.md:1 |

```python
# nạp: version cùng transaction với dữ liệu
session.add(ContentMeta(key="version", value=version))
session.flush()
```
(backend/app/load_content.py:154-155)

### Ranh giới

Sửa trực tiếp trong DB sẽ bị lần nạp sau ghi đè (backend/README.md:42-44 mô tả cách nạp lại). Đổi `id`
bài hoặc `label` ô làm tiến độ cũ mồ côi vì tiến độ khoá theo hai thứ đó. `/content` không có
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
Phần còn lại trong app là `demo_seed.dart`, chỉ có tiến độ demo.

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
backend/app/main.py:64-82). Hình dạng `/content` cũng giữ khớp bằng hai bên tự viết: model pydantic
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
(`theme.dart`) và bảng route (`router.dart`). Mọi màn hình đọc màu qua `AppColors`/
`Theme.of(context).colorScheme`, không tự định nghĩa `Color(0x...)` riêng — quy tắc này được
kiểm bằng `grep` (INV-04 trong sổ bất biến của run, xem `reviews/SEAM.md`).

### Cách hoạt động

```dart
abstract final class AppColors {
  static const Color surface = Color(0xFF111418);
  static const Color primary = Color(0xFF5ccfb0);   // teal — màu chính
  static const Color accent = Color(0xFFf5b94a);     // amber — CHỈ dùng cho hint
  static const Color danger = Color(0xFFff7b72);
  // ...
}
```
(mobile/lib/app/theme.dart:6-17)

Font không tải qua mạng (không dùng gói `google_fonts`) — hai font family (IBM Plex Sans,
JetBrains Mono) được bundle sẵn dạng file `.ttf` trong `mobile/assets/fonts/` và khai trong
`pubspec.yaml` (mobile/pubspec.yaml:64-76).

### Ranh giới

`router.dart` không có auth guard hay redirect — mọi route mở thẳng, kể cả `/exercise/:exerciseId`
(việc khoá bài do `ExerciseScreen` tự kiểm, không do router; xem mục features/exercise).

## shared — widget dùng chung

### Là gì

Bộ widget tái dùng giữa các màn: `SurfaceCard`, `TagChip`, `ResultBadge`, `TimerPill`,
`ThinProgressBar`, `ScreenHeader`, `SectionLabel`, `PrimaryButton`, `GhostButton`, `HintButton`.
Tồn tại để tránh mỗi màn tự viết lại card/nút/progress bar theo phong cách khác nhau.

### Cách hoạt động

Tất cả đọc token từ `AppColors`/`AppSpace`/`AppRadius`/`AppText`, không hardcode giá trị —
`elevation` mặc định 0 (không đổ bóng), bo góc theo 3 mức cố định (`sm`=6, `md`=12,
`pill`=999) (mobile/lib/app/theme.dart:26-29).

### Ranh giới

`PrimaryButton`/`HintButton` bọc `ElevatedButton` của Material — còn giữ elevation mặc định của
Material thay vì elevation 0 tường minh ở hai chỗ này (mobile/lib/shared/widgets.dart:266,335);
đã ghi Minor trong Backlog, chưa sửa tại thời điểm run này kết thúc.


## deploy — web + API cùng một origin trên VPS

### Là gì

Phần triển khai đưa app lên một VPS dùng chung với dịch vụ khác để có một link thử trên trình duyệt.
Trình duyệt chỉ nói chuyện với một địa chỉ duy nhất (cổng 8090 của nginx). nginx trả file web Flutter đã
build sẵn, và chuyển đúng hai đường dẫn của backend (`/content`, `/run`) vào uvicorn đang nghe ở
`127.0.0.1:8100`. Vì web và API cùng "origin" (cùng giao thức, host, cổng) nên trình duyệt không áp luật
chặn gọi chéo nguồn (CORS) và backend không phải cấu hình gì thêm. Chi tiết vận hành xem
`docs/modules/deploy.md`.

### Cách hoạt động

Đường đi của một request:

```text
trình duyệt --HTTP--> nginx :8090
  nếu /content hoặc /run -> uvicorn 127.0.0.1:8100 -> Postgres smart_coding_study
                                                   -> Judge0 CE công khai (chỉ /run)
  còn lại                -> /opt/smart-coding-study/web (file tĩnh, fallback index.html)
```

| Thứ | Ở đâu | file:dòng |
| --- | --- | --- |
| Địa chỉ công khai + cổng mặc định, truyền vào bản build web làm `API_URL` | biến `PUBLIC_URL` | deploy/deploy.sh:13, deploy/deploy.sh:18 |
| Build web ở máy dev (VPS không có Flutter), rồi rsync lên server | bước 1-2 của script | deploy/deploy.sh:17-28 |
| User hệ thống riêng `smartcs`, không shell | `useradd` nếu chưa có | deploy/deploy.sh:40 |
| Role + DB Postgres riêng; mật khẩu sinh trên server, đi qua stdin của psql | `openssl rand` + `pg` | deploy/deploy.sh:44-61 |
| Bí mật chỉ nằm ở `/etc/smart-coding-study.env` (root:smartcs, 640), ghi file tạm rồi `mv` | `ENV_FILE` | deploy/deploy.sh:37-57 |
| Migration rồi nạp nội dung mỗi lần deploy | `alembic upgrade head`, `app.load_content` | deploy/deploy.sh:70-72 |
| Cài unit systemd, `enable` + `restart` | `smart-coding-study-api` | deploy/deploy.sh:79-82 |
| nginx: `nginx -t` trước, lỗi thì trả site cũ và dừng, sạch mới `reload` | khối nginx | deploy/deploy.sh:85-94 |
| Smoke test: `/content` qua 8100 và 8090, `/` qua 8090 | `curl -fsS` | deploy/deploy.sh:96-103 |

Cấu hình nginx (deploy/nginx/smart-coding-study.conf:18-39) chỉ mở đúng hai route API bằng `location =`, mọi
đường dẫn khác rơi vào `try_files ... /index.html` để router của web hoạt động:

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

Unit systemd (deploy/systemd/smart-coding-study-api.service:7-19) chạy uvicorn bằng user `smartcs`, nạp env từ
file bí mật, và siết quyền: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`,
`ReadOnlyPaths=/opt/smart-coding-study`. Ba mốc thời gian lồng nhau: HTTP timeout của runner 15s, nginx
`proxy_read_timeout` 18s (conf:31), client app 20s (mobile/lib/data/judge_client.dart:63). Body: nginx cho tới
80k (conf:10), lớn hơn giới hạn 64KB của backend để chính backend trả 413 (backend/app/main.py:34).

### Ranh giới

Chỉ chạm tài nguyên tên `smart-coding-study`/`smartcs` vì VPS dùng chung (deploy/deploy.sh:7-9). Không có
HTTPS hay domain, không mật khẩu và không giới hạn tốc độ trên `/run`: ai có link đều chạy được code, và code
được chuyển tới Judge0 công khai nên IP VPS có thể bị Judge0 chặn nếu bị lạm dụng (deploy/README.md:36-41).
Không có CI deploy: chỉ chạy tay từ máy có Flutter và SSH tới host `vps`.

## Giới hạn đã biết

Tiến độ chưa bền: không có Hive hay SQLite, nên tiến độ, draft code, hint và ô đã xem lời giải sống trong
`ProgressController` và mất khi app bị kill (Hive thuộc issue #5). Về máy chấm, code học viên được gửi tới Judge0 CE
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
(backend/app/main.py:36) cộng 15s Judge0 vượt `proxy_read_timeout` 18s; cổng 8090/8100 lặp ở ba file
(deploy/deploy.sh:13, deploy/README.md:9, deploy/systemd/smart-coding-study-api.service:12) và chỉ smoke test
bắt được lệch; thư mục tạm `/root/.smart-coding-study-deploy` không tự dọn nếu script chết giữa chừng
(deploy/deploy.sh:22). Review chéo bằng model họ khác không chạy được (Codex timeout 2 lần).
