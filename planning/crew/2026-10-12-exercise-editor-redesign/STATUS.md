Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-12-exercise-editor-redesign
Branch:   crew/2026-10-12-exercise-editor-redesign
Issue:    #25 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/25

State: P4 — T-01, T-02, T-03, T-03b đóng; verify-seam OK; 514 test xanh, analyze sạch. PR mở, chờ user merge.
Next action: user xem PR + chụp màn web 3 bề rộng (chưa kiểm bằng mắt), merge, deploy.

Backlog (Minor, không sửa trong run):
- INV-06 còn một phần: đóng RIÊNG một thẻ ô (mục vẫn mở) thì lỗi nhãn không hiện, chỉ còn chấm đỏ ở mục + nút Áp dụng xám
- code_cell: mất màu khi IME composing; lineEnd O(n²) dòng cực dài; _charWidth=8.6 hardcode; thiếu test escape; không nhận """ nhiều dòng; toolbar Row cứng overflow khi cell rộng <252px; cases không viền đỏ khi lỗi (errorText không có Key)
- collapsible_section: import package: thay vì relative; thiếu Semantics expanded
- exercise_editor: mục lục chỉ cuộn tới header, không tự mở mục đóng; không có nút "Thu gọn/Mở tất cả" (state nằm trong widget); chưa test biên 700/1100 và đổi cỡ giữa chừng; nút Huỷ/Áp dụng nằm thanh dưới ở mọi layout (mockup đặt ở header với layout rộng)
