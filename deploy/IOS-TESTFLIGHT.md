# Đưa app lên TestFlight

App: **Smart Coding Study** · Bundle ID `com.aipower.smartCodingStudy` · server
`https://codewithphuong.jacons-corp.com` (iOS chỉ cho gọi HTTPS).

Đã chuẩn bị sẵn trong repo:

| | |
|---|---|
| Icon | `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset` — icon tạm `</>`, đủ 15 cỡ, không alpha. Thay: sửa `mobile/tool/make_app_icon.py` rồi `cd mobile && python3 tool/make_app_icon.py` |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` trong `Info.plist` → không bị hỏi mỗi lần upload |
| Version | `version:` trong `mobile/pubspec.yaml` (hiện `1.0.0`); build number do script đặt, luôn tăng |
| Build | `deploy/ios-build.sh` |

Các bước dưới cần tài khoản Apple của bạn — làm một lần (trừ bước 4–6 lặp lại mỗi bản mới).

## 1. Đăng nhập Apple ID trong Xcode

Xcode → **Settings…** → **Accounts** → **+** → Apple ID → đăng nhập tài khoản Apple Developer.

## 2. Chọn Team cho app

```bash
open mobile/ios/Runner.xcworkspace
```

Chọn project **Runner** → target **Runner** → tab **Signing & Capabilities**:

- Tick **Automatically manage signing**.
- **Team**: chọn team Apple Developer của bạn.
- **Bundle Identifier**: giữ `com.aipower.smartCodingStudy` (đổi thì nhớ đổi cả ở bước 3).

Xcode tự tạo App ID + chứng chỉ. Lưu lại; file `project.pbxproj` sẽ có `DEVELOPMENT_TEAM` — commit
thay đổi đó để lần sau không phải chọn lại.

## 3. Tạo app trên App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**:

- Platform: **iOS** · Name: `Smart Coding Study` (tên phải chưa ai dùng, trùng thì thêm hậu tố)
- Primary language: Vietnamese · Bundle ID: `com.aipower.smartCodingStudy` · SKU: vd `smart-coding-study`
- User access: Full Access

## 4. Build

```bash
deploy/ios-build.sh
```

Script kiểm đã chọn Team, kiểm server HTTPS trả lời, rồi `flutter build ipa` (build number =
`yyMMddHH`; build hai lần trong cùng một giờ thì truyền số lớn hơn: `deploy/ios-build.sh 26101122`). Kết quả: `mobile/build/ios/archive/Runner.xcarchive` và (nếu ký được)
`mobile/build/ios/ipa/*.ipa`.

## 5. Upload

Chọn một trong hai:

- **Xcode Organizer**: `open mobile/build/ios/archive/Runner.xcarchive` → **Distribute App** →
  **App Store Connect** → **Upload** → Next đến hết.
- **Transporter** (App Store, miễn phí): kéo file `.ipa` vào → **Deliver**.

Apple xử lý bản build 5–30 phút; xong sẽ có email.

## 6. TestFlight

App Store Connect → app → **TestFlight**:

- **Internal Testing** → tạo nhóm → thêm người (phải là thành viên team trong App Store Connect). Không
  cần Apple duyệt, cài được ngay qua app **TestFlight** trên iPhone.
- **External Testing** (người ngoài team, qua email/link công khai): cần Apple duyệt bản beta lần đầu
  (~1 ngày); phải điền mô tả + thông tin liên hệ.

## Lưu ý

- Server đang ở **chế độ mở** (`AUTH_OPEN_AS=test@gmail.com`): ai cài app cũng là tài khoản đó (có
  quyền admin). Bật lại đăng nhập: `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh`.
- Mỗi lần upload phải có build number lớn hơn lần trước — script tự lo nếu dùng mặc định.
- Đổi `version:` trong `pubspec.yaml` khi phát hành phiên bản mới (vd `1.0.1`).
- Bản web và iOS dùng cùng server: deploy backend (`deploy/deploy.sh`) không cần build lại iOS, trừ khi
  đổi domain.

## Gặp lỗi

Các bước Apple (ký, upload, TestFlight) chưa được chạy thử trên máy thật lần nào — lần đầu có thể vướng:

| Lỗi | Xử lý |
|---|---|
| `No signing certificate` / `No profiles for 'com.aipower.smartCodingStudy'` | Bước 1–2: đăng nhập Apple ID trong Xcode và chọn Team; mở Xcode build thử một lần (Product → Archive) để Xcode tự tạo chứng chỉ |
| Bundle ID đã bị dùng | Đổi Bundle ID ở bước 2 (vd thêm hậu tố), dùng đúng ID đó ở bước 3 |
| Upload báo `The bundle version must be higher` | Chạy lại script với build number lớn hơn |
| App mở ra báo không tải được nội dung | Kiểm `https://codewithphuong.jacons-corp.com/content` mở được trên Safari; bản build phải từ `deploy/ios-build.sh` (build tay thiếu `--dart-define=API_URL` sẽ trỏ về máy dev) |
