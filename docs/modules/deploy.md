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
| 2 | Tạo thư mục tạm root-only (`install -d -m 700`), rsync `backend/` và `build/web/`, scp file nginx + unit | deploy/deploy.sh:20-30 |
| 3 | Trên server: user `smartcs`, role+DB Postgres, venv, `alembic upgrade head`, nạp nội dung, chown root, systemd, nginx | deploy/deploy.sh:35-105 |
| 4 | In link | deploy/deploy.sh:108 |

Tính idempotent: env file chỉ sinh khi chưa tồn tại, nên mật khẩu DB không đổi giữa các lần deploy
(deploy/deploy.sh:45); `createdb` chỉ chạy khi DB chưa có (deploy/deploy.sh:59). Mật khẩu đi qua stdin của
psql, kèm `SET log_min_error_statement = panic` để câu lệnh lỗi không lọt vào log Postgres
(deploy/deploy.sh:52-54); env ghi ra `.new` rồi `mv` nguyên tử (deploy/deploy.sh:48,56).

```bash
if ! nginx -t 2>/dev/null; then
  if [ -f "$TMP/site.bak" ]; then cp "$TMP/site.bak" "$SITE"; else rm -f "$SITE"; fi
  echo "nginx -t lỗi — đã trả cấu hình cũ, KHÔNG reload" >&2
  ...
  exit 1
fi
systemctl reload nginx
```
(deploy/deploy.sh:88-94)

Cấu hình đi kèm: deploy/nginx/smart-coding-study.conf (nghe 8090; `location = /content` và `= /run` proxy tới
127.0.0.1:8100, còn lại `try_files` về `index.html`; `index.html` và service worker `no-cache`) và
deploy/systemd/smart-coding-study-api.service (uvicorn `127.0.0.1:8100 --proxy-headers`, `User=smartcs`,
`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`, `ReadOnlyPaths`, `Restart=on-failure`).

## Ranh giới & đánh đổi

Cách chọn so với phương án khác:

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| Web + API cùng origin qua nginx | web và API khác cổng/host + CORS | không cấu hình CORS, một link duy nhất |
| uvicorn chỉ nghe `127.0.0.1:8100` | mở cổng API ra ngoài | chỉ nginx vào được backend |
| Build web ở máy dev | build trên VPS | VPS không có Flutter |
| Thư mục tạm dưới `/root` (700) | `/tmp` dùng chung | user khác có thể đặt sẵn file để root cài (deploy/deploy.sh:21-22) |
| Chỉ chạm tài nguyên `smart-coding-study`/`smartcs` | cấu hình nginx/DB chung | VPS có 11 site khác (planning/crew/2026-10-11-deploy-vps-web/reviews/SEAM.md, INV-05) |

Module không làm: HTTPS/domain, xác thực, giới hạn tốc độ `/run`, CI deploy, rollback code/DB (chỉ site nginx
có rollback khi `nginx -t` lỗi).

## Giới hạn đã biết

- Link công khai, không mật khẩu, không `limit_req`; code học viên chuyển tới Judge0 công khai nên IP VPS có
  thể bị chặn (deploy/README.md:36-41). HTTP thường.
- `/run` xếp hàng Semaphore(4) (backend/app/main.py:36) + Judge0 15s có thể vượt `proxy_read_timeout 18s` ->
  504 khi tải cao; chưa đo.
- Cổng 8090/8100 lặp ở ba file, chỉ smoke test bắt lệch (deploy/deploy.sh:13, deploy/README.md:9).
- Thư mục tạm không dọn nếu script chết giữa chừng (deploy/deploy.sh:22).
- Chưa có second opinion từ model họ khác (Codex timeout 2 lần); chưa so từng byte code backend đã rsync
  trên VPS với repo (SEAM.md, "Không kiểm được").

## Nguồn

deploy/deploy.sh:1-108; deploy/README.md:1-41; deploy/nginx/smart-coding-study.conf:1-48;
deploy/systemd/smart-coding-study-api.service:1-22; backend/app/main.py:34-36;
planning/crew/2026-10-11-deploy-vps-web/STATUS.md; reviews/SEAM.md; DEVIATIONS.md.
