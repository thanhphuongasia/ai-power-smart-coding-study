# deploy

> Script một lệnh đưa web Flutter + backend FastAPI lên VPS dùng chung qua HTTPS (domain riêng), cộng script build iOS cho TestFlight; dev chạy từ máy có Flutter và SSH.

## Là gì

Module này là thư mục `deploy/`: một script bash, một site nginx và một unit systemd. Nó giải quyết việc
đưa app lên một link công khai để thử trên trình duyệt, mà không làm hỏng các dịch vụ khác trên cùng VPS.
Web và API được phục vụ từ cùng một địa chỉ `https://codewithphuong.jacons-corp.com` (nginx cổng 443, cert Let's Encrypt; iOS chặn HTTP thường nên bắt buộc HTTPS) nên không cần CORS (luật trình duyệt chặn gọi
API khác nguồn). Backend chạy dưới user hệ thống riêng, chỉ nghe ở loopback, còn bí mật nằm trong một file
env duy nhất trên server. Script chạy lại bao nhiêu lần cũng an toàn.

## Dùng khi nào

Developer chạy tay `deploy/deploy.sh` từ máy có Flutter và SSH tới host `vps` (deploy/deploy.sh:2-5).
Địa chỉ công khai là hằng số trong script (`DOMAIN`, `PUBLIC_URL="https://$DOMAIN"`, deploy/deploy.sh:16-18), không còn biến môi trường để ghi đè. Đổi domain: sửa `DOMAIN` ở `deploy/deploy.sh` và `deploy/ios-build.sh` cùng `server_name`/đường dẫn cert trong file nginx, lấy cert mới rồi deploy (deploy/README.md:70-72). Không có CI hay hook tự chạy. Build bản iOS đi qua script riêng, xem mục "iOS / TestFlight" cuối file.

## Cách hoạt động

Một bước kiểm cert rồi bốn bước của script (nhãn `==> n/4` trong deploy/deploy.sh):

| Bước | Việc | file:dòng |
| --- | --- | --- |
| 0 | Kiểm cert Let's Encrypt của domain tồn tại trên VPS TRƯỚC mọi thay đổi (thiếu thì in lệnh `certbot certonly --nginx -d <domain>` và dừng, không build, không rsync) | deploy/deploy.sh:30-33 |
| 1 | `flutter build web --release` với `--dart-define=API_URL=$PUBLIC_URL` (build ở máy dev vì VPS không có Flutter) | deploy/deploy.sh:35-36 |
| 2 | Tạo thư mục tạm root-only (`install -d -m 700`), rsync `backend/` (loại `.initial-passwords`) và `build/web/`, scp file nginx + unit | deploy/deploy.sh:38-49 |
| 3 | Trên server: user `smartcs`, role+DB Postgres, venv, `alembic upgrade head`, nạp nội dung CHỈ khi DB rỗng, seed user, chown root, systemd, nginx, smoke test | deploy/deploy.sh:51-160 |
| 4 | In link | deploy/deploy.sh:163 |

Tính idempotent: env file chỉ sinh khi chưa tồn tại, nên mật khẩu DB không đổi giữa các lần deploy
(deploy/deploy.sh:63); `createdb` chỉ chạy khi DB chưa có (deploy/deploy.sh:77-80). Mật khẩu đi qua stdin của
psql, kèm `SET log_min_error_statement = panic` để câu lệnh lỗi không lọt vào log Postgres
(deploy/deploy.sh:71-73); env ghi ra `.new` rồi `mv` nguyên tử (deploy/deploy.sh:67,75).

```bash
if ! nginx -t 2>/dev/null; then
  if [ -f "$TMP/site.bak" ]; then cp "$TMP/site.bak" "$SITE"; else rm -f "$SITE"; fi
  echo "nginx -t lỗi — đã trả cấu hình cũ, KHÔNG reload" >&2
  ...
  exit 1
fi
systemctl reload nginx
```
(deploy/deploy.sh:127-133)

Smoke test chạy trên server, qua HTTPS thật tới đúng tên miền (`--resolve` ép domain về 127.0.0.1 nên không phụ thuộc DNS của chính VPS). Nếu một bước lỗi, `rollback_site` trả file site nginx cũ (hoặc xoá nếu chưa từng có), `nginx -t` rồi reload, và thoát với lỗi:

