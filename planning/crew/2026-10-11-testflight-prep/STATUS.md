Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    (không tạo)

# Status: done — commit a25b41d, đã deploy

T-01 HTTPS (PASS với Minor + external đã xử lý) · T-02 icon/Info.plist · T-03 ios-build + hướng dẫn (PASS với Minor). SEAM PASS, verify-seam exit 0.
Kiểm thật: https://codewithphuong.jacons-corp.com 200, cert hợp lệ (CN đúng, hết hạn 2027-01-09); /content 200; /api/me open; :8090 và :80 → 308 https; POST /run qua :8090 giữ POST → passed; site khác (studybuddy, fishingrod, identity 200; github-mcp 401 như cũ); `certbot renew --dry-run` success. `flutter build ios --no-codesign --release` OK (worker T-02); `deploy/ios-build.sh` dừng đúng khi chưa chọn Team.
Chưa kiểm được: ký + upload + TestFlight (cần tài khoản Apple của user) — deploy/IOS-TESTFLIGHT.md.
Backlog: docs/ còn nhắc http://ip:8090 (distill); HSTS chưa bật; domain lặp ở 3 file.
