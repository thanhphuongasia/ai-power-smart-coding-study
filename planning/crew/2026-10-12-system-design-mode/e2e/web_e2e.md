# E2E trên app web thật (Chrome, khung 390px) + backend thật + Postgres riêng

Dựng: `e2e/web_e2e_setup.py` (DB, nội dung, user, tài liệu airline đã publish) → `flutter build web --dart-define=API_URL=http://127.0.0.1:8791`
→ `e2e/web_e2e_server.py` (backend + web cùng origin, AUTH_OPEN_AS=ann@e2e.test) → trang `phone.html` (iframe 390x790) để có bố cục điện thoại.

Đã đi qua, bằng chuột/bàn phím thật:
1. Home → tab Design (tab thứ 5, 4 tab cũ không đổi) → thẻ tài liệu "0/9 section · 0/26 card".  (screens/01)
2. Lộ trình Phase 1: banner xanh "CHAPTER 1 · 0/3 SECTION", đĩa 3D zigzag, node xanh dương + quầng + bóng "BẮT ĐẦU", node khoá xám.  (screens/02)
3. Màn đọc: thanh trên navy + thanh tiến độ, tờ giấy trắng chữ serif; lướt qua hết section 1 thì tự đánh dấu, hiện "Xong: Problem Description · tiếp: Requirements", thanh trên đổi sang "Requirements".  (screens/03, 04)
4. Phase 1 xong (qua API cho nhanh): lộ trình tự cuộn tới node "Bối cảnh" (BẮT ĐẦU), API Design mở, các task sau khoá.  (screens/05)
5. Màn Bối cảnh (yêu cầu chức năng, phi chức năng, quy mô) → "Bắt đầu API Design".  (screens/06)
6. Màn task: đề, 3 gợi ý, ô viết với bộ đếm byte (84/8192 cho câu có dấu), nộp → "Lần 1 · 50 điểm · Chấm sơ bằng từ khoá", ✓/✗ từng ý, "Xem đáp án mẫu", "Task tiếp theo".  (screens/07, 08)
7. Claude chấm sâu (gọi đúng hàm `review_queue/review_detail/submit_feedback` mà tool MCP dùng) → bấm "Làm mới" trong app → "Claude đã chấm" + ghi chú từng ý + khối nhận xét chung; bản reviewed thay bản từ khoá.  (screens/09)

Phát hiện khi chạy thật (không bắt được ở widget test): bảng trong màn đọc rộng hơn màn hình điện thoại, cột phải bị cắt chữ → sửa ở block_renderer (bảng co theo bề rộng, chữ xuống dòng).
8. Sau khi sửa bảng (block_renderer): bảng vừa khung 390px, chữ xuống dòng, không cắt cột.  (screens/10)
