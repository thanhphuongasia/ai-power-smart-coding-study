# /crew — Issue #31: chế độ học System Design (Phase 1 Đọc + Phase 2 Thực chiến)

Run: `planning/crew/2026-10-12-system-design-mode/` · Branch `crew/2026-10-12-system-design-mode`
Issue cha: **#31** (đã có, dùng lại, không tạo mới). Mockup: artifact `9yGHzgh2nk2Kci8z14zm4r` v4.

## Context

Admin nhập `.md` → app chia chapter/section/card → học viên lướt đọc liền mạch, lưu tiến độ, vào
Phase 2 tự viết thiết kế 6 task, chấm từ khoá ngay, Claude chat chấm sâu qua MCP, app hiện feedback,
nhiều lần thử. Danh sách section/task **giống Duolingo**. SRS card SD để lượt sau (issue vẫn còn mở).

## Phát hiện P0/P1 làm đổi plan cũ

| Phát hiện | Hệ quả |
|---|---|
| Nhánh hiện tại `ci/deploy-vps-on-merge` **cũ hơn `origin/main` 19 commit** (đã có reskin #29/#30) | Worktree base **`origin/main`**, không phải HEAD. Sau `worktree add` chạy `git branch --unset-upstream` rồi `push -u` (failure đã ghi ở MEMORY) |
| Reskin đổi nav: dưới 700px là `NavigationBar` (`Key('bottom-nav')`) 4 tab; từ 700px là top bar + drawer (`app_drawer.dart:81`) | Thêm tab thứ 5 "Design" ở **ba chỗ** khớp index: branch `router.dart:32-64`, destination `app_shell.dart:42-71`, `_nav` drawer — thêm **cuối** để không đổi key `drawer-nav-$i`. Test cũ (`app_drawer_test`, `issue29_e2e_test`, `phase2_screens_test`) đếm tab: T-06 sửa |
| Font app là Nunito, **không có serif** | Bundle Source Serif 4 (OFL) cho màn đọc, khai trong `pubspec.yaml` |
| Đã có màu `success`(xanh lá), `primary`(xanh dương), `primaryDark`, `successDark` | `DuoPath` dùng token sẵn có, **không sửa `AppPalette`** (tránh vỡ `theme_test`). Nền trắng của tờ đọc là hằng riêng của màn đọc |
| Migration mới nhất `0006`, không PR mở | Dùng `0007`. Fetch lại trước mỗi wave và trước PR; `test_single_head` bắt 2 head |
| Có 4 worktree crew khác đang tồn tại | Không đụng; đọc `git worktree list` trước khi dọn |

## Quyết định thiết kế (đã duyệt, rút gọn)

1. Bảng `sd_*` riêng, ngoài `load_content` và hàng chờ duyệt; doc có `status` (`draft`/`published`).
2. Quy ước md: `#` tên · `## Bối cảnh` → card bối cảnh · `## Thực chiến` (mỗi `###` là task: `Đề:`,
   `Gợi ý:`, `Rubric:` dạng `ý :: từ khoá, từ khoá`, `Đáp án mẫu: <section>`) · `##` khác = chapter,
   `###` = section, mỗi khối = card. **Chờ user đưa file `.md` thật để xác nhận trước T-02.**
3. `card_id = sha1(nội dung chuẩn hoá)[:8]`; tiến độ không FK vào content.
4. Server tính `done`/`unlocked`; rubric, từ khoá, điểm là server-owned, không bao giờ ra client.
5. `Evaluator` interface (mẫu `CodeRunner`) + `KeywordEvaluator`; lần thử `status=auto`, MCP ghi `reviewed`.
6. Mỗi lần nộp một dòng `sd_attempts`; ≤8KB/câu, ≤20 lần/task/ngày; xong task khi có ≥1 lần thử.
7. MCP: `sd_list_attempts`, `sd_get_attempt`, `sd_submit_feedback`; qua `authorize_sub`, không có tool xoá.

## Sổ bất biến

```text
INV-01 · Nhập lại doc không xoá tiến độ của card không đổi
         phải khớp: backend/app/sd/parser.py · backend/app/sd/admin.py · backend/app/sd/learner.py
         vỡ thì thấy gì: sửa 1 card rồi nhập lại, học viên mất dấu "đã đọc" của cả section
INV-02 · Response cho học viên không chứa rubric/từ khoá/điểm nội bộ
         phải khớp: backend/app/sd/learner.py · backend/app/sd/attempts.py · mobile/lib/data/sd_repository.dart
         vỡ thì thấy gì: GET /api/sd/docs/{id} trả field "keywords"; app lộ đáp án
INV-03 · Feedback reviewed (từ MCP) thắng auto; API và app hiện cùng một bản
         phải khớp: backend/app/sd/attempts.py · backend/app/mcp_server.py · mobile/lib/features/system_design/task_screen.dart
         vỡ thì thấy gì: Claude ghi feedback xong nhưng app vẫn hiện điểm từ khoá
INV-04 · Trạng thái khoá/xong của node chỉ tính ở server; DuoPath chỉ vẽ
         phải khớp: backend/app/sd/learner.py · mobile/lib/features/system_design/duo_path.dart
         vỡ thì thấy gì: node mở khoá ở app nhưng PUT progress bị 409, hoặc ngược lại
INV-05 · Tab Design không đổi hành vi code mode (progress code, review, practice)
         phải khớp: mobile/lib/app/router.dart · mobile/lib/features/shell/app_shell.dart · mobile/lib/features/shell/app_drawer.dart
         vỡ thì thấy gì: bấm tab Review nhảy sang Design (lệch index branch/destination)
INV-06 · Câu trả lời của học viên A không đọc được bởi học viên B qua mọi đường (API, MCP)
         phải khớp: backend/app/sd/attempts.py · backend/app/mcp_server.py · backend/app/mcp_access.py
         vỡ thì thấy gì: sd_get_attempt trả attempt của user khác cho tài khoản không có quyền
```

## Task contract

Chung: validation backend = `cd $WT/backend && TEST_DATABASE_URL=postgresql+psycopg://localhost:5432/smart_coding_study_test_sd /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study/backend/.venv/bin/python -m pytest -q <test>` (worktree không có `.venv`; dùng venv của thư mục gốc, DB test riêng vì DB dùng chung hay đỏ). Validation mobile = `cd $WT/mobile && flutter pub get && flutter test <test>`. Forbidden chung: `mobile/ios/**`, `package-lock`, `backend/content/content.json`, `deploy/**`, mọi file của `load_content`/`review.py` (trừ khi nêu). Evidence = `git diff --stat -- <owned>`. Ít nhất sửa theo thứ tự rủi ro cao trước.

| ID | Role · tier · model | Objective | Owned files (phải sửa) | Acceptance | Validation (1 lệnh) |
|---|---|---|---|---|---|
| T-01 | orchestrator · L4 · (session) | Schema + migration | `backend/app/tables.py`, `backend/migrations/versions/0007_system_design.py`, `backend/tests/test_sd_schema.py` | 5 bảng `sd_docs/sd_sections/sd_tasks/sd_progress/sd_attempts`; không FK từ progress/attempt vào content; downgrade chạy; một head | pytest `tests/test_sd_schema.py` |
| T-02 | orchestrator · L4 · (session) | Parser md + import admin | `backend/app/sd/__init__.py`, `backend/app/sd/parser.py`, `backend/app/sd/admin.py`, `backend/app/main.py`, `backend/tests/test_sd_admin.py` | POST `/api/admin/sd/docs` upsert theo slug, ≤1MB, `_bad_text`, 403 trước 422, card_id ổn định, nhập lại giữ progress (INV-01) | pytest `tests/test_sd_admin.py` |
| T-03 | orchestrator · L4 · (session) | API học viên + tiến độ | `backend/app/sd/learner.py`, `backend/app/main.py`, `backend/tests/test_sd_learner.py` | GET docs/doc không chứa rubric; PUT progress đánh dấu card; server trả `done`/`unlocked` (INV-02, INV-04); doc `draft` không hiện | pytest `tests/test_sd_learner.py` |
| T-04 | orchestrator · L4 · (session) | Attempts + evaluator | `backend/app/sd/attempts.py`, `backend/app/sd/evaluator.py`, `backend/app/main.py`, `backend/tests/test_sd_attempts.py` | POST attempt chấm từ khoá, lưu n lần, trần 8KB/20 lượt/ngày, user chỉ đọc attempt của mình (INV-06), mutant: bỏ từ khoá → ý rớt | pytest `tests/test_sd_attempts.py` |
| T-05 | orchestrator · L4 · (session) | MCP xem attempt + ghi feedback | `backend/app/mcp_server.py`, `backend/app/mcp_access.py`, `backend/app/sd/attempts.py`, `backend/tests/test_sd_mcp.py` | 3 tool, `authorize_sub` mỗi lần, `reviewed` thắng `auto` (INV-03), không tool xoá, đọc attempt user khác cần quyền (INV-06) | pytest `tests/test_sd_mcp.py` |
| T-06 | `crew-impl-standard` · T2 · sonnet | Nền Flutter + tab Design | `mobile/lib/domain/sd_models.dart`, `mobile/lib/data/sd_repository.dart`, `mobile/lib/app/router.dart`, `mobile/lib/features/shell/app_shell.dart`, `mobile/lib/features/shell/app_drawer.dart` | Model + repo + provider; tab thứ 5 khớp index ở 3 chỗ, drawer thêm cuối; sửa các test đếm tab (xem T-06 phụ) | `flutter test test/app_drawer_test.dart test/issue29_e2e_test.dart test/phase2_screens_test.dart` |
| T-06b | cùng worker T-06 (nối tiếp, vì cùng test) | Sửa test nav | `mobile/test/app_drawer_test.dart`, `mobile/test/issue29_e2e_test.dart`, `mobile/test/phase2_screens_test.dart`, `mobile/test/sd_repository_test.dart` | Test chạm tab/branch cập nhật; test repo parse JSON, không đọc field rubric | như T-06 |
| T-07 | `crew-impl-standard` · T2 · sonnet (song song với T-06) | Widget kiểu Duolingo | `mobile/lib/features/system_design/duo_path.dart`, `mobile/test/duo_path_test.dart` | Banner xanh lá "PHẦN i · k/n"; đĩa tròn 3D zigzag (đáy tối hơn); node hiện tại xanh dương + quầng + bóng "BẮT ĐẦU"; khoá xám; xong xanh lá + tick; chỉ nhận dữ liệu, không tự tính khoá (INV-04); dùng token sẵn có | `flutter test test/duo_path_test.dart` |
| T-08 | `crew-impl-standard` · T2 · sonnet | Danh sách doc + lộ trình section | `mobile/lib/features/system_design/sd_docs_screen.dart`, `mobile/lib/features/system_design/sd_path_screen.dart`, `mobile/lib/app/router.dart`, `mobile/test/sd_path_screen_test.dart` | Từ tab Design vào doc ≤2 chạm; Phase 1/Phase 2 hiện đúng; node khoá bấm hiện toast; test bắt đầu từ màn chính | `flutter test test/sd_path_screen_test.dart` |
| T-09 | `crew-impl-standard` · T2 · sonnet | Màn đọc toàn màn hình | `mobile/lib/features/system_design/reader_screen.dart`, `mobile/lib/features/system_design/block_renderer.dart`, `mobile/pubspec.yaml`, `mobile/assets/fonts/SourceSerif4-Regular.ttf`, `mobile/test/sd_reader_test.dart` | Thanh trên tối + tiến độ, tờ trắng bo góc luôn trắng cả dark mode, serif; render text/bảng/code/callout; lướt qua card thì PUT progress (debounce); mở lại nhảy tới card chưa đọc | `flutter test test/sd_reader_test.dart` |
| T-10 | `crew-impl-standard` · T2 · sonnet | Phase 2 | `mobile/lib/features/system_design/context_screen.dart`, `mobile/lib/features/system_design/tasks_screen.dart`, `mobile/lib/features/system_design/task_screen.dart`, `mobile/lib/app/router.dart`, `mobile/test/sd_task_flow_test.dart` | Bối cảnh → danh sách task (DuoPath) → task: gợi ý, ô viết, nộp, lịch sử lần thử, feedback `reviewed` thắng `auto` (INV-03); hết tab không mất bản nháp | `flutter test test/sd_task_flow_test.dart` |

Ghi chú tách task: backend T-01→T-05 **tuần tự** (cùng `main.py`/`attempts.py`); Flutter T-06 ∥ T-07, rồi T-08 → T-09 → T-10 **tuần tự** vì cùng `router.dart`. Checkpoint full test sau T-05 và sau T-08. Docs (`docs/modules/sd-study.md`, ARCHITECTURE, DECISIONS) do `crew-distill` ở P5, không phải task.

## Thứ tự và wave

Wave 1: T-01 → T-02 (xin file `.md` thật của user trước T-02). Wave 2: T-03, T-04 (rủi ro cao làm sớm).
Checkpoint: `pytest -q` toàn bộ. Wave 3: T-05 ∥ T-06+T-06b ∥ T-07. Wave 4: T-08 → T-09. Wave 5: T-10.
Mỗi wave đầu: `git fetch origin` và kiểm `alembic heads`.

## Review

Mọi task L4: `crew-review` **và** `crew-review-external` song song vòng đầu, prompt ghi nguyên lệnh
`EXTERNAL_AGENT_TIMEOUT=360 ... </dev/null`. Reviewer chạy mutant trên **bản sao ngoài git** (không
`git stash`/`checkout`). Sau mọi task: reviewer mối nối trả lời INV-01..06 → `reviews/SEAM.md`, rồi
`verify-seam.sh`. Tên bất biến chỉ `INV-NN`; PLAN không nhắc mã INV của docs.

## E2E (orchestrator tự chạy trước khi commit)

1. Nhập md mẫu qua admin API → học viên đọc 1 section → tắt/mở app → tiến độ còn.
2. Sửa 1 card, nhập lại → tiến độ các card khác còn (INV-01).
3. Nộp 2 lần thử Task API → cả hai còn trong lịch sử, từ khoá không lộ trong response (INV-02).
4. Gọi tool MCP ghi feedback → app hiện feedback `reviewed` (INV-03); tài khoản khác không đọc được attempt (INV-06).
5. Từ **tab Home** bấm tab Design → doc → section ≤2 chạm; bấm từng tab cũ vẫn vào đúng màn (INV-05).
6. Chụp màn thật (integration test tạm + backend DB riêng) cho DuoPath và màn đọc; so với mockup.

## Việc ngoài scope (ghi, không sửa)

- SRS cho card SD; LLM chấm trực tiếp (đã chọn đi qua MCP).
- `mobile/ios/Runner.xcodeproj/project.pbxproj` sửa dở ở thư mục gốc, không thuộc run.
- `assets/fonts/IBMPlexSans-*` còn trong repo nhưng không khai pubspec: để nguyên.
- PR: dùng `Related to #31` (SRS chưa làm nên không tự đóng); hỏi user lúc P4 nếu muốn `Closes`.
