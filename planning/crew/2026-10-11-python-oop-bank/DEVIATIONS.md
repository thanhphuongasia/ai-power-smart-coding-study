# Deviations — append-only
- Plan crew mặc định: worktree + PR · Thực tế: thẳng trên main (memory work-directly-on-main) · Duyệt: user
- Plan không có backend/app/harness.py · Thực tế: harness kiểm method bằng callable(...) nên bài property (owner_name, balance) luôn báo 'Không tìm thấy method' → đổi sang hasattr (1 dòng) · Duyệt: orchestrator
