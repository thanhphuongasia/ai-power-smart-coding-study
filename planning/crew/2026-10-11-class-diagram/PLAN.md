# Run `class-diagram` — sơ đồ class trong tab Challenge, highlight phạm vi của bài

## Context

User muốn tab Challenge của mỗi bài method có **class diagram**:
- class của bài (vd `Flight` ở `models/flight.py`) hiện đủ thuộc tính (nhóm core/support) + method;
- các class liên kết tới nó, kiểu quan hệ (aggregation/association/dependency…) và nhãn;
- class khác (Controller, Service…) chỉ hiện **method tác động** tới class của bài;
- **highlight** phần thuộc bài hiện tại.

Hiện trạng: nội dung đi `content.json → Postgres → GET /content → app`. Bài method có `class_name` +
`function_name`, template chứa cả class. Code thật của Airline có 6 class: Flight (code, origin, dest,
capacity, booked, status; __init__, seats_left, is_full), FlightService (flights; add_flight,
remove_flight, search), Schedule (by_date; add, flights_on), FlightController (service; add, delete),
BookingService (free, reservations, counter; book, cancel), SeatMap (valid, taken; assign_seat).

Git: làm thẳng trên **main** (memory work-directly-on-main) — không worktree/PR; commit + push +
deploy sau khi test xanh (ghi DEVIATIONS).

## Quyết định thiết kế

1. **Dữ liệu sơ đồ soạn tay trong nội dung, theo project**: mỗi theme có `diagram`:
   ```json
   {"classes": [{"name": "Flight", "file": "models/flight.py",
                 "attributes": [{"name": "code", "type": "str", "group": "core"}, …],
                 "methods": ["__init__", "seats_left", "is_full"]}],
    "relations": [{"from": "FlightService", "to": "Flight", "kind": "aggregation",
                   "label": "flights: mã → Flight", "via": ["add_flight", "remove_flight", "search"]}]}
   ```
   `kind ∈ {association, aggregation, composition, dependency}`; `via` = method của `from` tác động
   lên `to`. Quan hệ không suy ra được từ code (vd FlightService dùng SimpleNamespace), nên soạn tay;
   chống lệch bằng **test hợp đồng**: thuộc tính/method khai trong sơ đồ phải có thật trong code đã
   ghép của các bài cùng class (INV-02).
2. **Lưu**: cột `themes.diagram` JSONB (migration 0003) — `/content` không thêm query. Key bắt buộc
   ở mọi theme (theme chưa có sơ đồ: `{"classes": [], "relations": []}`); wave 1 thêm key này vào
   content.json cho 3 theme cũ (bài học run trước).
3. **Loader kiểm**: tên class duy nhất; `from`/`to` có trong `classes`; `via` ⊆ methods của `from`;
   `kind` hợp lệ; group ∈ {core, support}.
4. **Highlight suy từ code bài** (client): ghép `accepted_answers[0]` vào template (`mergeCells` có
   sẵn) → trong thân `def <function_name>` lấy mọi `self.<x>` → thuộc tính được highlight; method
   `function_name` highlight. Vd `__init__` → code, origin, dest, capacity, booked, status;
   `seats_left` → capacity, booked.
5. **UI** (phone-first, không vẽ graph tự do): mục "SƠ ĐỒ CLASS" trong tab Challenge, sau "Dùng để
   làm gì?". Hộp UML của class bài (tên · file / thuộc tính chia core|support kèm kiểu / method), rồi
   từng quan hệ liên quan là một hàng: biểu tượng quan hệ (◇ aggregation, ◆ composition, → association,
   ⇢ dependency) + nhãn + hộp class kia **thu gọn**: nếu class kia là `from` → chỉ method trong `via`;
   nếu là `to` → chỉ tên + nhãn. Phần thuộc bài: nền accent + chữ đậm. Bài hàm rời / theme không có
   sơ đồ → không hiện mục này.

## Sổ bất biến

