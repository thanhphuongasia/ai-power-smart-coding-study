# SEAM review — admin-ux-levels

INV-01: CÒN ĐÚNG — mobile/lib/features/admin/admin_module_screen.dart:261 · mobile/lib/features/admin/admin_controller.dart:336 — mọi ghi đi qua ctl.add*/updateNode/delete* (_mutate); không màn nào sửa JSON trực tiếp; AdminSaveBar (admin_widgets.dart:~480) giữ dirty/validate/save/discard+confirmDiscard, AdminConflictBanner (admin_widgets.dart:~395) cho 409. flutter analyze sạch, flutter test 445 xanh.
INV-02: CÒN ĐÚNG — mobile/lib/app/router.dart:89-103 · mobile/lib/features/admin/admin_screen.dart:66 — 4 route đăng ký (/admin, theme/:themeId, module/:moduleId, exercise/:id); push theo cây (screen:66, theme_screen:84, module_screen:180/268) nên back đúng; Home admin-button push /admin (home_screen.dart:45) = 1 chạm tới danh sách project. Breadcrumb pop theo số tầng (admin_widgets.dart:~125).
INV-03: CÒN ĐÚNG — mobile/lib/features/admin/admin_controller.dart:178-218 · backend/app/content_rules.py:150-157 — scaffold có class: `class C:\n    def fn(self):\n        # TODO A` + indent_level 2 (marker 8 space = 4*2, khớp content_rules.py:116); không class: `def fn():` + indent 1; class rỗng -> null (editor cũng map rỗng -> null, exercise_editor.dart:215). fn/class lấy đúng giá trị dialog (module_screen:262-266). Lỗi "không định nghĩa def fn(" là lỗi bài nháp có chủ đích (solution rỗng), biến mất khi điền solution.
INV-04: VỠ — mobile/lib/features/admin/admin_widgets.dart:17-20 · backend/app/content_rules.py:107-128 — regex `^\s*bài\s+([^\s:]+)\s*:` chỉ khớp `bài <id>: …`. Mọi lỗi cấp ô có dạng `bài <id> ô <X>: …` (bp = f"{p} ô {lab}", content_rules.py:107; các dòng 109,111,114,116,118,121,124,126,128) -> KHÔNG khớp, không có chấm đỏ. Cũng không khớp: `theme X: thiếu class C (bài <id>)` (content_rules.py:267), lỗi pydantic dạng `exercises.<id>.field: msg` (load_content.py:227). Dạng đúng khớp: content_rules.py:85/91/93/104/135/141/147/151/155/157/181-187, load_content.py:213 (id cắt 40 ký tự — chỉ lệch khi id >40), 252, 255, 257, 259, 263. Hệ quả cụ thể: bài nháp mới chỉ thấy chấm khi còn lỗi cấp bài (thiếu judge.solution / case); sau khi điền solution+case mà ô còn thiếu đáp án/gợi ý/vocab/explanation thì Kiểm tra báo "N lỗi" nhưng không thẻ nào đỏ. Sửa: regex `^\s*bài\s+([^\s:]+)\s*(?:ô\s+\S+\s*)?:` (+ tuỳ chọn bắt `\(bài ([^\s)]+)\)` cuối chuỗi), thêm test với `bài e1 ô A: cần ít nhất 1 đáp án` (admin_screen_test.dart:169 chỉ dùng dạng `bài e1: …` nên không bắt được).

## Mối nối chưa khai

- Dialog thêm bài (admin_module_screen.dart:214-268) không validate tên hàm/class là identifier hợp lệ; nhập "my func" -> scaffold `def my func(` chỉ lộ ở server/preview. Minor.
- Dialog thêm bài bỏ qua (không báo) khi tiêu đề rỗng (module_screen:259); addExercise có thể trả null nếu file bị xoá giữa chừng -> không điều hướng, im lặng. Minor.
- Lỗi theme-level (diagram, `theme X: …`) không có chấm đỏ ở thẻ theme/module vì parser chỉ biết id bài; chỉ thấy qua chip "N lỗi". Nằm cùng gốc INV-04.
- Breadcrumb pop N lần phụ thuộc stack push: mở thẳng URL sâu (web refresh /admin/module/x) thì canPop=false, chạm breadcrumb không làm gì (admin_widgets.dart:~125). Minor; nút back header có fallback context.go('/').

Verdict: CẦN SỬA — INV-04 VỠ (chặn commit): regex chấm đỏ bỏ sót mọi lỗi dạng `bài <id> ô <X>: …`. INV-01..03 còn đúng. Đây là thay đổi UI-only, không chạm security/migration; fix nhỏ một regex + một test.

## Sau sửa (T-02b) — kiểm lại INV-04
INV-04: CÒN ĐÚNG — mobile/lib/features/admin/admin_widgets.dart:17-35 · backend/app/content_rules.py:91-267 — parser nhận `bài <id>:`, `bài <id> ô <X>:`, `(bài <id>)`; xác nhận bởi review vòng 2 T-02; test widget lỗi cấp ô ở mobile/test/admin_screen_test.dart.
Verdict sau xử lý: PASS (INV-01..04 CÒN ĐÚNG)
