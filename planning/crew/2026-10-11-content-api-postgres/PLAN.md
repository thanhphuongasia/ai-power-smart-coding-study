# Run `content-api-postgres` — nội dung học lưu Postgres, app tải qua API (có cache offline)

## Context

Sau PR #9 (chưa merge, branch `crew/2026-10-11-exercise-tabs-judge`): backend FastAPI chỉ có
`POST /run`; test + lời giải ở `backend/app/exercises.json`. Toàn bộ nội dung học (theme → topic
→ file → exercise → ô TODO, challenge, template, hint, lời giải) viết cứng trong
`mobile/lib/data/seed.dart`, đọc **đồng bộ** ở 11 file `lib` (progression, session_controller,
session_providers, exercise_screen, review_controller, stats, home, theme/topic detail,
file_crosscut, practice) và 10 file test. App không có chỗ async/AsyncValue nào, model không có
`fromJson`. Thêm bài = sửa Dart + build lại app.

User đã chốt: **Postgres**; **app lấy nội dung qua API**; **run này chỉ nội dung** (tiến độ vẫn
in-memory, đồng bộ tiến độ để run sau cùng đăng nhập); **cache nội dung trên máy** để mở offline.

Git: stacked trên PR #9 — worktree tách từ `crew/2026-10-11-exercise-tabs-judge`, PR mới base vào
branch đó. Lưu ý: `main` đang có thay đổi chưa commit (streak chip ở `home_screen.dart`, không phải
của run nào) — có thể conflict với run này khi merge.

## Quyết định thiết kế

1. **Một file nguồn soạn nội dung** `backend/content/content.json` = toàn bộ nội dung + phần chấm
   bài (`judge: {solution, cases}`) của từng bài. Thay `backend/app/exercises.json` (xoá).
   Lệnh `python -m app.load_content` nạp file vào Postgres trong **một transaction, thay toàn bộ**
   (idempotent) và tính `version` = sha256 của payload `/content`.
2. **Postgres = nguồn chính thức lúc chạy** cho cả `/content` và `/run`. Schema quan hệ, quản lý
   bằng **Alembic** (SQLAlchemy 2.1 + psycopg 3, sync session — 5 bài, không cần async DB):
   `themes`, `topics`, `code_files`, `exercises` (challenge `jsonb`, `judge_solution`,
   `judge_cases jsonb`), `file_exercises` (N–N có `position`: split-chunks nằm ở 2 file), `blocks`,
   `content_meta(version)`. `DATABASE_URL` mặc định `postgresql+psycopg://localhost:5432/smart_coding_study`
   (Postgres 15 Homebrew đang chạy cổng 5432).
3. **`GET /content`** trả cả cây trong một lần (nội dung nhỏ): `{version, themes[...], exercises{id: …}}`;
   file chỉ chứa `exercise_ids` (bài dùng chung xuất hiện một lần). **Không bao giờ trả `judge`**.
   Đọc DB bằng 6 query cố định (không N+1).
4. **App**: `ContentRepository` = `GET /content` (timeout 5s) + cache `shared_preferences` (một chuỗi
   JSON + version). Lúc mở app: mạng OK → dùng + ghi cache; mạng lỗi → dùng cache + banner "Đang dùng
   nội dung đã lưu"; không có cache → màn lỗi + "Thử lại". `contentProvider` (AsyncNotifier) +
   `ContentGate` bọc app: loading / lỗi / dữ liệu.
5. **Đổi từng bước, suite luôn xanh**: (a) thêm `Content` (index + `fromJson`/`toJson`) và
   `contentIndexProvider` mặc định = seed hiện tại → (b) chuyển mọi nơi đọc sang provider → (c) gắn
   tải API + cache, override provider ở app thật → (d) xoá nội dung khỏi `seed.dart`, test dùng
   fixture đọc `../backend/content/content.json`.
6. Dữ liệu **demo tiến độ** (`seedPassedExercises`, `seedDrafts`, activity, lịch ôn) và **Admin
   PendingContent** không phải nội dung học → giữ trong app (`demo_seed.dart`), ngoài phạm vi.