```text
INV-01 · Hợp đồng theme.diagram {classes[{name,file,attributes[{name,type,group}],methods[]}], relations[{from,to,kind,label,via[]}]} cùng tên/kiểu ở mọi đầu
         phải khớp: backend/app/content_schema.py · backend/app/content_api.py · mobile/lib/domain/models.dart · backend/content/content.json
         vỡ thì thấy gì: /content 500 hoặc app "Không tải được nội dung"
INV-02 · Sơ đồ khớp code: mỗi class có bài thì thuộc tính/method khai trong sơ đồ đều có trong code ghép (accepted_answers[0] vào template) của các bài cùng class
         phải khớp: backend/content/content.json · mobile/lib/domain/merge.dart · mobile/test/content_contract_test.dart
         vỡ thì thấy gì: sơ đồ hiện thuộc tính/method không tồn tại trong code người học viết
INV-03 · Mỗi bài method có class trong sơ đồ của theme chứa nó; highlight = function_name + self.<x> trong thân method đó
         phải khớp: mobile/lib/domain/class_scope.dart (mới) · mobile/lib/features/exercise/class_diagram.dart (mới) · backend/content/content.json
         vỡ thì thấy gì: bài method không có sơ đồ, hoặc highlight sai thuộc tính
INV-04 · Quan hệ hợp lệ: from/to ∈ classes, via ⊆ methods(from), kind ∈ 4 loại — chặn lúc nạp
         phải khớp: backend/app/load_content.py · backend/app/content_schema.py
         vỡ thì thấy gì: app vẽ quan hệ trỏ tới class không có
INV-05 · Không ảnh hưởng cũ: /content vẫn ≤ 8 query; bài hàm rời và theme không sơ đồ không đổi giao diện; test cũ xanh
         phải khớp: backend/app/content_api.py · mobile/lib/features/exercise/challenge_tab.dart · backend/tests/test_content_api.py
         vỡ thì thấy gì: query count tăng; tab Challenge bài cũ hiện khung trống
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | orchestrator · L4 (schema/migration) · session | `themes.diagram` JSONB + migration 0003 + schema strict + loader kiểm (INV-04) + key rỗng cho 3 theme cũ | `backend/app/tables.py`, `backend/migrations/versions/0003_theme_diagram.py`, `backend/app/content_schema.py`, `backend/app/load_content.py`, `backend/tests/test_load_content.py`, `backend/content/content.json` | `cd backend && .venv/bin/python -m pytest -q tests/test_schema.py tests/test_load_content.py` |
| T-02 | orchestrator · L4 (public API) · session | `/content` trả `diagram` mỗi theme, không thêm query | `backend/app/content_api.py`, `backend/tests/test_content_api.py` | `cd backend && .venv/bin/python -m pytest -q tests/test_content_api.py` |
| T-03 | `crew-impl-standard` · T2 · sonnet | Dart model `ClassDiagram/DiagramClass/DiagramAttribute/DiagramRelation` parse strict + `StudyTheme.diagram` + `classScope(exercise)` (highlight) | `mobile/lib/domain/models.dart`, `mobile/lib/domain/class_scope.dart`, `mobile/test/content_json_test.dart`, `mobile/test/class_scope_test.dart` | `cd mobile && flutter test test/content_json_test.dart test/class_scope_test.dart` |
| T-04 | `crew-impl-standard` · T2 · sonnet | Widget `ClassDiagramView` + gắn vào tab Challenge (ẩn khi không có) | `mobile/lib/features/exercise/class_diagram.dart`, `mobile/lib/features/exercise/challenge_tab.dart`, `mobile/test/class_diagram_test.dart` | `cd mobile && flutter test test/class_diagram_test.dart test/exercise_screen_test.dart` |
| T-05 | `crew-impl-standard` · T2 · sonnet | Soạn sơ đồ Airline (6 class, ~6 quan hệ) + test hợp đồng INV-02/03 | `backend/content/content.json`, `mobile/test/content_contract_test.dart` | `cd backend && .venv/bin/python -m pytest -q && cd ../mobile && flutter test test/content_contract_test.dart` |

**Thứ tự**: Wave 1 — T-01, T-02 (tôi) ‖ T-03 (hợp đồng JSON chốt trong plan). Wave 2 — T-04 ‖ T-05.
Commit checkpoint sau mỗi wave (trên main, chưa push cho tới khi qua seam gate).
Review: `crew-review` mỗi task; T-01/T-02 thêm `crew-review-external` (timeout 360). Reviewer mối nối
INV-01..05 → `verify-seam.sh` → push + deploy.

## Verification (e2e — orchestrator tự chạy)

1. `pytest -q`, `flutter test`, `flutter analyze`.
2. Deploy; `curl /content`: theme airline có `diagram` 6 class; theme cũ `{"classes": [], "relations": []}`; không lộ judge.
3. Chrome: Home → Airline → Flight → `Flight.__init__` → tab Challenge: hộp Flight, core/support,
   highlight origin/dest/capacity/booked/status + `__init__`; hàng quan hệ FlightService ◇ (chỉ
   add_flight/remove_flight/search), BookingService, Schedule, SeatMap, FlightController.
4. `FlightService.search`: hộp FlightService highlight `search` + `flights`; FlightController hiện
   add/delete; Flight chỉ tên + nhãn.
5. **Mối nối cũ**: `split-chunks` (hàm rời) tab Challenge không có mục sơ đồ, Run vẫn passed.

## Rủi ro / giới hạn

- Sơ đồ soạn tay có thể lệch code → test INV-02 chặn thuộc tính/method không có thật, KHÔNG chặn
  được quan hệ sai nghĩa (vd nhãn mô tả sai) — cái đó dựa review.
- Code mẫu hiện mỗi bài là bản rút gọn độc lập (BookingService giữ `free` riêng, không gọi Flight) —
  sơ đồ thể hiện quan hệ **thiết kế**, nhãn phải nói rõ "khái niệm" để không gây hiểu nhầm.
- Màn hình hẹp: sơ đồ dạng danh sách dọc, không phải graph 2D.
