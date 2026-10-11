# SEAM review — testflight-prep

INV-01: CÒN ĐÚNG — deploy/deploy.sh:16-18,31 · deploy/ios-build.sh:11-12,34 · deploy/nginx/smart-coding-study.conf:21-24 (443, location /content :40, /run, /api/, /api/admin/ 4200k) · mobile/lib/data/content_repository.dart:12-16 — web (PUBLIC_URL) và iOS (API_URL) cùng = https://codewithphuong.jacons-corp.com. apiBaseUrl() đọc đúng biến API_URL; mọi repo (progress/auth/admin/judge) dùng chung hàm đó. Default 127.0.0.1:8000 chỉ dùng khi quên dart-define; ios-build.sh luôn truyền. DOMAIN lặp ở 3 file (hằng, không đọc chung) - lệch thì chỉ người đọc bắt được.
INV-02: CÒN ĐÚNG — deploy/deploy.sh:114-130 · deploy/nginx/smart-coding-study.conf:1-30 — kiểm cert trước khi đụng nginx (dòng 115-118), nginx -t lỗi thì trả bản cũ + không reload (121-127). Chỉ ghi sites-enabled/smart-coding-study.conf; conf chỉ có 3 server của app; cert dùng certonly (không sửa conf). VPS (ssh read-only): cert /etc/letsencrypt/live/codewithphuong.jacons-corp.com/{fullchain,privkey}.pem, options-ssl-nginx.conf, ssl-dhparams.pem đều tồn tại; không site nào khác khai server_name codewithphuong hay default_server; :8090 chỉ site của app. Lưu ý nhỏ: chỉ kiểm fullchain.pem, không kiểm privkey/options-ssl/dhparam, nhưng nginx -t sẽ bắt và rollback.
INV-03: CÒN ĐÚNG (chưa chạy trên VPS) — deploy/nginx/smart-coding-study.conf:7-12 (8090 -> 301 https://domain$request_uri) · deploy/deploy.sh:136-146 (smoke qua --resolve domain:443, /api/me want 200 khi AUTH_OPEN_AS, 8090 phải 301) — logic khớp. VPS hiện vẫn conf cũ (chưa deploy) nên hành vi thật chưa kiểm được. 301 làm POST đổi thành GET: link/bookmark GET ổn, client cũ gọi API POST qua :8090 sẽ hỏng (chỉ web bản cũ; web mới build lại với URL https).
INV-04: CÒN ĐÚNG — mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/ (15 PNG, sips: hasAlpha no cả 15, 1024 = 1024px, 83.5@2x = 167px, kích cỡ khớp tên; Contents.json liệt kê 15 filename) · mobile/ios/Runner/Info.plist:17-20 (CFBundleName=CodeStudy, ITSAppUsesNonExemptEncryption=false) — đủ và đúng tên.

## Mối nối chưa khai

1. Tài liệu còn nói 8090/HTTP/PUBLIC_URL override: docs/ARCHITECTURE.md:34,408,419,427,436,493 · docs/modules/deploy.md:9,25,65,107 · docs/DECISIONS.md:361 (smoke "/api/me trả 401", "nghe 8090", `PUBLIC_URL` override đã bỏ ở deploy.sh:18). Không chặn; cần distill (P5) cập nhật.
2. CORS: web và API cùng origin https nên không cần; backend không có CORS/origin check (grep backend/app không có) - iOS (không có Origin) ổn. Không vỡ.
3. ATS: Info.plist:29-32 chỉ NSAllowsLocalNetworking (không có NSAllowsArbitraryLoads); URL https hợp lệ, không cần ngoại lệ. Nhưng build iOS không truyền API_URL (flutter run/build thường) sẽ trỏ http://127.0.0.1:8000 - chỉ ios-build.sh đặt đúng; ghi vào IOS-TESTFLIGHT.md là đủ.
4. X-Forwarded-Proto mới thêm ở nginx; backend không đọc X-Forwarded-*/X-Real-IP cho giới hạn đăng nhập (grep không thấy) - không ảnh hưởng. Chế độ mở: ai cài TestFlight là test@gmail.com (admin) - đã khai ở PLAN.
5. Mặc định deploy không còn nhận PUBLIC_URL từ môi trường (deploy.sh:18); README.md "Đổi domain" đã cập nhật khớp.

Verdict: PASS (4/4 bất biến còn đúng; không chặn commit). Chưa kiểm được: hành vi thật sau deploy (VPS còn conf cũ), upload TestFlight, build ios.

## Sau sửa
INV-03: CÒN ĐÚNG — deploy/nginx/smart-coding-study.conf:12 · deploy/deploy.sh:157 — đổi 301→308 (giữ POST), smoke kiểm 308; kiểm thật sau deploy.
