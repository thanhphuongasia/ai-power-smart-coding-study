# Run `project-tree-airline` — cây project→module lồng nhau→file→class→method, seed Airline Reservation System

## Context

Cây nội dung hiện tại (Postgres `themes → topics → code_files → file_exercises → exercises → blocks`) chỉ có
1 tầng component và coi mọi bài là hàm rời. User muốn mô tả project thật: module/service lồng nhiều tầng,
file chứa class, bài tập là **method của class**. Seed đầu tiên: **Airline Reservation System**, module
**Flight** (quản lý chuyến bay) và **Reservation** (đặt chỗ). Xong thì deploy lên VPS để test (đã cho phép).

Khảo sát: harness chỉ gọi được hàm top-level `function(*args)` so với JSON (`backend/app/harness.py:81`);
`Topic` phẳng; client duyệt cây bằng vòng lặp cố định 4 tầng ở ~10 chỗ (`content.dart`, `progression.dart`,
`session_providers.dart:33`, `home_screen.dart:137`, `theme_detail_screen.dart:72`, `topic_detail_screen.dart:42`,
`stats_screen.dart:90`…); nhãn vị trí ô (`cellWhere`, `cell_editor_page.dart:17`) suy từ `indent_level`
nên sai cho method (thân method đã ở indent 2).

