#!/usr/bin/env bash
# Build bản iOS release (.ipa + .xcarchive) để đưa lên TestFlight. Chạy trên máy Mac có Xcode:
#
#   deploy/ios-build.sh            # build number = giờ hiện tại (yyMMddHH), luôn tăng
#   deploy/ios-build.sh 26101122   # tự đặt (vd build 2 lần trong cùng một giờ: tăng số cuối)
#
# Trước lần đầu: đăng nhập Apple ID trong Xcode và chọn Team cho target Runner — xem
# deploy/IOS-TESTFLIGHT.md. App gọi server qua HTTPS (iOS chặn HTTP thường).
set -euo pipefail

DOMAIN=codewithphuong.jacons-corp.com
API_URL="https://$DOMAIN"
BUILD_NUMBER="${1:-$(date +%y%m%d%H)}"  # 8 chữ số: < 2^31, luôn tăng theo thời gian
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/mobile/ios/Runner.xcodeproj/project.pbxproj"

case "$BUILD_NUMBER" in
  '' | *[!0-9]*) echo "build number phải là số nguyên: '$BUILD_NUMBER'" >&2; exit 1 ;;
esac
command -v flutter >/dev/null || { echo "Không thấy flutter trong PATH" >&2; exit 1; }
xcodebuild -version >/dev/null || { echo "Cần Xcode (xcodebuild)" >&2; exit 1; }
if ! grep -q 'DEVELOPMENT_TEAM = ' "$PBXPROJ"; then
  echo "Chưa chọn Team ký app: mở mobile/ios/Runner.xcworkspace → Runner → Signing & Capabilities" >&2
  echo "→ chọn Team (Automatically manage signing). Xem deploy/IOS-TESTFLIGHT.md bước 2." >&2
  exit 1
fi
# Server phải trả lời qua HTTPS trước khi build (app không có server thì vô dụng trên TestFlight).
curl -fsS -m 15 -o /dev/null "$API_URL/content" \
  || { echo "Không gọi được $API_URL/content — kiểm server/HTTPS trước" >&2; exit 1; }

VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$ROOT/mobile/pubspec.yaml")"
echo "==> build iOS $VERSION ($BUILD_NUMBER), API_URL=$API_URL"
(cd "$ROOT/mobile" && flutter build ipa --release \
  --dart-define=API_URL="$API_URL" \
  --build-number="$BUILD_NUMBER")

echo
echo "==> xong. Archive: mobile/build/ios/archive/Runner.xcarchive"
ls "$ROOT"/mobile/build/ios/ipa/*.ipa 2>/dev/null && echo "    IPA ở trên — tải lên bằng Transporter," \
  || echo "    (chưa xuất được .ipa — mở archive bằng Xcode Organizer để Distribute)"
echo "    hoặc: open mobile/build/ios/archive/Runner.xcarchive → Distribute App → App Store Connect."
