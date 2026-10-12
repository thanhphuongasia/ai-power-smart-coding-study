# Deploy lên VPS

Một lệnh, chạy từ máy có Flutter và SSH tới VPS (host `vps` trong `~/.ssh/config`):

```bash
deploy/deploy.sh
```

Link: **https://codewithphuong.jacons-corp.com** (web + API cùng origin; link cũ `http://178.105.5.12:8090` chuyển hướng 308 sang đây). App iOS (TestFlight) gọi cùng origin — xem `deploy/IOS-TESTFLIGHT.md`.

## Tự động khi merge main

`.github/workflows/deploy.yml` chạy đúng `deploy/deploy.sh` mỗi lần push vào `main` (hoặc bấm tay
ở tab Actions → Deploy VPS). Cần 4 secret của repo (Settings → Secrets and variables → Actions),
thiết lập một lần:

| Secret | Giá trị |
|---|---|
| `VPS_HOST` | IP/hostname của VPS |
| `VPS_USER` | user SSH (`root`: `deploy.sh` ghi `/opt`, `/etc`, cài systemd/nginx) |
| `VPS_SSH_KEY` | private key RIÊNG cho deploy (`ssh-keygen -t ed25519 -f deploy_key`, public key thêm vào `authorized_keys` của root trên VPS) |
| `VPS_KNOWN_HOSTS` | output của `ssh-keyscan <VPS_HOST>` (ghim host key) |

Key này có quyền root trên VPS dùng chung: không dùng lại key cá nhân, và nên bật required review
cho PR vào `main` vì ai merge được là deploy được.

## Trên server có gì

| Thứ | Ở đâu |
|---|---|
| Web Flutter (build/web) | `/opt/smart-coding-study/web`, nginx phục vụ HTTPS 443 cho domain (cổng 80 và 8090 chỉ chuyển hướng) |
| HTTPS | cert Let's Encrypt `/etc/letsencrypt/live/codewithphuong.jacons-corp.com/` (lấy một lần bằng `sudo certbot certonly --nginx -d codewithphuong.jacons-corp.com`; `certbot.timer` tự gia hạn) |
| Backend FastAPI | `/opt/smart-coding-study/backend`, systemd `smart-coding-study-api`, `127.0.0.1:8100` |
| nginx site | `/etc/nginx/sites-enabled/smart-coding-study.conf` (`/content`, `/run` → 8100; còn lại → web) |
| Bí mật | `/etc/smart-coding-study.env` (root:smartcs, 640) — `DATABASE_URL` có mật khẩu sinh ngẫu nhiên |
| DB | Postgres local, database `smart_coding_study`, role `smartcs` |
| User chạy service | `smartcs` (hệ thống, không shell) |

Mỗi lần deploy: build web với `API_URL` = link công khai → rsync → cài thư viện → `alembic upgrade
head` → nạp `backend/content/content.json` **chỉ khi DB chưa có nội dung** (`--if-empty`) → seed user
còn thiếu → restart service → `nginx -t` rồi mới reload (lỗi thì trả cấu hình cũ). Chạy lại nhiều lần
không sao.

## Nội dung: DB là nguồn chính

Admin sửa nội dung trong app (nút Admin → Soạn nội dung → Kiểm tra → Lưu). Deploy **không** ghi đè DB
nữa, nên sửa `content.json` rồi deploy sẽ không có tác dụng. Muốn sửa bằng file:

```bash
ssh vps
cd /opt/smart-coding-study/backend && set -a && . /etc/smart-coding-study.env && set +a
.venv/bin/python -m app.export_content /root/content.json        # 1. xuất bản đang chạy (có judge)
# 2. sửa /root/content.json (hoặc scp bản đã sửa lên)
.venv/bin/python -m app.load_content --force /root/content.json  # 3. kiểm đủ luật rồi thay toàn bộ
```

`--force` kiểm cùng bộ luật với admin (schema, ghép đáp án == lời giải, ≤3 ô, sơ đồ khớp code…); sai
thì không ghi gì. Tiến độ học viên nằm ở bảng riêng, không bị xoá khi thay nội dung.

## Chế độ mở (demo, không đăng nhập)

Mặc định deploy bật `AUTH_OPEN_AS=test@gmail.com` trong `/etc/smart-coding-study.env`: mở link là vào
thẳng app dưới tài khoản đó (admin + học viên), tiến độ lưu cho tài khoản đó. Ai có link cũng là user
này. Bật lại đăng nhập: `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh`. Đổi user mở:
`DEPLOY_AUTH_OPEN_AS=<email> deploy/deploy.sh`.

## Tài khoản

`app.seed_users` tạo `test@gmail.com` (học viên + admin, tài khoản test) và `phuongtt.tech1508@gmail.com` (admin + học viên)
nếu chưa có, mật khẩu ngẫu nhiên. Mật khẩu ban đầu **chỉ** nằm trong file root 600, không in ra log:

```bash
ssh vps sudo cat /etc/smart-coding-study/initial-passwords
```

Nhiều dòng cùng một email (lần seed trước lỗi giữa chừng) thì dòng **cuối** là đúng. Đăng nhập rồi đổi mật khẩu (nút tài khoản → Đổi mật khẩu), sau đó nên xoá file:
`ssh vps sudo rm /etc/smart-coding-study/initial-passwords`. User đã có thì seed không đổi mật khẩu.
Đặt lại mật khẩu (thu hồi mọi phiên cũ của user đó; thay `MAT_KHAU`):

```bash
printf '%s' 'MAT_KHAU' | ssh vps 'cd /opt/smart-coding-study/backend && set -a && . /etc/smart-coding-study.env && set +a && .venv/bin/python -m app.set_password test@gmail.com'
```

Chưa có trang quản lý user: thêm user = thêm vào `SEED_USERS` trong `backend/app/seed_users.py` rồi deploy.

Đổi domain: sửa `DOMAIN` trong `deploy/deploy.sh` + `deploy/ios-build.sh` + `server_name`/đường dẫn cert
trong `deploy/nginx/smart-coding-study.conf`, lấy cert cho domain mới, rồi deploy. Deploy dừng (không đụng
nginx) nếu chưa có cert.

## Xem log / thao tác tay

```bash
ssh vps journalctl -u smart-coding-study-api -n 100 --no-pager
ssh vps systemctl restart smart-coding-study-api
```

## Rủi ro đang chấp nhận (tạm thời)

- Link **công khai, không mật khẩu, không giới hạn** — ai có link đều Run được; backend chuyển code
  tới Judge0 công khai, bị lạm dụng thì IP VPS có thể bị Judge0 chặn.
- Token lưu ở localStorage của trình duyệt (30 ngày): trang dính XSS thì lộ token.
- Giới hạn đăng nhập sai (5 lần/15 phút theo IP+email, 30 lần/IP) đếm trong RAM: restart là reset.
- VPS dùng chung với dịch vụ khác: script chỉ chạm tài nguyên tên `smart-coding-study`/`smartcs`.
