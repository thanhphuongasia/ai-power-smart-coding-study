# Run `testflight-prep` — HTTPS domain + iOS sẵn sàng TestFlight

## Context

User muốn đưa app lên TestFlight. iOS chặn HTTP thường (ATS) nên app phải gọi server qua HTTPS. User có
domain `codewithphuong.jacons-corp.com` (DNS A → 178.105.5.12, đã kiểm). Tài khoản Apple Developer đã có,
chưa tạo app trên App Store Connect, máy chưa có chứng chỉ ký — phần Apple user tự làm, tôi chuẩn bị mọi
thứ còn lại + hướng dẫn. Icon hiện là mặc định Flutter → tạo icon tạm. Git: thẳng trên main, deploy sau
test xanh + seam gate.

## Thiết kế

1. **HTTPS trên VPS dùng chung** (nginx 80/443 phục vụ nhiều site; certbot + tài khoản có sẵn):
   - Một lần: `certbot certonly --nginx -d codewithphuong.jacons-corp.com` (chỉ lấy cert, không sửa config;
     gia hạn qua `certbot.timer` sẵn có). Nếu certbot đòi đồng ý điều khoản mới → dừng, hỏi user.
   - `deploy/nginx/smart-coding-study.conf`: server `443 ssl` cho domain (cert + `options-ssl-nginx.conf`
     + `ssl-dhparams.pem` như site khác) chứa toàn bộ location hiện có (web, /content, /run, /api/,
     /api/admin/ 4200k); server `80` domain → 301 https; server `:8090` → 301 `https://<domain>$request_uri`
     (link cũ vẫn dùng được). Chỉ file site của app này.
   - `deploy/deploy.sh`: `PUBLIC_URL` mặc định `https://codewithphuong.jacons-corp.com`; build web với URL
     đó; deploy kiểm cert tồn tại trước khi cài conf (thiếu → báo lệnh certbot, dừng); smoke check qua
     `curl --resolve <domain>:443:127.0.0.1 https://…` (content, /api/me 200 khi chế độ mở) + `:8090` trả 301.
2. **iOS**:
   - Icon tạm: script Python thuần (zlib, không cần PIL) vẽ `</>` màu nhấn trên nền tối 1024×1024 RGB
     (không alpha) → `sips` ra đủ 15 cỡ trong `AppIcon.appiconset` (tên file như Contents.json hiện có).
     Script giữ lại ở `mobile/tool/make_app_icon.py` để thay icon sau.
   - `Info.plist`: `ITSAppUsesNonExemptEncryption=false`, `CFBundleName` = `CodeStudy` (≤15 ký tự),
     giữ `CFBundleDisplayName` "Smart Coding Study", giữ `NSAllowsLocalNetworking`.
   - `deploy/ios-build.sh`: kiểm Xcode + Team đã chọn (cảnh báo nếu chưa có `DEVELOPMENT_TEAM`);
     `flutter build ipa --release --dart-define=API_URL=https://codewithphuong.jacons-corp.com
     --build-number=<tham số hoặc YYYYMMDDHHMM>`; in đường dẫn `.ipa`/`.xcarchive` và bước upload.
3. **Hướng dẫn** `deploy/IOS-TESTFLIGHT.md`: (1) Xcode → Settings → Accounts đăng nhập Apple ID;
   (2) mở `ios/Runner.xcworkspace` → Signing & Capabilities → chọn Team (Automatic) — ghi Team ID vào
   project; (3) App Store Connect → Apps → + → iOS, Bundle ID `com.aipower.smartCodingStudy`, tên, SKU;
   (4) `deploy/ios-build.sh`; (5) upload bằng Xcode Organizer (Distribute → App Store Connect) hoặc
   Transporter; (6) TestFlight → nhóm tester nội bộ; ghi chú chế độ mở (ai cài cũng là test@gmail.com),
   export compliance đã khai trong Info.plist, số build phải tăng mỗi lần.

## Sổ bất biến

