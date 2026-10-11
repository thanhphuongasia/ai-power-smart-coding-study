# Deploy lên VPS

Một lệnh, chạy từ máy có Flutter và SSH tới VPS (host `vps` trong `~/.ssh/config`):

```bash
deploy/deploy.sh
```

Link test: **http://178.105.5.12:8090** (web + API cùng origin).

## Trên server có gì

| Thứ | Ở đâu |
|---|---|
| Web Flutter (build/web) | `/opt/smart-coding-study/web`, nginx phục vụ ở cổng 8090 |
| Backend FastAPI | `/opt/smart-coding-study/backend`, systemd `smart-coding-study-api`, `127.0.0.1:8100` |
| nginx site | `/etc/nginx/sites-enabled/smart-coding-study.conf` (`/content`, `/run` → 8100; còn lại → web) |
| Bí mật | `/etc/smart-coding-study.env` (root:smartcs, 640) — `DATABASE_URL` có mật khẩu sinh ngẫu nhiên |
| DB | Postgres local, database `smart_coding_study`, role `smartcs` |
| User chạy service | `smartcs` (hệ thống, không shell) |

Mỗi lần deploy: build web với `API_URL` = link công khai → rsync → cài thư viện → `alembic upgrade
head` → nạp `backend/content/content.json` → restart service → `nginx -t` rồi mới reload (lỗi thì
trả cấu hình cũ). Chạy lại nhiều lần không sao.

Đổi IP/cổng: `PUBLIC_URL=http://<ip>:<cổng> deploy/deploy.sh` (cổng nginx sửa ở
`deploy/nginx/smart-coding-study.conf`).

## Xem log / thao tác tay

```bash
ssh vps journalctl -u smart-coding-study-api -n 100 --no-pager
ssh vps systemctl restart smart-coding-study-api
```

## Rủi ro đang chấp nhận (tạm thời)

- Link **công khai, không mật khẩu, không giới hạn** — ai có link đều Run được; backend chuyển code
  tới Judge0 công khai, bị lạm dụng thì IP VPS có thể bị Judge0 chặn.
- HTTP thường, chưa có domain/HTTPS.
- VPS dùng chung với dịch vụ khác: script chỉ chạm tài nguyên tên `smart-coding-study`/`smartcs`.
