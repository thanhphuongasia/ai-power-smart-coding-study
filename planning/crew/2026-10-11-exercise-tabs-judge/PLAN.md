# Run `exercise-tabs-judge` — 3 tab + ô TODO kiểu Jupyter + chấm Python thật qua backend (Judge0)

## Context

Mockup đã chốt: https://claude.ai/artifact/AcQ8fBTYcKoiyW44QhDfLc. Hiện app chấm bằng so chuỗi
(`mobile/lib/domain/answer_checker.dart:68` `runBlock`), mỗi bài là chuỗi block tuần tự
(BlockListScreen → CellScreen). User muốn:

- mỗi bài 3 tab: **Challenge** (đề + "Dùng để làm gì?" + ví dụ nhỏ/dự án thật), **Code**, **Solution**;
- Code kiểu Jupyter: code có sẵn là ô khoá, mỗi TODO A/B/C là một ô riêng, không cần thụt lề;
  Run → tự ghép → hiện code đã ghép (dòng nào từ ô nào) → chạy;
- chấm bằng **Python thật**, mỗi bài có unit test, **pass hết mới qua bài kế tiếp**, sai thì chỉ ô nào;
- Solution mở từng ô; ô đã xem lời giải không tính điểm, vẫn phải tự gõ.

User đã chốt: backend riêng (self-host về sau), **giai đoạn đầu dùng máy chấm bên thứ ba** để
nhanh, nhưng có **interface để sau này đổi sang self-host dễ**; tích hợp máy chấm làm luôn run
này. Backend **chỉ chạy local 127.0.0.1** (simulator iOS).

## Quyết định thiết kế

