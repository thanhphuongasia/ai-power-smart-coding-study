# Run `deploy-vps-web` — đưa backend + bản web lên VPS, link test qua IP:cổng

## Context

`main` (đã có PR #9, #12) chạy được local: FastAPI + Postgres (`backend/`), app Flutter có bản web
(`mobile/web`, `--dart-define=API_URL`, lib không dùng `dart:io`). User muốn link test công khai.

User đã chốt: máy `vps` (root, Ubuntu 24.04, IPv4 **178.105.5.12**); **IP + cổng, HTTP**; **chưa bảo
vệ** (không mật khẩu, không rate limit); Judge0 công khai.

Khảo sát VPS (read-only): nginx 1.24 (`sites-enabled/*.conf`, `nginx -t` đang sạch), Postgres 16
local, Python 3.12 (venv/ensurepip OK), rsync có; app khác ở `/opt/<tên>` + systemd; iptables INPUT
ACCEPT; cổng **8090** (public) và **8100** (local) trống. Máy dùng chung ~15 dịch vụ — không đụng.

Git: worktree tách từ **`origin/main`** (main local đang cũ + có thay đổi chưa commit của user).

## Quyết định thiết kế

1. **Một origin cho web + API**: nginx `listen 8090` phục vụ web tĩnh và proxy `/content`, `/run`
   → `127.0.0.1:8100`. Web build với `API_URL=http://178.105.5.12:8090` → không cần CORS.
2. **Backend**: `/opt/smart-coding-study/backend` (rsync từ repo, bỏ `.venv`, `tests`, `__pycache__`,
   `.env`), venv riêng, chạy bằng systemd `smart-coding-study-api.service` dưới **user hệ thống
   riêng `smartcs`** (không shell) — dịch vụ công khai không bảo vệ thì không chạy bằng root.
3. **DB**: database `smart_coding_study` + role `smartcs` (mật khẩu ngẫu nhiên sinh trên server).
   Bí mật chỉ nằm ở `/etc/smart-coding-study.env` (root:smartcs, 640). `alembic upgrade head` +
   `python -m app.load_content` mỗi lần deploy (idempotent).
4. **Web**: `flutter build web --release` ở máy local (VPS không có Flutter), rsync
   `build/web` → `/opt/smart-coding-study/web`.
5. **File deploy trong repo** (`deploy/`): nginx site, systemd unit, `deploy.sh` (chạy từ máy
   local: build web → rsync → lệnh remote idempotent → `nginx -t` rồi mới reload), README.
6. Không đổi code app/backend trừ khi build web lộ lỗi (khi đó tách correction task).

## Sổ bất biến

```text
INV-01 · API_URL nướng vào bản web = origin công khai nginx nghe (http://178.105.5.12:8090)
         phải khớp: deploy/deploy.sh · deploy/nginx/smart-coding-study.conf · mobile/lib/data/content_repository.dart (apiBaseUrl)
         vỡ thì thấy gì: web mở ra màn "Không tải được nội dung" dù /content trả 200
INV-02 · Đường proxy nginx = route FastAPI (/content, /run) và cổng upstream = cổng uvicorn trong unit
         phải khớp: deploy/nginx/smart-coding-study.conf · deploy/systemd/smart-coding-study-api.service · backend/app/main.py · backend/app/content_api.py
         vỡ thì thấy gì: 404 hoặc 502 trên /content, /run
INV-03 · Giới hạn chuỗi: nginx client_max_body_size ≥ MAX_BODY_BYTES 64KB; nginx proxy_read_timeout > thời gian chấm (Judge0 HTTP 15s) và < timeout client /run 20s; nginx giữ Content-Length
         phải khớp: deploy/nginx/smart-coding-study.conf · backend/app/main.py:34 · backend/app/runner.py:75 · mobile/lib/data/judge_client.dart:63
         vỡ thì thấy gì: 413 từ nginx với code hợp lệ, hoặc 504 trước khi backend trả timeout
INV-04 · DB trên VPS ở migration head và nạp đúng content.json của commit deploy
         phải khớp: deploy/deploy.sh · backend/migrations · backend/content/content.json
         vỡ thì thấy gì: /content 503 content_not_loaded, hoặc nội dung cũ
INV-05 · Deploy chỉ chạm tài nguyên của nó: /opt/smart-coding-study, unit + site + env + DB/role tên smart-coding-study/smartcs; nginx reload chỉ sau `nginx -t` sạch
         phải khớp: deploy/deploy.sh
         vỡ thì thấy gì: site khác trên VPS (studybuddy, fishing-rod…) chết sau deploy
INV-06 · Bí mật (mật khẩu DB) chỉ ở env file trên server, không trong repo, không in ra log/console
         phải khớp: deploy/deploy.sh · deploy/systemd/smart-coding-study-api.service
         vỡ thì thấy gì: `git grep` / output deploy có mật khẩu
```

## Task

| ID | Role · Tier | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | orchestrator (L4: server dùng chung, công khai) | Viết file deploy | `deploy/nginx/smart-coding-study.conf`, `deploy/systemd/smart-coding-study-api.service`, `deploy/deploy.sh`, `deploy/README.md` | `bash -n deploy/deploy.sh && shellcheck deploy/deploy.sh` (nếu có) + `nginx -t` trên VPS với file tạm |
| T-02 | orchestrator | Build web local + chạy deploy lần đầu lên VPS | — (thao tác) | e2e dưới đây |

Review: `crew-review` (T2) + `crew-review-external` (timeout 360, theo project rule L4) cho T-01
trước khi chạy T-02. Reviewer mối nối sau T-02.

## Verification (e2e — orchestrator tự chạy)

1. Trước deploy: ghi mã HTTP các site đang chạy trên VPS (vd `curl -sI https://studybuddy.jacons-corp.com`, `:5080`, `:8088`) làm mốc.
2. `curl http://178.105.5.12:8090/` → 200 HTML; `/content` → 200, 5 bài, không `judge`; `/run` lời giải split-chunks → passed.
3. Mở link bằng trình duyệt (Claude in Chrome): Home hiện nội dung từ API (không banner) → vào bài → gõ 3 ô → Run → passed → Bài tiếp theo.
4. Sau deploy: các site mốc ở bước 1 trả đúng mã cũ (INV-05); `systemctl is-active smart-coding-study-api`.
5. Deploy lần 2 (idempotent) không lỗi, version nội dung không đổi.
6. Reviewer mối nối INV-01..06 → `verify-seam.sh` → PR.

## Giới hạn / rủi ro (nói rõ với user)

- **Link công khai, không bảo vệ**: ai có link đều dùng được và gửi code qua backend tới Judge0
  công khai → bị lạm dụng thì IP VPS có thể bị Judge0 chặn (ảnh hưởng chỉ tính năng Run).
- HTTP thường (không mã hoá); mật khẩu/không có — chỉ là dữ liệu bài tập.
- Không HTTPS/domain; app mobile thật cần build riêng với `API_URL` này.