**Base**: tách từ `feat/cell-gating` (PR #15 — UI mới đang chạy trên VPS, có `cellWhere`), PR **base = main**
(không stack base vào nhánh khác — tránh lỗi merge nhầm đã gặp). Diff PR co lại khi #15 merge.
Deploy dùng `deploy/` copy tạm (untracked) từ worktree PR #14 như lần trước.

## Quyết định thiết kế

1. **Module lồng nhau = `topics` tự tham chiếu**: thêm `topics.parent_id` (nullable, FK `topics.id`
   CASCADE). JSON: mỗi topic có thêm `modules: [Topic…]` (đệ quy, có thể rỗng). `position` = **thứ tự
   duyệt trước (preorder) trong theme** → giữ nguyên unique `(theme_id, position)`, `/content` vẫn 1 SELECT
   cho topics (tổng số query không tăng). Không đổi tên bảng/route (`theme`, `topic` giữ trong code;
   UI có thể gọi "Project/Module").
2. **Class = thuộc tính của bài, không phải bảng**: `exercises.class_name` (nullable). Bài method có
   `class_name="FlightService"`, `function_name="search"`, template chứa **cả khung class** (method khác là
   code khoá). File hiển thị bài nhóm theo class. Lý do: đơn giản nhất mà đủ "file → class → method";
   tách bảng class khi có nhu cầu thật (vd metadata riêng cho class).
3. **Harness thêm dạng case "kịch bản"** (giữ nguyên 2 dạng cũ):
   `{"steps": ["svc = FlightService()", "svc.add_flight(Flight('VN1','HAN','SGN',2))"], "call": "[f.code for f in svc.search('HAN','SGN')]", "expect": {"return": ["VN1"]}}`
   và `expect: {"raises": "ValueError"}`. Mỗi case chạy trong namespace copy riêng; steps/call là nội dung
   do người soạn viết (server), không phải input người học. Payload `/run` thêm `class_name`; harness kiểm
   class tồn tại và có method → báo "Không tìm thấy method FlightService.search()".
4. **Nhãn vị trí ô suy từ template** (thay ánh xạ `indent_level`): dòng code khoá gần nhất phía trên có
   indent nhỏ hơn marker → "trong vòng for" / "trong if" / "trong method search" / "trong hàm"… Hàm trong
   `merge.dart`, dùng ở `cell_editor_page.dart` và `code_tab.dart`. `indent_level` giữ làm metadata (INV-05 test cũ).
5. **Mở khoá/“bài kế” giữ theo file** (không đổi luật): class chỉ là nhóm hiển thị trong file.
6. **Seed**: project `airline` đặt **đầu danh sách**; 3 project cũ giữ nguyên. Cây dự kiến:
   ```text
   airline — Airline Reservation System
   ├ flight — Quản lý chuyến bay
   │  ├ models/flight.py            class Flight: seats_left(), is_full()
   │  ├ services/flight_service.py  class FlightService: add_flight() (trùng mã → ValueError), search()
   │  └ (sub-module) schedule — services/schedule.py  class Schedule: flights_on(date)  [nếu đủ ngắn]
   └ reservation — Đặt chỗ
      ├ services/booking_service.py class BookingService: book() (hết chỗ → ValueError), cancel()
      └ (sub-module) seating — seat_map.py  class SeatMap: assign_seat()
   ```
   ~6 bài, mỗi bài 2–3 ô TODO ngắn, đủ challenge/hints/accepted_answers, judge case dạng kịch bản chạy
   được (reference solution pass qua harness thật). Ít nhất 2 tầng module để chứng minh lồng nhau.

## Sổ bất biến

```text
INV-01 · Hợp đồng JSON mới — Topic.modules (đệ quy, list) và Exercise.class_name (key bắt buộc, có thể null) cùng tên/kiểu ở mọi đầu
         phải khớp: backend/app/content_schema.py · backend/app/content_api.py (_read_tree/_exercise_payload) · mobile/lib/domain/models.dart (fromJson/toJson) · backend/content/content.json
         vỡ thì thấy gì: /content 500 (response_model), hoặc app "Không tải được nội dung"/cache bị xoá
INV-02 · Thứ tự module = position preorder trong theme; /content dựng lại cha–con và thứ tự đúng như content.json
         phải khớp: backend/app/load_content.py (gán position/parent_id) · backend/app/content_api.py · backend/migrations/versions/0002_*.py · backend/app/tables.py
         vỡ thì thấy gì: sub-module mất, lặp, hoặc sai thứ tự; test /content == public_payload fail
INV-03 · Mọi file ở MỌI tầng module đều được client duyệt tới (lookup, unlock, continue, practice, stats, cross-cut)
         phải khớp: mobile/lib/domain/content.dart · mobile/lib/domain/progression.dart · features/exercise/session_providers.dart · features/browse/{home,theme_detail,topic_detail}_screen.dart · features/stats/stats_screen.dart · features/practice/practice_screen.dart
         vỡ thì thấy gì: mở bài trong sub-module → StateError/“không tìm thấy”, bài thiếu ở tab Luyện, đếm block sai
INV-04 · Bài method chấm được: class_name DB → Judge → payload /run → harness tìm class+method, chạy case kịch bản
         phải khớp: backend/app/tables.py · backend/app/content_api.py (read_judge) · backend/app/main.py (payload) · backend/app/harness.py
         vỡ thì thấy gì: lời giải đúng nhận "Không tìm thấy hàm search()" hoặc fail
INV-05 · Ghép đáp án đầu tiên vào template == judge.solution, marker indent == 4×indent_level — cho MỌI bài kể cả airline
         phải khớp: backend/content/content.json · mobile/lib/domain/merge.dart · mobile/test/content_contract_test.dart
         vỡ thì thấy gì: người học gõ đúng đáp án vẫn bị chấm sai
INV-06 · Nhãn vị trí ô suy từ template đúng cho cả hàm và method
         phải khớp: mobile/lib/domain/merge.dart · features/exercise/cell_editor_page.dart · features/exercise/code_tab.dart
         vỡ thì thấy gì: thân method hiện "trong vòng for"
INV-07 · 5 bài cũ giữ nguyên hành vi (harness 2 dạng case cũ, split-chunks flow, cross-cut chunker.py 2 theme)
         phải khớp: backend/app/harness.py · backend/content/content.json · mobile/test/app_flow_test.dart · mobile/test/phase2_screens_test.dart
         vỡ thì thấy gì: test cũ đỏ; split-chunks không Run passed trên VPS
```

## Task (mỗi task: owned files PHẢI có diff; forbidden = mọi file ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation (1 lệnh) |
|---|---|---|---|---|
| T-01 | orchestrator · L4 · session | DB + loader: `parent_id`, `class_name`, migration 0002, schema `modules`/`class_name`, loader preorder + kiểm id module trùng/đệ quy | `backend/app/tables.py`, `backend/migrations/versions/0002_module_tree_class.py`, `backend/app/content_schema.py`, `backend/app/load_content.py`, `backend/tests/test_load_content.py` | `cd backend && .venv/bin/pytest -q tests/test_schema.py tests/test_load_content.py` |
| T-02 | orchestrator · L4 (public API) · session | `/content` dựng cây lồng + `class_name`; `Judge.class_name` | `backend/app/content_api.py`, `backend/tests/test_content_api.py` | `cd backend && .venv/bin/pytest -q tests/test_content_api.py` |
| T-03 | `crew-impl-standard` · T2 · sonnet | Harness case kịch bản + `raises`, payload `class_name`, lỗi "không tìm thấy method" | `backend/app/harness.py`, `backend/app/main.py`, `backend/tests/test_harness.py`, `backend/tests/test_api.py` | `cd backend && .venv/bin/pytest -q tests/test_harness.py tests/test_api.py` |
| T-04 | `crew-impl-standard` · T2 · sonnet | Domain app: `Topic.modules`, `Exercise.className`, index đệ quy (`allFiles`, `locateExercise` trả path module), progression | `mobile/lib/domain/models.dart`, `mobile/lib/domain/content.dart`, `mobile/lib/domain/progression.dart`, `mobile/test/content_json_test.dart`, `mobile/test/progression_test.dart` | `cd mobile && flutter test test/content_json_test.dart test/progression_test.dart` |
| T-05 | `crew-impl-standard` · T2 · sonnet | Nhãn vị trí ô suy từ template | `mobile/lib/domain/merge.dart`, `mobile/lib/features/exercise/cell_editor_page.dart`, `mobile/lib/features/exercise/code_tab.dart`, `mobile/test/merge_test.dart` | `cd mobile && flutter test test/merge_test.dart test/code_tab_test.dart` |
| T-06 | `crew-impl-standard` · T2 · sonnet | Màn duyệt: theme → module (sub-module card + breadcrumb) → file (nhóm theo `class X`), row `Class.method()` | `mobile/lib/features/browse/theme_detail_screen.dart`, `mobile/lib/features/browse/topic_detail_screen.dart`, `mobile/lib/features/browse/exercise_row.dart`, `mobile/test/browse_screens_test.dart` | `cd mobile && flutter test test/browse_screens_test.dart test/phase2_screens_test.dart` |
| T-07 | `crew-impl-standard` · T2 · sonnet | Chỗ còn lại duyệt cây cứng 4 tầng → dùng helper T-04; header `file · Class.method` | `mobile/lib/features/browse/home_screen.dart`, `mobile/lib/features/exercise/session_providers.dart`, `mobile/lib/features/stats/stats_screen.dart`, `mobile/lib/features/exercise/exercise_screen.dart`, `mobile/lib/features/practice/practice_screen.dart` | `cd mobile && flutter test` |
| T-08 | `crew-impl-standard` · T2 · sonnet | Seed Airline (~6 bài method, 2 module, ≥2 tầng) + cập nhật test đếm id/theme | `backend/content/content.json`, `mobile/test/content_contract_test.dart`, `backend/tests/test_harness.py` (case airline) | `cd backend && .venv/bin/pytest -q && cd ../mobile && flutter test test/content_contract_test.dart` |

Acceptance chung: test cũ xanh (INV-07); `flutter analyze` sạch; pytest toàn bộ xanh trên Postgres test.

**Thứ tự** (rủi ro cao sớm): Wave 1 — T-01, T-02 (tôi) ‖ T-04. Checkpoint full test. Wave 2 — T-03 ‖ T-05 ‖ T-06.
Wave 3 — T-07 rồi T-08. Checkpoint full test (backend + mobile). Commit checkpoint sau mỗi wave
(không dùng `git checkout --` để hoàn tác).

Review: `crew-review` từng task; T-01/T-02 (L4 tự làm) thêm `crew-review-external` timeout 360 theo project
rule. Reviewer mối nối (INV-01..07) trước commit cuối → `verify-seam.sh`.

`home_screen.dart` (T-07): thư mục gốc của user đang sửa dở file này (streak chip, chưa commit) → thay đổi ở
đây giữ tối thiểu (chỉ đổi vòng lặp sang helper) để giảm conflict khi user merge.

## Verification (e2e — orchestrator tự chạy)

1. Local: `pytest -q` (backend) + `flutter test` + `flutter analyze`.
2. Deploy VPS (`deploy/deploy.sh`, migration 0002 chạy qua `alembic upgrade head`).
3. `curl /content`: có `airline` đầu tiên, module `flight` có sub-module, bài có `class_name`, không lộ `judge`.
4. `curl /run` với lời giải mẫu của 1 bài airline → `passed`; với code thiếu method → lỗi "Không tìm thấy method".
5. **Mối nối cũ**: `/run` split-chunks lời giải mẫu vẫn passed (INV-07).
6. Chrome: Home → card Airline → module Flight → sub-module → file → bài (header `flight_service.py ·
   FlightService.search`, nhãn ô "trong method search") → gõ đúng → Run passed. Các site khác trên VPS giữ mã HTTP cũ.
7. Reviewer mối nối → `verify-seam.sh` exit 0 → commit/push/PR (base main, `Closes #<issue>`).

## Rủi ro / giới hạn

- Case kịch bản dùng `exec/eval` chuỗi do người soạn viết — an toàn vì chạy trong sandbox Judge0 như code học
  viên; KHÔNG được để client gửi steps/call (chỉ đọc từ DB).
- Cache app bản cũ thiếu `modules`/`class_name` → parse lỗi → tự xoá, tải lại (đã có cơ chế).
- Không làm tiến độ lưu bền (ngoài phạm vi, user chọn làm sau).
