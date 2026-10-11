Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    (không tạo — run demo nhỏ theo yêu cầu trực tiếp)

# Status: done — commit a12ee78, đã deploy

T-01 backend · T-02 app (T-02b) · T-03 deploy — đều đóng (review PASS với Minor; external đã xử lý). SEAM PASS, verify-seam exit 0.
Kiểm chứng: pytest 331 passed · flutter analyze sạch, flutter test +438 · e2e local cờ tắt 20/20, cờ bật: /api/me open, PUT progress 204, /run ghi passed, token thật thắng.
VPS: /api/me không token → {"email":"test@gmail.com","roles":["learner","admin"],"open":true}; /api/progress 200; /api/admin/content 200; env có đúng 1 dòng AUTH_OPEN_AS.

Backlog: phiên mở trong RAM khi server tắt cờ → 401 không tự về màn đăng nhập; /account/password mở bằng URL ở phiên mở báo "phiên hết hạn"; giá trị activity không có cận trên (run trước).
Tắt chế độ mở: `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh`.
