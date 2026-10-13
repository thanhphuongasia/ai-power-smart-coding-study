# SEAM review — run 2026-10-12-sd-reader-hotfix

INV-01: CÒN ĐÚNG — backend/app/sd/learner.py:66,77 · mobile/lib/features/system_design/reader_screen.dart:397-401 · mobile/lib/features/system_design/sd_path_screen.dart:61,79,89
INV-02: CÒN ĐÚNG (đường touch/menu/mở màn; hở ở scrollbar/phím trên desktop-web, KHÔNG kiểm được) — mobile/lib/features/system_design/card_snap_physics.dart:42-60 · mobile/lib/features/system_design/reader_screen.dart:338,346-348,435-448
INV-03: CÒN ĐÚNG — backend/app/sd/learner.py:77 · backend/app/sd/attempts.py:100-104 · mobile/lib/features/system_design/sd_path_screen.dart:79-90,234-236 · mobile/lib/features/system_design/task_screen.dart:352 · mobile/lib/features/system_design/context_screen.dart:168
INV-04: CÒN ĐÚNG — mobile/lib/features/system_design/reader_screen.dart:294,323,325,428-431 · mobile/lib/features/system_design/card_snap_physics.dart:46-52

## Bằng chứng

Chạy thật trong worktree: `pytest tests/test_sd_learner.py tests/test_sd_attempts.py` = 46 passed; `flutter test` (sd_reader, sd_reader_menu, card_snap_physics, sd_path_screen, sd_task_flow) = 141 passed.
Mutant chạy trên bản sao ngoài git (scratchpad), đều bị test bắt (đỏ):
- learner.py:77 `unlocked = True` -> 4 test đỏ (gồm test_task_locked_before_phase2); khôi phục khoá tuần tự theo task trước -> 6 test đỏ (gồm test_all_tasks_open_and_can_be_submitted_out_of_order).
- reader_screen.dart:338 bỏ `_menuJumps` guard -> sd_reader_menu_test (e) đỏ.
- reader_screen.dart:446 `_startIndex = 0` sau nhảy menu -> (e) đỏ.
- reader_screen.dart:397-401 "xong" suy từ đếm card cục bộ thay vì `_doneNotified` -> (d1) đỏ.

### INV-01
Server: `_tasks_state` (learner.py:77) là nơi duy nhất tính task `unlocked`; `list_docs` (:126), `get_doc` (:155) và POST attempt (attempts.py:100-104) đều gọi nó với cùng biểu thức `phase2 = bool(sec) and all(done)` (3 bản sao biểu thức, đồng nhất; không lệch). Client: path (sd_path_screen.dart:61,89 `_fromServer`), màn task (task_screen.dart:352), 'Bắt đầu' (context_screen.dart:168) chỉ đọc `SdTask.unlocked/done`; `grep` không còn chỗ nào client tự suy khoá/xong, và không còn chuỗi 'Làm task trước'. Menu: locked = `_unlocked` (khởi tạo từ `SdSection.unlocked`, nới bằng `nextSectionId` của PUT done, reader_screen.dart:535-541); done = `_doneNotified` (server done ban đầu + PUT done, :169,:541). `SdTask.unlocked` không thể lệch POST 409 vì cùng hàm.
Lưu ý (không phải lỗi mới): `readCount/total` trong menu (:393) là đếm cục bộ nhưng chỉ là chữ phụ, không quyết khoá/xong.

### INV-02
Fling: createBallisticSimulation (card_snap_physics.dart:42-60) chặn đích <= 0,9 viewport; mọi card có mép dưới trong (vBottom cũ, vBottom mới] đều giao viewport mới, nên luật "mép dưới qua mép dưới viewport" (reader_screen.dart:346) chỉ đánh dấu card đã hiện ra. Vận tốc < 300 px/s rơi về physics cha (platform), quãng trôi nhỏ.
Menu: `_menuJumps` chặn đánh dấu suốt animateTo (:338,:435), sau đó `_startIndex` = đầu section đích (:446) rồi `_evaluate`; card trên đích chỉ tính khi còn thấy (:347). `?section=`: `_startIndex` đặt trước ensureVisible (:273-282). Resize/đổi cỡ chữ: `_evaluate` chỉ chạy khi cuộn, nên chỉ đánh dấu muộn hơn, không đánh dấu thừa. Chỉ semantics-scroll/PageDown cuộn tối đa ~1 viewport, vẫn không bỏ card.
KHÔNG KIỂM ĐƯỢC: kéo thanh cuộn (scrollbar thumb) trên web/desktop, phím Home/End, và fling trên thiết bị thật. Các đường này không đi qua physics snap (PLAN đã nêu con lăn/trackpad "giữ tự do"); với thumb-drag, card bị lướt qua có `index >= _startIndex` và bottom < vTop sẽ bị đánh dấu (reader_screen.dart:346-348) dù chưa hiện. Chưa có test và chưa chạy trên Chrome thật. Rủi ro chỉ với người dùng web desktop; ghi vào Backlog, không chặn.

### INV-03
Một quy tắc `unlocked = phase2` (learner.py:77); path: node task = `_fromServer(t.unlocked)` (sd_path_screen.dart:89), tap node khoá chỉ khi Phase 2 khoá (:234-236); màn task: khoá khi `!task.unlocked` (task_screen.dart:352, thông báo 'Đọc xong Phase 1…'); 'Bắt đầu': `sdStartTask` dùng `unlocked && !done` (context_screen.dart:168); 'Task tiếp theo' `next.unlocked` (task_screen.dart:322); POST attempt 409 khi `!unlocked` (attempts.py:103-104). MCP (admin.py / attempts.py phần chấm sâu) không dùng rule khoá: đó là đường của admin chấm bài đã nộp, không tạo attempt, nên không lệch. GET attempts (attempts.py:~140) không kiểm khoá (đọc lịch sử của chính mình; không lộ prompt/rubric) — như trước hotfix.

### INV-04
Menu và snap cùng lấy mốc từ `_anchors()` (reader_screen.dart:294): snap qua `_snapOffsets` (:323,:325), menu qua `_scrollToSection` (:428-431, lọc `sectionStart`). Mốc đầu section = đỉnh tiêu đề (:309), nên sau nhảy pixels == một mốc; fling tiến: mốc kế có `a > pixels + 1` (card_snap_physics.dart:46-52 -> snapTarget) = card thứ 2 của section (sd_reader_menu_test (e) khẳng định top('c2') ≈ 0). Nhảy lùi rồi vuốt: không lộ card bị bỏ qua (e). Section cuối bị kẹp ở maxScrollExtent (:432): vuốt lùi sang mốc trước < pixels-1, không kẹt.
Chưa kiểm: nhảy khi đang trong fling của người dùng (animateTo thay activity ballistic; code xử lý bằng `_menuJumps` đếm lồng nhau, không có test riêng).