7. Tiến độ khoá theo `exercise.id` + `block.label` — id phải ổn định giữa các version nội dung
   (đổi id trên server = tiến độ cũ mồ côi; ghi vào giới hạn).

## Hợp đồng `GET /content` (T-02 · T-05 · T-06 dùng chung, snake_case)

```json
{"version": "sha256:…",
 "themes": [{"id": "rag", "name": "…", "description": "…", "tags": ["python"],
   "topics": [{"id": "rag-chunking", "name": "…", "description": "…",
     "files": [{"id": "rag-chunker-py", "name": "chunker.py", "exercise_ids": ["split-chunks", "overlap-chunks"]}]}]}],
 "exercises": {"split-chunks": {"id": "split-chunks", "title": "…", "function_name": "split_chunks",
   "params": ["text", "size"], "template": "def …\n    # TODO A …",
   "challenge": {"statement": "…", "motivation": "…",
     "small": {"caption": "…", "input": "…", "output": "…", "note": null},
     "project": {"caption": "…", "input": "…", "output": "…", "note": "…"}},
   "blocks": [{"id": "split-chunks-a", "label": "A", "title": "…", "prompt": "…", "indent_level": 1,
     "accepted_answers": ["…"], "expected_output": "…", "explanation": "…", "hints": ["…","…","…"], "vocab": ["…"]}]}}}
```
`content.json` = cùng shape + `"judge": {"solution": "...", "cases": [...]}` trong mỗi exercise.
`/run` giữ nguyên hợp đồng PR #9; chỉ đổi nguồn đọc function/cases sang DB.

## Sổ bất biến

```text
INV-01 · /content JSON = Content.fromJson ở Dart (đủ field, đúng tên snake_case, đúng kiểu, note nullable)
         phải khớp: backend/app/content_api.py · mobile/lib/domain/content.dart · mobile/test/content_json_test.dart
         vỡ thì thấy gì: app kẹt màn lỗi / thiếu challenge dù server trả 200
INV-02 · /content KHÔNG chứa judge (solution đầy đủ, cases)
         phải khớp: backend/app/content_api.py · backend/tests/test_content_api.py
         vỡ thì thấy gì: test case lộ ra app (curl /content | grep cases có kết quả)
INV-03 · DB là nguồn duy nhất cho /content và /run; không còn exercises.json; id bài ở /run = id ở /content
         phải khớp: backend/app/main.py · backend/app/content_api.py · backend/app/load_content.py
         vỡ thì thấy gì: thêm bài vào content.json + nạp → /content có, /run trả 404
INV-04 · Ghép lời giải các ô vào template = judge.solution, và solution pass hết cases (giữ INV-02 cũ của PR #9)
         phải khớp: backend/content/content.json · mobile/test/content_contract_test.dart · backend/tests/test_harness.py
         vỡ thì thấy gì: gõ đúng vẫn fail → bài khoá vĩnh viễn
INV-05 · Marker `# TODO <label>` mỗi ô đúng một lần, thụt = 4 × indent_level (giữ INV-01 cũ)
         phải khớp: backend/content/content.json · mobile/lib/domain/merge.dart · mobile/test/content_contract_test.dart
         vỡ thì thấy gì: IndentationError khi gõ đúng
INV-06 · Nạp nội dung là thay toàn bộ trong một transaction; nạp 2 lần ra cùng version, cùng dữ liệu
         phải khớp: backend/app/load_content.py · backend/tests/test_load_content.py
         vỡ thì thấy gì: bài trùng / bài đã xoá khỏi content.json vẫn còn trên /content
INV-07 · "Nội dung hiện hành" một nguồn ở app: mọi nơi trong mobile/lib đọc qua contentIndexProvider; không file lib nào import nội dung từ seed
         phải khớp: mobile/lib/data/content_providers.dart · progression.dart · session_controller.dart · session_providers.dart · exercise_screen.dart · review_controller.dart · stats_screen.dart · home_screen.dart · theme_detail_screen.dart · topic_detail_screen.dart · file_crosscut_screen.dart · practice_screen.dart
         vỡ thì thấy gì: thêm bài trên server → Home có, Practice/Stats không
