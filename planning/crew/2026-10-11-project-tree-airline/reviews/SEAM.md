# Seam review — 2026-10-11-project-tree-airline

INV-01: CÒN ĐÚNG — backend/app/content_schema.py:73 · mobile/lib/domain/models.dart:332 — modules/class_name cùng tên-kiểu ở schema, /content (content_api.py:111,124), Dart fromJson/toJson và content.json; test round-trip trên Postgres xanh.
INV-02: CÒN ĐÚNG — backend/app/load_content.py:46 · backend/app/content_api.py:75 — loader và /content cùng quy ước preorder, con gom theo parent_id; unique (theme_id, position) giữ ở tables.py:33.
INV-03: CÒN ĐÚNG — mobile/lib/domain/models.dart:62 · backend/app/content_api.py:103 — mọi walker client đệ quy (progression.dart:14, session_providers.dart:34, home_screen.dart:137, stats_screen.dart:95, practice_screen.dart:25); thứ tự bài backend == uniqueExercises (test_content_api thứ tự preorder).
INV-04: CÒN ĐÚNG — backend/app/content_api.py:150 · backend/app/harness.py:136 — class_name đi DB → Judge → main.py:122 → harness; 13/13 lời giải mẫu passed; e2e VPS /run 3 bài airline passed, đổi tên method → "Không tìm thấy method FlightService.search()".
INV-05: CÒN ĐÚNG — backend/content/content.json · mobile/test/content_contract_test.dart:10 — ghép accepted_answers[0] == judge.solution cho cả 13 bài, marker = 4×indent_level.
INV-06: CÒN ĐÚNG — mobile/lib/domain/merge.dart:135 · mobile/lib/features/exercise/code_tab.dart:444 — template airline: ô A "trong method", ô sau for "trong vòng for", sau if "trong if"; không còn "trong vòng for" sai cho thân method.
INV-07: CÒN ĐÚNG — backend/app/harness.py:140 · mobile/test/app_flow_test.dart:1 — 2 dạng case cũ giữ nguyên; pytest + flutter (app_flow, phase2 cross-cut chunker.py 2 theme) xanh; e2e VPS split-chunks passed.

Ghi chú: nhãn là "trong method" (không kèm tên method như PLAN mô tả) — ghi ở DEVIATIONS.md.
