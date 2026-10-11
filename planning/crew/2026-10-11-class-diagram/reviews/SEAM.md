# Seam review — 2026-10-11-class-diagram

INV-01: CÒN ĐÚNG — backend/app/content_schema.py:77 · mobile/lib/domain/models.dart:200 — cùng key classes/relations/attributes{name,type,group}/relations{from,to,kind,label,via}; DB lưu và /content trả dict thô nên giữ key `from` (content_api.py:118); Dart đọc/ghi 'from' (models.dart:207); e2e VPS: payload không có "from_".
INV-02: CÒN ĐÚNG — mobile/test/content_contract_test.dart:1 · backend/content/content.json:1 — thuộc tính/method khai trong sơ đồ có trong code ghép; test được siết lại ở T-05b (khớp đúng thân class thay vì chuỗi con).
INV-03: CÒN ĐÚNG — mobile/lib/domain/class_scope.dart:31 · mobile/lib/features/exercise/class_diagram.dart:138 — 11 bài method đều có class trong sơ đồ; flight-init → {code, origin, dest, capacity, booked, status}; seats_left → {capacity, booked}; search → flights; booking-book → {free, counter, reservations}.
INV-04: CÒN ĐÚNG — backend/app/load_content.py:70 · backend/app/content_schema.py:93 — kind/group chặn bằng Literal, from/to/via kiểm ở _diagram_errors; test case inherits/misc bị từ chối (backend/tests/test_load_content.py:207).
INV-05: CÒN ĐÚNG — backend/tests/test_content_api.py:80 · mobile/lib/features/exercise/challenge_tab.dart:36 — diagram nằm trong SELECT themes sẵn có (≤ 8 query); bài hàm rời classScope null → không hiện mục; pytest 160 passed, flutter +334.