```bash
R="--resolve $DOMAIN:443:127.0.0.1"
curl -fsS -m 10 $R -o /dev/null "https://$DOMAIN/content" || rollback_site
...
[ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/)" = 308 ] \
  || { echo ":8090 không chuyển hướng 308" >&2; rollback_site; }
```
(deploy/deploy.sh:142-158)

Tài khoản và nội dung trong bước 3 (deploy/deploy.sh:87-101):

```bash
content_out="$(.venv/bin/python -m app.load_content --if-empty)"
echo "content: $content_out"
install -d -m 700 /etc/smart-coding-study && chmod 700 /etc/smart-coding-study
INITIAL_PASSWORDS_FILE=/etc/smart-coding-study/initial-passwords .venv/bin/python -m app.seed_users
```

| Việc | Hành vi | file:dòng |
| --- | --- | --- |
| Nội dung | `--if-empty`: DB đã có nội dung thì in `skip`, KHÔNG ghi đè (admin có thể đã sửa). Script không bao giờ truyền `--force` | deploy/deploy.sh:94, backend/app/load_content.py:407-409 |
| Seed user | tạo `test@gmail.com` (learner) và `phuongtt.tech1508@gmail.com` (learner + admin) nếu chưa có; user có sẵn thì không đổi mật khẩu, chỉ thêm role thiếu | backend/app/seed_users.py:27-30, 56-59 |
| Mật khẩu ban đầu | sinh ngẫu nhiên, APPEND vào `/etc/smart-coding-study/initial-passwords` (file 0600 mở bằng `O_NOFOLLOW`, thư mục 0700); stdout chỉ in `created N user(s)`, không bao giờ in mật khẩu | backend/app/seed_users.py:34-42, 73-74 |
| File mật khẩu dev | `backend/.initial-passwords` bị rsync loại trừ và bị `rm -f` trên server trước khi mở quyền đọc thư mục app | deploy/deploy.sh:45, 101 |
| Lấy mật khẩu | chủ VPS tự đọc `ssh vps sudo cat /etc/smart-coding-study/initial-passwords`, đăng nhập, đổi mật khẩu, rồi xoá file | deploy/README.md:44-54 |
| Chế độ mở | biến local `DEPLOY_AUTH_OPEN_AS` (mặc định `test@gmail.com`; đặt rỗng để tắt), kiểm dạng email ở máy local rồi lại ở server; trước `systemctl restart`, xoá dòng `AUTH_OPEN_AS=` cũ trong env file và ghi lại dòng mới nếu khác rỗng (đúng 1 dòng, idempotent) | deploy/deploy.sh:21-26, 108-110 |
| Smoke test | qua HTTPS: `/content` và `/` phải 200; `/api/me` không token phải 200 khi chế độ mở bật, 401 khi tắt; `:8090` phải trả 308. Sai bất kỳ cái nào thì rollback site nginx và dừng (chứng minh `location /api/` đã đi vào backend và cờ đã tới backend) | deploy/deploy.sh:149-158 |

Cấu hình đi kèm: deploy/nginx/smart-coding-study.conf có ba server block:

| Server | Việc | file:dòng |
| --- | --- | --- |
| `:8090` (`server_name _`) | `return 308 https://<domain>$request_uri` để link cũ `http://<ip>:8090` vẫn dùng được | deploy/nginx/smart-coding-study.conf:8-13 |
| `:80` cho domain | `return 308` sang https | deploy/nginx/smart-coding-study.conf:15-20 |
| `:443 ssl` cho domain | cert Let's Encrypt (`fullchain.pem`/`privkey.pem` + `options-ssl-nginx.conf` + `ssl-dhparams.pem`); `location = /content` và `= /run` proxy tới 127.0.0.1:8100; `location /api/` proxy cùng chỗ với `proxy_read_timeout 15s`; `location /api/admin/` cho body tới 4200k và timeout 60s vì admin gửi cả bộ nội dung (backend cho 4MB); còn lại `try_files` về `index.html`; `index.html` và service worker `no-cache` | deploy/nginx/smart-coding-study.conf:22-92 |

Unit deploy/systemd/smart-coding-study-api.service: uvicorn `127.0.0.1:8100 --proxy-headers`, `User=smartcs`,
`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`, `ReadOnlyPaths`, `Restart=on-failure`.

