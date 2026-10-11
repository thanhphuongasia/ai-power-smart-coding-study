# Deviations — append-only
- Plan crew mặc định: worktree + branch + PR · Thực tế: user yêu cầu làm thẳng trên main (memory work-directly-on-main, 2026-10-11) · Quyết định: không worktree/PR, commit checkpoint trên main, push + deploy sau seam gate · Duyệt: user (chỉ thị trước đó)
- Plan: T-03 không sở hữu browse_screens_test.dart · Thực tế: fixture JSON tự viết trong file đó thiếu key `diagram` (parse nghiêm) · Quyết định: orchestrator thêm key rỗng (cơ học) · Duyệt: orchestrator
- Plan: T-01 đóng sau review nội bộ · Thực tế: external review (lần 2) bắt Major alias from_ · Quyết định: orchestrator sửa schema (bỏ populate_by_name) + test, không đổi hợp đồng JSON (vẫn key from) · Duyệt: orchestrator
