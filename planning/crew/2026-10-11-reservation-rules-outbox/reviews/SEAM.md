# Seam review — 2026-10-11-reservation-rules-outbox

INV-01: CÒN ĐÚNG — backend/content/content.json:2287 · mobile/lib/domain/merge.dart:83 — 6 bài mới mỗi bài 3 ô, 3 hint, đáp án ≤2 dòng, marker = 4×indent_level, ghép đáp án đầu == solution; AST không có lệnh sau return/raise/break cùng nhánh; flutter test +334.
INV-02: CÒN ĐÚNG — backend/content/content.json:2372 · backend/tests/test_harness.py:39 — test_harness 61 passed (mẫu pass, thân pass fail); grep không có lời gọi now()/random/time.time; e2e VPS 6 bài mới passed, lời giải sai "huỷ sát giờ" failed.
INV-03: CÒN ĐÚNG — backend/content/content.json:1 · mobile/test/content_contract_test.dart:402 — sơ đồ Airline (11 class) và Twitter (3 class) khớp code bằng AST; mọi bài method có class trong sơ đồ của mọi theme chứa nó; 6 class cũ không đổi.
INV-04: CÒN ĐÚNG — mobile/lib/domain/content.dart:123 · mobile/lib/features/browse/topic_detail_screen.dart:665 — reliability/outbox.py cùng tên + cùng ids ở airline-reliability và feed-reliability; Chrome thấy nhãn "Dùng ở 2 theme"; mở khoá theo file (mobile/lib/domain/progression.dart:4) — người học Twitter mở outbox-save ngay.
INV-05: CÒN ĐÚNG — backend/tests/test_load_content.py:65 · mobile/test/content_contract_test.dart:112 — 16 bài cũ giống từng byte so với d23f2e1; 22 bài, 17 bài method; e2e booking-book, like-post vẫn passed.
