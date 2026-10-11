# Deviations — append-only
- Plan crew mặc định: worktree + PR · Thực tế: thẳng trên main (memory work-directly-on-main) · Duyệt: user
- T-02: orchestrator chỉnh toạ độ nét icon sau khi xem ảnh (dấu / dính vào < >) — đổi SEGMENTS/STROKE_R trong mobile/tool/make_app_icon.py, sinh lại 15 PNG · Duyệt: orchestrator
- External T-01: 301→308 (giữ POST) · kiểm cert dời lên đầu deploy.sh (trước build/rsync, tránh deploy nửa chừng) · rollback site khi smoke lỗi (cũng là Minor review nội bộ) → đã sửa. Bác bỏ "renewal không reload nginx": renewal conf có installer=nginx → certbot tự reload, giống mọi site khác trên VPS · Duyệt: orchestrator
- Review nội bộ T-01: redirect cổng 80 hardcode domain (đồng nhất 8090) → đã sửa; certbot renew --dry-run chạy sau deploy · Review T-02/T-03: build number 8 chữ số (yyMMddHH) + mục "Gặp lỗi" trong guide → đã sửa; bác bỏ "precheck /content cần auth khi tắt chế độ mở": /content luôn công khai · Duyệt: orchestrator
