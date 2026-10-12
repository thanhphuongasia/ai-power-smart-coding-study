# SEAM review — 2026-10-12-exercise-editor-redesign

INV-01: CÒN ĐÚNG — mobile/lib/features/admin/exercise_editor.dart:531,553,581,616,625,748-751,789,923,… (mọi Key cũ còn; so với ffc104e chỉ thêm, không mất); mobile/test/admin_exercise_editor_test.dart (toàn suite xanh)
INV-02: CÒN ĐÚNG — mobile/lib/features/admin/code_cell.dart:166-190 (buildTextSpan chỉ đổi style, không đổi chuỗi), exercise_editor.dart:55,126,131,132,149 (HighlightingController) + :109,227,235,240 (toJson đọc .text)
INV-03: CÒN ĐÚNG — mobile/lib/features/admin/exercise_editor.dart:984-997 (medium: _previewPanel; hẹp: _preview inline; hai nhánh loại trừ nhau)
INV-04: CÒN ĐÚNG — mobile/lib/features/admin/exercise_editor.dart:1001,922-924 (_actionBar ngoài LayoutBuilder, một bộ, điều kiện casesError/hasLabelError); _apply :408 chặn lần nữa
INV-05: CÒN ĐÚNG — mobile/lib/features/admin/exercise_editor.dart:119-168,213-242 (controller sống trong _Form/_BlockForm, không trong widget; toJson/warnings/hasLabelError/casesError đọc controller, không đọc cây widget); collapsible_section.dart:90,225 (đóng chỉ bỏ child khỏi cây)
INV-06: VỠ — mobile/lib/features/admin/exercise_editor.dart:544-552 (label-error nằm trong child CollapsibleCard) + :801 (summary mục blocks chỉ "N ô")

## Ghi chú

Chạy thật: `flutter test` (cd mobile) = "+513: All tests passed!"; `flutter analyze` = No issues found.

INV-05 (tự thêm): "Đóng một mục/ô hoặc đổi layout rộng/hẹp không làm mất dữ liệu đã nhập, và Áp dụng/preview/warnings vẫn tính trên dữ liệu của mục đang đóng". Lý do thêm: đóng mục làm Key biến mất, nên mọi logic dựa vào widget sẽ lệch. Kiểm bằng đọc code: không logic nào dùng Key/widget. `_jumpTo` (:711) dùng context của chính CollapsibleSection (GlobalKey, luôn có trong cây) nên Scrollable.ensureVisible không hỏng khi mục đóng. Đổi layout: các mục có GlobalKey (:695) nên giữ state khi chuyển nhánh. Chỉ mất vị trí cuộn và trạng thái "Thu gọn" của CodeCell (state cục bộ, không phải dữ liệu). Chưa có test nào đóng mục rồi bấm Áp dụng, hay đổi bề rộng lúc chạy — kết luận dựa trên đọc code.

INV-06 (tự thêm): "Khi Áp dụng bị vô hiệu thì lý do vẫn thấy được dù mục/ô đang đóng". Với casesError: ĐÚNG, vì summary mục Judge = casesError (:833-834). Với lỗi nhãn (trống/trùng): SAI — thông báo `label-error-*` nằm trong thẻ ô; đóng thẻ ô (hoặc cả mục Blocks) thì chỉ còn chấm đỏ ở mục Blocks (:802) và nút Áp dụng xám, không có chữ nào giải thích. Tái hiện: đặt nhãn ô B thành "A" → đóng thẻ ô B → Áp dụng xám, không thấy "Nhãn "A" bị trùng". Mức Minor (cần người dùng chủ động đóng; mở lại là thấy; mặc định mọi thứ mở). Đề xuất sửa: summary mục blocks khi hasLabelError = labelError đầu tiên (như judge làm với casesError). Test bổ sung: nhãn trùng + đóng mục blocks → tìm được chữ "bị trùng" trong summary. Verdict VỠ theo định nghĩa invariant, nhưng mức Minor — orchestrator quyết có chặn commit hay ghi Backlog.

Không có test phủ: đổi bề rộng lúc chạy (qua 700/1100), đóng mục rồi Áp dụng. Layout test chỉ pump từng bề rộng riêng lẻ.
