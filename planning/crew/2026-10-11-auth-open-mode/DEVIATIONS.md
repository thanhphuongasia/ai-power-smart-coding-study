# Deviations — append-only
- Plan crew mặc định: worktree + PR · Thực tế: thẳng trên main (memory work-directly-on-main) · Duyệt: user (chỉ thị trước)
- Plan T-01 owned không có tests/test_auth.py · Thực tế: fixture client_for override get_user_lookup gọi user_for_token(token) — /run giờ luôn gọi lookup kể cả token None → đổi 1 dòng sang auth.resolve_user · Duyệt: orchestrator
- Review T-01 Minor + SEAM #1: đổi mật khẩu ở chế độ mở xoá hết phiên thật → 403 `open_mode` · Duyệt: orchestrator
- External T-01 "Critical" (giá trị DEPLOY_AUTH_OPEN_AS có thể phá quote/chèn lệnh qua ssh + env file): chỉ operator đặt được nhưng sửa rẻ → kiểm dạng email ở local + server, ghi env ngay trước restart · Duyệt: orchestrator
- Sự cố: reviewer T-01 (read-only) tự chạy `git stash`/`stash pop` trong lúc worker T-02b đang sửa file → kiểm lại: stash list rỗng, mọi thay đổi còn; seam reviewer thấy working tree "tạm thiếu field open" lúc đó · Ghi recurring-failures