1. **Backend FastAPI** ở `backend/` (khớp issue #5). App gọi `POST /run {exercise_id, code}`;
   backend giữ test case + lời giải tham chiếu ở **một file** `backend/app/exercises.json`
   (client không sửa được test). Nội dung hiển thị (đề, template, gợi ý, lời giải từng ô) vẫn ở
   `mobile/lib/data/seed.dart` — không đổi app sang tải nội dung qua mạng.
2. **Máy chấm qua interface `CodeRunner`** (`backend/app/runner.py`):
   ```python
   @dataclass(frozen=True)
   class Execution:
       status: Literal["ok", "timeout", "error"]   # error = máy chấm không chạy được chương trình
       stdout: str
       stderr: str

   class CodeRunner(Protocol):
       async def run(self, source: str, stdin: str) -> Execution: ...
   ```
   Bản dùng bây giờ: `Judge0Runner` gọi **Judge0 CE** (`https://ce.judge0.com`, đã kiểm
   `GET /languages` → 200, có `Python (3.12.5)` id 100). Chọn runner bằng env
   `CODE_RUNNER=judge0`, `JUDGE0_URL`, `JUDGE0_TOKEN` (tuỳ chọn, gửi header `X-Auth-Token`).
   **Đổi sang self-host sau này** — hai đường, không cái nào đụng tới harness/API/app:
   (a) tự host Judge0 CE bằng docker-compose → chỉ đổi `JUDGE0_URL`; (b) viết `DockerRunner`
   cùng interface → đổi `CODE_RUNNER=docker`. Run này chỉ viết `Judge0Runner` (chưa có lần dùng
   thứ hai thật, không viết trước DockerRunner).
3. **Harness độc lập máy chấm**: `backend/app/harness.py` là một chương trình Python đọc stdin
   JSON `{code, function, cases}`, compile code người dùng với filename `solution.py` (số dòng lỗi
   = dòng của code đã gửi), chạy từng case, gom `print` của người dùng, in **một dòng kết quả
   JSON** có tiền tố cố định ra stdout. Backend gửi `source = harness`, `stdin = payload` cho
   runner, rồi parse dòng kết quả. Máy chấm nào cũng chỉ cần "chạy python với stdin".
4. **Test case dạng JSON**: `{"args": [...], "expect": {"return": v}}` hoặc
   `{"expect": {"arg": 0, "value": v}}` (hàm sửa tham số như `save_document`, `like_post`).
   Hiển thị được "input / mong đợi / nhận được" như mockup.
5. **Ghép ô ở client** (Dart, một chỗ duy nhất): `Exercise.template` chứa dòng `# TODO A`
   (thụt lề dòng đánh dấu = thụt lề của code ô A). Ghép ra `code` + `lineOrigin`. Lỗi trả về số
   dòng → client tra `lineOrigin` để tô đỏ đúng ô.
6. **"Đã xong" có một nguồn**: `ExerciseProgress.passed`, chỉ đặt khi backend trả `passed`.
   `completedBlocks` cũ thành getter suy ra (`passed ? blocks.length : 0`). "Đang làm dở" =
   `!passed && có draft`.
7. **Khoá bài kế tiếp trong cùng file code** (`CodeFile.exercises` theo thứ tự): bài k mở khi
   k = 0 hoặc bài k-1 đã `passed`. Bài dùng chung nhiều file (split-chunks) mở nếu mở ở bất kỳ
   file nào chứa nó. Không khoá xuyên file/topic.
8. **Xem lời giải**: `ExerciseProgress.solutionViewed` (set id ô). Stats/review coi ô đó là
   "không sạch". Không có nút "chép vào ô".
9. Giữ `answer_checker.dart` cho chế độ ôn tập "gõ lại" (ngoài phạm vi) và làm **gợi ý phụ** khi
   test fail mà không có số dòng lỗi: ô khác mọi `acceptedAnswers` hiện "kiểm tra lại ô này".
10. HTTP client mobile: package `http`. URL mặc định `http://127.0.0.1:8000`, đổi bằng
    `--dart-define=JUDGE_URL`. iOS cần `NSAllowsLocalNetworking`.
11. Màn mới `ExerciseScreen` ở `/exercise/:id` thay BlockListScreen + CellScreen (xoá cả hai và
    route `/exercise/:id/block/:index`). Timer/idle/timeout chuyển sang màn mới.

## Hợp đồng `/run` (dùng chung T-02 · T-04 · T-09)

```json
// request
{"exercise_id": "split-chunks", "code": "def split_chunks(text, size):\n    ..."}
// 200
{"status": "passed" | "failed" | "error" | "timeout",
 "error": null | {"kind": "syntax" | "runtime", "line": 3 | null, "message": "..."},
 "tests": [{"call": "split_chunks('hello world', 4)", "expected": "['hell', 'o wo', 'rld']",
            "actual": "['hell', 'o wo', 'rld']" | null, "passed": true}],
 "stdout": "...", "duration_ms": 812}
// 404 exercise_id lạ · 422 body sai / code > 8000 ký tự
// 503 {"detail": "runner_unavailable"} — máy chấm không trả lời / 429 / 5xx / không parse được
```

`line` = dòng 1-based **trong `code` đã gửi**. `expected`/`actual` là `repr()`.
Judge0 → `Execution`: status id 3 → `ok`; 5 (Time Limit Exceeded) → `timeout`; 13/14 hoặc lỗi
HTTP → raise → 503. Giới hạn gửi kèm: `cpu_time_limit=2`, `wall_time_limit=5`,
`memory_limit=128000`. HTTP timeout tới máy chấm 15s.

## Sổ bất biến

```text
INV-01 · Mỗi ô TODO có đúng một dòng `# TODO <label>` trong Exercise.template, thụt lề dòng đó = 4 × Block.indentLevel
         phải khớp: mobile/lib/data/seed.dart · mobile/lib/domain/merge.dart · mobile/test/seed_test.dart
         vỡ thì thấy gì: gõ đúng nhưng trả IndentationError; hoặc một ô không được ghép
INV-02 · Ghép lời giải mọi ô vào template = `solution` trong backend/app/exercises.json, và solution đó pass hết case
         phải khớp: mobile/lib/data/seed.dart · backend/app/exercises.json · mobile/test/judge_contract_test.dart · backend/tests/test_harness.py
         vỡ thì thấy gì: gõ đúng lời giải vẫn fail → bài bị khoá vĩnh viễn (vì có gating)
INV-03 · Tập exercise id trong seed = tập key trong exercises.json; functionName = `function`
         phải khớp: mobile/lib/data/seed.dart · backend/app/exercises.json · mobile/test/judge_contract_test.dart
         vỡ thì thấy gì: Run trả 404 hoặc harness báo không tìm thấy hàm
INV-04 · JSON /run của backend = model parse ở client
         phải khớp: backend/app/main.py · backend/app/harness.py · mobile/lib/data/judge_client.dart
         vỡ thì thấy gì: app báo "lỗi máy chấm" dù backend trả passed
INV-05 · error.line là dòng 1-based của code đã gửi; lineOrigin[line-1] ra đúng ô
         phải khớp: backend/app/harness.py · mobile/lib/domain/merge.dart · mobile/lib/features/exercise/code_tab.dart
         vỡ thì thấy gì: tô đỏ nhầm ô (lệch 1 dòng)
INV-06 · "Đã xong" chỉ có một nguồn: ExerciseProgress.passed; mọi nơi hiện done/đếm tiến độ suy ra từ nó
         phải khớp: session_controller.dart · session_providers.dart · exercise_row.dart · home_screen.dart · stats_screen.dart · review_controller.dart · file_crosscut_screen.dart · practice_screen.dart
         vỡ thì thấy gì: Run pass nhưng Home/topic vẫn "New", hoặc Review không có thẻ mới
INV-07 · Ô đã xem lời giải không tính điểm ở mọi nơi tính điểm
         phải khớp: session_controller.dart (solutionViewed) · stats_screen.dart · review_controller.dart
         vỡ thì thấy gì: Stats ghi "không dùng gợi ý" cho ô đã mở lời giải
INV-08 · Khoá bài: một quy tắc (progression.dart) cho ExerciseRow, nút "Bài tiếp theo", và mở thẳng route
         phải khớp: mobile/lib/domain/progression.dart · exercise_row.dart · exercise_screen.dart · code_tab.dart
         vỡ thì thấy gì: vào được bài khoá từ tab Practice, hoặc "Bài tiếp theo" dẫn vào bài khoá
INV-09 · "Đang làm dở" một định nghĩa: !passed && có draft — cho Continue card và ExerciseRow
         phải khớp: session_providers.dart (inProgressExerciseProvider) · exercise_row.dart
         vỡ thì thấy gì: Home hiện "tiếp tục" bài mà danh sách ghi "New"
INV-10 · /run chỉ phụ thuộc CodeRunner; harness không biết máy chấm nào; đổi runner không đổi JSON trả về
         phải khớp: backend/app/runner.py · backend/app/main.py · backend/app/harness.py · backend/tests/test_api.py (FakeRunner)
         vỡ thì thấy gì: thay Judge0 bằng runner khác thì timeout hiện thành "error", hoặc phải sửa main.py
INV-11 · Token máy chấm không lọt ra response, log hay git
         phải khớp: backend/app/runner.py · backend/app/main.py · backend/.gitignore · backend/.env.example
         vỡ thì thấy gì: `JUDGE0_TOKEN` xuất hiện trong body 503 hoặc trong file đã commit
```

Checklist "chính thức": khái niệm **"bài đã xong"** — hiện có `ExerciseProgress.completedBlocks`
(int); mới thêm `passed` (bool). Quan hệ: **cái cũ suy ra từ cái mới**. Test vỡ khi lệch: T-06.

## Task (balanced — không override model)

Chung cho mọi task worker: không "tiêm lỗi tạm", không `git checkout --`/`git stash`; output
ví dụ phải lấy từ `python3` thật. Thư mục làm việc = `$WT` tuyệt đối.

| ID | Role · Tier · Model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | `crew-impl-standard` · T2 · sonnet | Harness (chương trình stdin→JSON, Python 3.12 tương thích) + dữ liệu 5 bài | `backend/requirements.txt`, `backend/.gitignore`, `backend/app/__init__.py`, `backend/app/harness.py`, `backend/app/exercises.json`, `backend/tests/test_harness.py` | `cd backend && .venv/bin/python -m pytest -q tests/test_harness.py` |
| T-02 | orchestrator (public API + secret + tích hợp ngoài) | `CodeRunner` + `Judge0Runner` + FastAPI `/run` + README + `.env.example` | `backend/app/runner.py`, `backend/app/main.py`, `backend/tests/test_api.py`, `backend/README.md`, `backend/.env.example` | `cd backend && .venv/bin/python -m pytest -q` |
| T-03 | `crew-impl-standard` · T2 · sonnet | Model (template, challenge, label, explanation), `merge.dart`, chuyển 5 bài sang dạng mới | `mobile/lib/domain/models.dart`, `mobile/lib/domain/merge.dart`, `mobile/lib/data/seed.dart`, `mobile/test/seed_test.dart`, `mobile/test/merge_test.dart` | `cd mobile && flutter test test/seed_test.dart test/merge_test.dart` |
| T-04 | `crew-impl-standard` · T2 · sonnet | Judge client (`http`), Info.plist, contract test xuyên ngôn ngữ (INV-02/03) | `mobile/pubspec.yaml`(+lock), `mobile/ios/Runner/Info.plist`, `mobile/lib/data/judge_client.dart`, `mobile/test/judge_client_test.dart`, `mobile/test/judge_contract_test.dart` | `cd mobile && flutter test test/judge_client_test.dart test/judge_contract_test.dart` |
| T-05 | `crew-impl-standard` · T2 · sonnet | Tách editor: nhiều ô trên một màn, một thanh gợi ý + phím ký hiệu dùng chung bám ô đang focus, key theo ô | `mobile/lib/features/exercise/code_input.dart`, `mobile/test/code_input_test.dart` | `cd mobile && flutter test test/code_input_test.dart` |
| T-06 | `crew-impl-standard` · T2 · sonnet | Tiến độ mới (passed, drafts/hint theo ô, solutionViewed) + quy tắc khoá | `mobile/lib/features/exercise/session_controller.dart`, `session_providers.dart`, `mobile/lib/domain/progression.dart`, `mobile/test/session_controller_test.dart`, `mobile/test/progression_test.dart` | `cd mobile && flutter test test/session_controller_test.dart test/progression_test.dart` |
| T-07 | `crew-impl-standard` · T2 · sonnet | Nơi đọc tiến độ: ExerciseRow (khoá + trạng thái), Stats, Review theo INV-06/07/09 | `mobile/lib/features/browse/exercise_row.dart`, `mobile/lib/features/stats/stats_screen.dart`, `mobile/lib/features/review/review_controller.dart`, `mobile/test/review_stats_test.dart`, `mobile/test/browse_screens_test.dart` | `cd mobile && flutter test test/review_stats_test.dart test/browse_screens_test.dart` |
| T-08 | `crew-impl-standard` · T2 · sonnet | `ExerciseScreen` (header + timer/idle + TabBar) + tab Challenge + tab Solution + route | `mobile/lib/features/exercise/exercise_screen.dart`, `challenge_tab.dart`, `solution_tab.dart`, `mobile/lib/app/router.dart`, `mobile/test/exercise_screen_test.dart` | `cd mobile && flutter test test/exercise_screen_test.dart` |
| T-09 | `crew-impl-standard` · T2 · sonnet | Tab Code: notebook (ô khoá + ô TODO), Run tất cả → judge → Out (code đã ghép + bảng test + tô ô lỗi) → pass thì "Bài tiếp theo" | `mobile/lib/features/exercise/code_tab.dart`, `mobile/lib/features/exercise/run_result_view.dart`, `mobile/test/code_tab_test.dart` | `cd mobile && flutter test test/code_tab_test.dart` |
| T-10 | `crew-impl-standard` · T2 · sonnet | Xoá màn cũ + test cũ, chuyển test idle, sửa app_flow đi từ Home | xoá `block_list_screen.dart`, `cell_screen.dart`, `test/cell_layout_test.dart`; `test/cell_idle_test.dart`→`test/exercise_idle_test.dart`; sửa `test/app_flow_test.dart` | `cd mobile && flutter analyze && flutter test` |

Mỗi task: **Forbidden** = mọi file ngoài Owned (task mobile cấm `backend/**`, task backend cấm
`mobile/**`; cấm `planning/**`). **Evidence** = `git diff --stat -- <owned>` (+ `git status
--porcelain` cho file mới/xoá). **Thứ tự trong task**: phần rủi ro trước — T-01 viết harness +
test syntax/runtime error/số dòng trước dữ liệu; T-03 viết `merge.dart` + test trước khi chuyển
seed; T-05 làm thanh dùng chung trước, giữ CodeInput cũ chạy được cho CellScreen tới T-10.
Contract đủ 9 mục ghi vào `tasks/T-NN.md` ở đầu P2.

Acceptance chính:
- **T-01**: case `return`/`arg` chấm đúng; SyntaxError/exception trả `line` đúng dòng code gửi;
  `print` của người dùng không làm hỏng dòng kết quả; reference solution cả 5 bài pass; chạy được
  trên Python 3.12.
- **T-02**: trước khi viết, tôi gọi thật `POST /submissions?base64_encoded=true&wait=true` lên
  Judge0 CE với chương trình 1 dòng để xác minh field trả về (theo pattern "xác minh API ngoài ở
  P1"). Test API dùng `FakeRunner` (không gọi mạng); một test `@pytest.mark.live` gọi Judge0 thật,
  mặc định skip. Máy chấm lỗi → 503, body không chứa token.
- **T-03**: template mỗi bài ngắn nhất (khoá `def` + khởi tạo), mỗi ô TODO 1 dòng (tối đa 2);
  `challenge` có ví dụ nhỏ + ví dụ dự án thật.
- **T-04**: lỗi mạng/503/JSON hỏng → "không kết nối được máy chấm", không crash.
- **T-09**: chỉ `status == passed` mới gọi `markPassed`; ô lỗi viền đỏ theo `lineOrigin`.

## Thứ tự + checkpoint

- **Wave 1** (song song, ownership rời): T-01 · T-03 · T-05.
- **Wave 2**: T-02 (tôi, sau T-01) · T-04 (sau T-01 + T-03) · T-06 (sau T-03).
- **Checkpoint 1**: `pytest -q` backend + `flutter analyze` + test của T-01..T-06. Test màn cũ
  (`app_flow`, `cell_*`, `phase2`) được phép đỏ tới T-10 — ghi danh sách vào STATUS.
- **Wave 3**: T-07 · T-08 (song song).
- **Wave 4**: T-09 → T-10.
- **Checkpoint 2 (cuối)**: `flutter analyze && flutter test` xanh toàn bộ + `pytest -q`.

## Verification (e2e — orchestrator tự chạy, gọi Judge0 thật)

1. `cd backend && .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000` (nền).
2. `curl` POST `/run` lời giải split-chunks → `passed`, 3/3 test.
3. Bỏ dòng `return` → `failed`, `actual` = `None`.
4. Lỗi cú pháp ở dòng 4 → `error`, `line: 4`.
5. `while True: pass` → `timeout`.
6. `JUDGE0_URL` trỏ sai → 503 `runner_unavailable`, body không có token.
7. **Mối nối** trên simulator, bắt đầu từ Home: Topic Chunking → overlap-chunks đang khoá → mở
   split-chunks (≤2 chạm) → gõ 3 ô → Run → passed → Home/topic hiện split-chunks "Done",
   overlap-chunks mở khoá, "Bài tiếp theo" vào overlap-chunks. Mở Solution 1 ô ở bài khác →
   Stats không tính ô đó là sạch.
8. Reviewer mối nối trả lời INV-01..INV-11 → `verify-seam.sh` exit 0 → commit, PR `Closes` issue cha.

## Giới hạn đã biết (nói trước)

- **Code học viên được gửi tới máy chủ Judge0 công khai** (bên thứ ba): không gửi gì ngoài code
  bài tập, nhưng đừng dùng instance này cho dữ liệu nhạy cảm. Giới hạn tần suất theo IP, không
  công bố con số cụ thể — đủ cho dev local, không đủ cho production → khi đó tự host.
- Chỉ chạy local; điện thoại thật và Android emulator (`10.0.2.2`, cleartext) chưa làm.
- Không chống gian lận: code học viên chạy cùng tiến trình với harness, cố tình in kết quả giả
  thì tự lừa mình — chấp nhận cho app học.
- Tiến độ vẫn in-memory (Hive là việc khác của issue #5).