INV-08 · Cache: offline dùng đúng bản lần tải thành công gần nhất; online thì ghi đè cache bằng bản mới (version mới)
         phải khớp: mobile/lib/data/content_repository.dart · mobile/test/content_repository_test.dart
         vỡ thì thấy gì: sửa nội dung trên server, mở lại app vẫn thấy bản cũ dù có mạng
INV-09 · App không bao giờ dựng màn nội dung trước khi content sẵn sàng (ContentGate); router/deep link không vượt gate
         phải khớp: mobile/lib/app/content_gate.dart · mobile/lib/main.dart · mobile/lib/app/router.dart
         vỡ thì thấy gì: crash StateError "content chưa nạp" khi mở app chậm mạng
INV-10 · Tiến độ (in-memory) khoá theo exercise.id/block.label của nội dung; nạp lại nội dung không xoá tiến độ của bài còn tồn tại
         phải khớp: mobile/lib/features/exercise/session_controller.dart · mobile/lib/data/content_providers.dart
         vỡ thì thấy gì: bấm Thử lại / làm mới nội dung → bài đã pass thành "Mới"
```

Checklist "chính thức" — khái niệm **"nội dung hiện hành"**: hiện có ở `seed.dart`
(`seedThemes`); mới thêm `content.json` (soạn), bảng Postgres (chạy), cache trên máy (offline).
Quan hệ: `content.json` →(load_content)→ **Postgres (chính thức)** →(`/content`)→ app → cache
(bản sao của lần tải gần nhất). `seed.dart` bị xoá nội dung ở T-09. Sửa trực tiếp DB sẽ bị lần nạp
sau ghi đè — README nói rõ. Test vỡ khi lệch: INV-03/06/08.

## Task (balanced — không override model)

Chung cho worker: không "tiêm lỗi tạm", không `git checkout --`/`git stash`; output thật.

| ID | Role · Tier · Model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | orchestrator (L4 schema/migration) | SQLAlchemy tables + Alembic 0001 + `db.py` + fixture test DB | `backend/requirements.txt`, `backend/alembic.ini`, `backend/migrations/env.py`, `backend/migrations/versions/0001_content.py`, `backend/app/db.py`, `backend/app/tables.py`, `backend/tests/conftest.py` | `cd backend && .venv/bin/python -m pytest -q` |
| T-02 | `crew-impl-standard` · T2 · sonnet | Xuất `content.json` từ seed hiện tại + judge từ exercises.json; `load_content.py` | `backend/content/content.json`, `backend/app/load_content.py`, `backend/tests/test_load_content.py` | `cd backend && .venv/bin/python -m pytest -q tests/test_load_content.py` |
| T-03 | `crew-impl-standard` · T2 · sonnet | `Content` (index: exerciseById/locateExercise/uniqueExercises/locateFilesNamed) + `fromJson/toJson` mọi model + `contentIndexProvider` mặc định = seed | `mobile/lib/domain/models.dart`, `mobile/lib/domain/content.dart`, `mobile/lib/data/content_providers.dart`, `mobile/test/content_json_test.dart` | `cd mobile && flutter test test/content_json_test.dart && flutter analyze` |
| T-04 | `crew-impl-standard` · T2 · sonnet | Chuyển nơi đọc phía exercise sang provider | `mobile/lib/domain/progression.dart`, `mobile/lib/features/exercise/session_controller.dart`, `session_providers.dart`, `exercise_screen.dart`, `code_tab.dart` | `cd mobile && flutter analyze && flutter test` |
| T-05 | `crew-impl-standard` · T2 · sonnet | Chuyển nơi đọc phía browse/practice/stats/review | `home_screen.dart`, `theme_detail_screen.dart`, `topic_detail_screen.dart`, `file_crosscut_screen.dart`, `practice_screen.dart`, `stats_screen.dart`, `review_controller.dart` | `cd mobile && flutter analyze && flutter test` |
| T-06 | orchestrator (public API) | `GET /content` + `/run` đọc DB + xoá exercises.json + README | `backend/app/content_api.py`, `backend/app/main.py`, `backend/tests/test_content_api.py`, `backend/tests/test_api.py`, `backend/tests/test_harness.py`, `backend/README.md`, xoá `backend/app/exercises.json` | `cd backend && .venv/bin/python -m pytest -q` |
| T-07 | `crew-impl-standard` · T2 · sonnet | `ContentRepository` (http + shared_preferences) + `contentProvider` async | `mobile/pubspec.yaml`(+lock), `mobile/lib/data/content_repository.dart`, `mobile/lib/data/content_providers.dart`, `mobile/test/content_repository_test.dart` | `cd mobile && flutter test test/content_repository_test.dart && flutter analyze` |
| T-08 | `crew-impl-standard` · T2 · sonnet | `ContentGate` (loading / lỗi + Thử lại / banner offline) + `main.dart` | `mobile/lib/app/content_gate.dart`, `mobile/lib/main.dart`, `mobile/test/content_gate_test.dart` | `cd mobile && flutter test test/content_gate_test.dart && flutter analyze` |
| T-09 | `crew-impl-standard` · T2 · sonnet | Xoá nội dung khỏi seed (giữ demo progress → `demo_seed.dart`), fixture test đọc content.json, sửa mọi test | `mobile/lib/data/seed.dart`→`demo_seed.dart`, `mobile/test/support/content_fixture.dart`, `mobile/test/content_contract_test.dart` (thay `judge_contract_test` + luật của `seed_test`), các test đang import seed | `cd mobile && flutter analyze && flutter test` |

T-05/T-09 vượt 5 file nhưng là thay thế cơ học cùng một mẫu (đọc `seedThemes` → `ref.watch(contentIndexProvider)`).
Mỗi task: **Forbidden** = ngoài Owned; **Evidence** = `git status --porcelain -- <owned>`; contract đủ
9 mục ghi `tasks/T-NN.md` đầu P2.

## Thứ tự + checkpoint

- **Wave 1**: T-01 (tôi) · T-03.
- **Wave 2**: T-02 (sau T-01 + T-03) · T-04 · T-05 (sau T-03; T-04/T-05 không chung file).
- **Checkpoint 1**: backend pytest + `flutter analyze && flutter test` xanh (app vẫn chạy bằng seed qua provider).
- **Wave 3**: T-06 (tôi, sau T-02) · T-07 (sau T-03).
- **Wave 4**: T-08 → T-09.
- **Checkpoint 2**: toàn bộ xanh, `grep -rn "seedThemes\|exerciseById\|uniqueExercises" mobile/lib` chỉ còn ở `content.dart`.

## Verification (e2e — orchestrator tự chạy)

1. `createdb smart_coding_study` → `alembic upgrade head` → `python -m app.load_content` (2 lần: cùng version).
2. `curl /content`: 3 theme, 5 bài, split-chunks ở 2 file, `grep -c judge\|cases` = 0.
3. `curl /run` lời giải 5 bài (Judge0 thật) → passed (đọc từ DB).
4. **Mối nối**: sửa title một bài trong `content.json` → nạp lại → mở app (simulator) thấy title mới **không build lại app**; tiến độ bài đã pass vẫn giữ.
5. Tắt backend → mở lại app: hiện nội dung từ cache + banner offline; xoá cache + tắt backend → màn lỗi, bật backend → "Thử lại" vào được Home.
6. Từ Home → làm split-chunks → Run → Bài tiếp theo (luồng PR #9 vẫn đúng trên nội dung từ API).
7. Reviewer mối nối INV-01..INV-10 → `verify-seam.sh` exit 0 → PR (base `crew/2026-10-11-exercise-tabs-judge`), `Related to #5`.

## Giới hạn đã biết

- Tiến độ chưa lên server (run sau, cùng đăng nhập). Admin PendingContent vẫn in-memory.
- Đổi `id` bài/ô trên server làm tiến độ local của bài đó mồ côi.
- Sửa trực tiếp DB bị lần `load_content` sau ghi đè — nguồn soạn là `content.json`.
- Chưa có màn soạn nội dung; thêm bài = sửa `content.json` + nạp lại (không cần build app).
- Stacked PR: phải merge PR #9 trước.
