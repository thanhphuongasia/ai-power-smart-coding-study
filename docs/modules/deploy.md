# deploy

> Script một lệnh đưa web Flutter + backend FastAPI lên VPS dùng chung; dev chạy từ máy có Flutter và SSH.

## Là gì

Module này là thư mục `deploy/`: một script bash, một site nginx và một unit systemd. Nó giải quyết việc
đưa app lên một link công khai để thử trên trình duyệt, mà không làm hỏng các dịch vụ khác trên cùng VPS.
Web và API được phục vụ từ cùng một địa chỉ (nginx cổng 8090) nên không cần CORS (luật trình duyệt chặn gọi
API khác nguồn). Backend chạy dưới user hệ thống riêng, chỉ nghe ở loopback, còn bí mật nằm trong một file
env duy nhất trên server. Script chạy lại bao nhiêu lần cũng an toàn.

## Dùng khi nào

Developer chạy tay `deploy/deploy.sh` từ máy có Flutter và SSH tới host `vps` (deploy/deploy.sh:2-5).
Đổi địa chỉ thì truyền `PUBLIC_URL=http://<ip>:<cổng>` (deploy/README.md:26-27). Không có CI hay hook tự
chạy.

## Cách hoạt động

Bốn bước của script (nhãn `==> n/4` trong deploy/deploy.sh):

| Bước | Việc | file:dòng |
| --- | --- | --- |
| 1 | `flutter build web --release` với `--dart-define=API_URL=$PUBLIC_URL` (build ở máy dev vì VPS không có Flutter) | deploy/deploy.sh:17-18 |
| 2 | Tạo thư mục tạm root-only (`install -d -m 700`), rsync `backend/` (loại `.initial-passwords`) và `build/web/`, scp file nginx + unit | deploy/deploy.sh:20-31 |
| 3 | Trên server: user `smartcs`, role+DB Postgres, venv, `alembic upgrade head`, nạp nội dung CHỈ khi DB rỗng, seed user, chown root, systemd, nginx | deploy/deploy.sh:33-119 |
| 4 | In link | deploy/deploy.sh:121 |

Tính idempotent: env file chỉ sinh khi chưa tồn tại, nên mật khẩu DB không đổi giữa các lần deploy
(deploy/deploy.sh:46); `createdb` chỉ chạy khi DB chưa có (deploy/deploy.sh:60). Mật khẩu đi qua stdin của
psql, kèm `SET log_min_error_statement = panic` để câu lệnh lỗi không lọt vào log Postgres
(deploy/deploy.sh:53-55); env ghi ra `.new` rồi `mv` nguyên tử (deploy/deploy.sh:49,57).

```bash
if ! nginx -t 2>/dev/null; then
  if [ -f "$TMP/site.bak" ]; then cp "$TMP/site.bak" "$SITE"; else rm -f "$SITE"; fi
  echo "nginx -t lỗi — đã trả cấu hình cũ, KHÔNG reload" >&2
  ...
  exit 1
fi
systemctl reload nginx
```
(deploy/deploy.sh:98-104)

Tài khoản và nội dung trong bước 3 (deploy/deploy.sh:70-83):

```bash
content_out="$(.venv/bin/python -m app.load_content --if-empty)"
echo "content: $content_out"
install -d -m 700 /etc/smart-coding-study && chmod 700 /etc/smart-coding-study
INITIAL_PASSWORDS_FILE=/etc/smart-coding-study/initial-passwords .venv/bin/python -m app.seed_users
```

| Việc | Hành vi | file:dòng |
| --- | --- | --- |
| Nội dung | `--if-empty`: DB đã có nội dung thì in `skip`, KHÔNG ghi đè (admin có thể đã sửa). Script không bao giờ truyền `--force` | deploy/deploy.sh:76-77, backend/app/load_content.py:407-409 |
| Seed user | tạo `test@gmail.com` (learner) và `phuongtt.tech1508@gmail.com` (learner + admin) nếu chưa có; user có sẵn thì không đổi mật khẩu, chỉ thêm role thiếu | backend/app/seed_users.py:27-30, 56-59 |
| Mật khẩu ban đầu | sinh ngẫu nhiên, APPEND vào `/etc/smart-coding-study/initial-passwords` (file 0600 mở bằng `O_NOFOLLOW`, thư mục 0700); stdout chỉ in `created N user(s)`, không bao giờ in mật khẩu | backend/app/seed_users.py:34-42, 73-74 |
| File mật khẩu dev | `backend/.initial-passwords` bị rsync loại trừ và bị `rm -f` trên server trước khi mở quyền đọc thư mục app | deploy/deploy.sh:27, 83 |
| Lấy mật khẩu | chủ VPS tự đọc `ssh vps sudo cat /etc/smart-coding-study/initial-passwords`, đăng nhập, đổi mật khẩu, rồi xoá file | deploy/README.md:44-54 |
| Smoke test | `/api/me` không token qua nginx phải trả 401, ngược lại deploy dừng (chứng minh `location /api/` đã đi vào backend) | deploy/deploy.sh:114-116 |