Cert lấy MỘT lần bằng `certbot certonly --nginx` (chỉ lấy cert, không để certbot sửa conf); `certbot.timer` có sẵn trên VPS tự gia hạn và, vì renewal conf dùng installer nginx, tự reload nginx (deploy/nginx/smart-coding-study.conf:3-4; planning/crew/2026-10-11-testflight-prep/DEVIATIONS.md).

Bật/tắt chế độ mở (người dùng không cần đăng nhập khi bật, xem `docs/modules/auth-progress.md`):

```bash
deploy/deploy.sh                                 # mặc định: mở, user test@gmail.com
DEPLOY_AUTH_OPEN_AS=<email> deploy/deploy.sh     # mở dưới user khác (email phải có trong DB)
DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh            # TẮT: bật lại màn đăng nhập
```
(deploy/README.md:43-48, deploy/deploy.sh:19-21)

Lưu ý: mặc định của `deploy.sh` là BẬT, nên chạy deploy không đặt biến sẽ mở lại chế độ mở dù lần trước đã tắt. Email không có trong DB thì backend coi như tắt, smoke test mong 200 sẽ thất bại và deploy báo lỗi rõ ràng.

## Ranh giới & đánh đổi

Cách chọn so với phương án khác:

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| Web + API cùng origin qua nginx | web và API khác cổng/host + CORS | không cấu hình CORS, một link duy nhất |
| Domain riêng + Let's Encrypt, 308 từ cổng cũ | IP + HTTP, sslip.io, hoặc ngoại lệ ATS (App Transport Security, luật iOS chặn HTTP thường) | xem docs/DECISIONS.md "HTTPS bằng domain riêng" |
| Kiểm cert trước, rollback site khi smoke lỗi | cài rồi mới phát hiện thiếu cert / để site hỏng chạy tiếp trên nginx dùng chung | deploy/deploy.sh:30-33, 142-147 |
| uvicorn chỉ nghe `127.0.0.1:8100` | mở cổng API ra ngoài | chỉ nginx vào được backend |
| Build web ở máy dev | build trên VPS | VPS không có Flutter |
| Thư mục tạm dưới `/root` (700) | `/tmp` dùng chung | user khác có thể đặt sẵn file để root cài (deploy/deploy.sh:39-40) |
| Chỉ chạm tài nguyên `smart-coding-study`/`smartcs` | cấu hình nginx/DB chung | VPS có 11 site khác (planning/crew/2026-10-11-deploy-vps-web/reviews/SEAM.md, INV-05) |

Module không làm: giới hạn tốc độ `/run`, quản lý user (thêm user = sửa `SEED_USERS` rồi deploy), CI deploy, rollback code/DB (chỉ site nginx có rollback: khi `nginx -t` lỗi hoặc smoke test lỗi), tự ký/upload app lên Apple (user tự làm), bật HSTS.

## iOS / TestFlight

Bản iOS không đi qua `deploy.sh`: nó gọi cùng origin HTTPS với web, nên deploy backend không đòi build lại iOS trừ khi đổi domain (deploy/IOS-TESTFLIGHT.md, mục Lưu ý). Phần Apple (đăng nhập Apple ID trong Xcode, chọn Team, tạo app trên App Store Connect, upload, mời tester) do user tự làm theo `deploy/IOS-TESTFLIGHT.md`; repo chỉ chuẩn bị mọi thứ còn lại.

| Thứ | Việc | file:dòng |
| --- | --- | --- |
| `deploy/ios-build.sh [build-number]` | kiểm số build là số nguyên, có `flutter`, `xcodebuild`, và `DEVELOPMENT_TEAM` trong project (thiếu thì dừng, chỉ về bước 2 của hướng dẫn); `curl` `/content` qua HTTPS; rồi `flutter build ipa --release --dart-define=API_URL=https://$DOMAIN --build-number=...`. Số build mặc định `date +%y%m%d%H` (8 chữ số, luôn tăng) | deploy/ios-build.sh:11-35 |
| `deploy/IOS-TESTFLIGHT.md` | 6 bước: Apple ID trong Xcode, chọn Team, tạo app trên App Store Connect (Bundle ID `com.aipower.smartCodingStudy`), build, upload (Organizer hoặc Transporter), TestFlight; kèm mục Lưu ý và Gặp lỗi | deploy/IOS-TESTFLIGHT.md:1-82 |
| `mobile/tool/make_app_icon.py` | sinh icon tạm `</>` 1024x1024 RGB không alpha bằng thư viện chuẩn rồi `sips` resize ra đủ 15 cỡ khai trong `AppIcon.appiconset/Contents.json`; chạy lại từ `mobile/` để thay icon | mobile/tool/make_app_icon.py:1-9 |
| `Info.plist` | `ITSAppUsesNonExemptEncryption=false` (khỏi bị hỏi export compliance mỗi lần upload), `CFBundleName`=`CodeStudy` (tối đa 15 ký tự) | mobile/ios/Runner/Info.plist:17-20 |