```text
INV-01 · Mọi bản build trỏ đúng một origin HTTPS và origin đó phục vụ cả web lẫn API: web (deploy.sh PUBLIC_URL) và iOS (ios-build.sh API_URL) = https://codewithphuong.jacons-corp.com; nginx 443 có đủ location /content /run /api/ /api/admin/
         phải khớp: deploy/deploy.sh · deploy/ios-build.sh · deploy/nginx/smart-coding-study.conf · mobile/lib/data/content_repository.dart (apiBaseUrl)
         vỡ thì thấy gì: web/iOS báo không tải được nội dung; iOS lỗi ATS
INV-02 · Deploy chỉ chạm site của app này và không làm sập nginx dùng chung: conf mới qua `nginx -t` mới reload, lỗi thì trả bản cũ; không sửa site khác, không để certbot ghi conf
         phải khớp: deploy/deploy.sh (khối nginx) · deploy/nginx/smart-coding-study.conf
         vỡ thì thấy gì: các site *.jacons-corp.com khác lỗi sau deploy
INV-03 · Link cũ http://178.105.5.12:8090 vẫn dùng được (301 sang https domain) và chế độ mở/HTTP-API giữ hành vi (deploy smoke)
         phải khớp: deploy/nginx/smart-coding-study.conf (server 8090) · deploy/deploy.sh (smoke)
         vỡ thì thấy gì: bookmark cũ chết, smoke deploy fail
INV-04 · Icon 1024 không có alpha, đủ 15 file đúng tên Contents.json; Info.plist có ITSAppUsesNonExemptEncryption=false
         phải khớp: mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/* · mobile/ios/Runner/Info.plist
         vỡ thì thấy gì: upload TestFlight bị Apple từ chối (icon alpha / thiếu cỡ)
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | orchestrator · L4 (hạ tầng/TLS, VPS dùng chung) · session | lấy cert; nginx 443/80/8090; deploy.sh https + kiểm cert + smoke | `deploy/nginx/smart-coding-study.conf`, `deploy/deploy.sh`, `deploy/README.md` | `bash -n deploy/deploy.sh` + deploy + curl https |
| T-02 | `crew-impl-light` · T1 · haiku | icon tạm (script + 15 PNG RGB) + Info.plist | `mobile/tool/make_app_icon.py`, `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/*`, `mobile/ios/Runner/Info.plist` | `python3 mobile/tool/make_app_icon.py && sips -g hasAlpha …1024…png` + `flutter build ios --no-codesign --release` |
| T-03 | orchestrator · L1 · session | `deploy/ios-build.sh` + `deploy/IOS-TESTFLIGHT.md` | `deploy/ios-build.sh`, `deploy/IOS-TESTFLIGHT.md` | `bash -n deploy/ios-build.sh` |

Song song: T-01 ‖ T-02 (ownership rời) → T-03. Review: T-01 `crew-review` + `crew-review-external`
(EXTERNAL_AGENT_TIMEOUT=360, rule L4); T-02 `crew-review`; seam reviewer INV-01..04 → `verify-seam.sh`
→ commit, push, deploy.

## Verification (orchestrator tự chạy)

1. `flutter analyze`, `flutter test` (không đổi Dart nhưng chạy cho chắc), `flutter build ios --no-codesign --release --dart-define=API_URL=https://codewithphuong.jacons-corp.com` thành công.
2. VPS: `curl -sI https://codewithphuong.jacons-corp.com/` 200, cert hợp lệ (không `-k`), `/api/me` 200;
   `curl -sI http://178.105.5.12:8090/` → 301 https; site khác vẫn 200 (vd `https://studybuddy.jacons-corp.com` HEAD).
3. Chrome (nếu cửa sổ hiển thị — kiểm `document.visibilityState` trước) mở https domain → Home.
4. Không thể kiểm upload/TestFlight (cần tài khoản user) → ghi rõ trong báo cáo.

## Giới hạn

- Ký app + upload + tạo app ASC: user tự làm (hướng dẫn kèm). Chưa chạy `flutter build ipa` có ký được.
- Chế độ mở: ai cài TestFlight cũng là test@gmail.com (admin).