Cấu hình đi kèm: deploy/nginx/smart-coding-study.conf (nghe 8090; `location = /content` và `= /run` proxy tới
127.0.0.1:8100; `location /api/` proxy tới cùng chỗ với `proxy_read_timeout 15s`; `location /api/admin/` cho body tới 4200k và timeout 60s
vì admin gửi cả bộ nội dung (backend cho 4MB); còn lại `try_files` về `index.html`; `index.html` và service worker `no-cache`) và
deploy/systemd/smart-coding-study-api.service (uvicorn `127.0.0.1:8100 --proxy-headers`, `User=smartcs`,
`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`, `ReadOnlyPaths`, `Restart=on-failure`).

## Ranh giới & đánh đổi

Cách chọn so với phương án khác:

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| Web + API cùng origin qua nginx | web và API khác cổng/host + CORS | không cấu hình CORS, một link duy nhất |
| uvicorn chỉ nghe `127.0.0.1:8100` | mở cổng API ra ngoài | chỉ nginx vào được backend |
| Build web ở máy dev | build trên VPS | VPS không có Flutter |
| Thư mục tạm dưới `/root` (700) | `/tmp` dùng chung | user khác có thể đặt sẵn file để root cài (deploy/deploy.sh:21-24) |
| Chỉ chạm tài nguyên `smart-coding-study`/`smartcs` | cấu hình nginx/DB chung | VPS có 11 site khác (planning/crew/2026-10-11-deploy-vps-web/reviews/SEAM.md, INV-05) |

Module không làm: HTTPS/domain, giới hạn tốc độ `/run`, quản lý user (thêm user = sửa `SEED_USERS` rồi deploy), CI deploy, rollback code/DB (chỉ site nginx
có rollback khi `nginx -t` lỗi).

## Giới hạn đã biết

- `/content` và `/run` vẫn công khai, không `limit_req`; code học viên chuyển tới Judge0 công khai nên IP VPS có
  thể bị chặn (deploy/README.md:66-69).
- HTTP thường, chưa domain/HTTPS: mật khẩu và token đăng nhập đi không mã hoá; token lưu localStorage 30 ngày
  (deploy/README.md:70-72). Cần domain + HTTPS trước khi dùng thật.
- `nginx` giới hạn body `/api/` ở 80k trừ `/api/admin/` (4200k) (deploy/nginx/smart-coding-study.conf:10, 43); `nginx -t` mới chỉ chạy qua deploy thật, chưa có kiểm riêng cho location admin.
- `/run` xếp hàng Semaphore(4) (backend/app/main.py:36) + Judge0 15s có thể vượt `proxy_read_timeout 18s` ->
  504 khi tải cao; chưa đo.
- Cổng 8090/8100 lặp ở ba file, chỉ smoke test bắt lệch (deploy/deploy.sh:13, deploy/README.md:9).
- Thư mục tạm không dọn nếu script chết giữa chừng (deploy/deploy.sh:22).
- Chưa có second opinion từ model họ khác (Codex timeout 2 lần). Code backend trên VPS đã được so với repo
  bằng `rsync -anc` (cùng tham số exclude của deploy/deploy.sh): 0 khác biệt
  (planning/crew/2026-10-11-deploy-vps-web/STATUS.md).

## Nguồn

deploy/deploy.sh:1-121; deploy/README.md:1-75; deploy/nginx/smart-coding-study.conf:1-65; backend/app/seed_users.py:1-79; planning/crew/2026-10-11-users-progress-admin/PLAN.md (mục 7), STATUS.md;
deploy/systemd/smart-coding-study-api.service:1-22; backend/app/main.py:34-36;
planning/crew/2026-10-11-deploy-vps-web/STATUS.md; reviews/SEAM.md; DEVIATIONS.md.