Chế độ mở (xem trên) vẫn áp cho app iOS: ai cài từ TestFlight cũng là `test@gmail.com` (admin) cho tới khi tắt bằng `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh` (deploy/IOS-TESTFLIGHT.md, mục Lưu ý).

Chưa kiểm được: ký, upload và cài từ TestFlight (cần tài khoản Apple của user). `flutter build ios --no-codesign --release` đã chạy OK và `ios-build.sh` đã dừng đúng khi chưa chọn Team (planning/crew/2026-10-11-testflight-prep/STATUS.md).

## Giới hạn đã biết

- `/content` và `/run` vẫn công khai, không `limit_req`; code học viên chuyển tới Judge0 công khai nên IP VPS có
  thể bị chặn (deploy/README.md:66-69).
- Chế độ mở bật mặc định: ai có link là user mở (admin, gồm `/api/admin/*`); đây là giới hạn đã khai của run, tắt bằng `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh` (planning/crew/2026-10-11-auth-open-mode/PLAN.md).
- Đã có HTTPS nhưng chưa bật HSTS (header buộc trình duyệt luôn dùng https); token lưu localStorage 30 ngày (planning/crew/2026-10-11-testflight-prep/STATUS.md Backlog).
- `nginx` giới hạn body `/api/` ở 80k trừ `/api/admin/` (4200k) (deploy/nginx/smart-coding-study.conf:33, 69); `nginx -t` mới chỉ chạy qua deploy thật, chưa có kiểm riêng cho location admin.
- `/run` xếp hàng Semaphore(4) (backend/app/main.py:36) + Judge0 15s có thể vượt `proxy_read_timeout 18s` ->
  504 khi tải cao; chưa đo.
- Cổng 8100 và domain lặp ở nhiều file (domain: deploy/deploy.sh:16, deploy/ios-build.sh:11, deploy/nginx/smart-coding-study.conf:12); chỉ smoke test bắt lệch phía server, `ios-build.sh` bắt bằng `curl /content` trước khi build (deploy/ios-build.sh:28).
- Cổng 80 và 8090 hardcode domain trong `return 308` (deploy/nginx/smart-coding-study.conf:12,19).
- 308 chỉ giữ method/body với client hiểu 308; client rất cũ có thể không theo (docs/DECISIONS.md).
- Thư mục tạm không dọn nếu script chết giữa chừng (deploy/deploy.sh:40).
- Chưa có second opinion từ model họ khác (Codex timeout 2 lần). Code backend trên VPS đã được so với repo
  bằng `rsync -anc` (cùng tham số exclude của deploy/deploy.sh): 0 khác biệt
  (planning/crew/2026-10-11-deploy-vps-web/STATUS.md).

## Nguồn

deploy/deploy.sh:1-163; deploy/ios-build.sh:1-41; deploy/IOS-TESTFLIGHT.md; mobile/tool/make_app_icon.py; mobile/ios/Runner/Info.plist; planning/crew/2026-10-11-testflight-prep/PLAN.md, STATUS.md, DEVIATIONS.md, reviews/SEAM.md; deploy/README.md:1-82; planning/crew/2026-10-11-auth-open-mode/PLAN.md, STATUS.md; deploy/nginx/smart-coding-study.conf:1-92; backend/app/seed_users.py:1-79; planning/crew/2026-10-11-users-progress-admin/PLAN.md (mục 7), STATUS.md;
deploy/systemd/smart-coding-study-api.service:1-22; backend/app/main.py:34-36;
planning/crew/2026-10-11-deploy-vps-web/STATUS.md; reviews/SEAM.md; DEVIATIONS.md.
