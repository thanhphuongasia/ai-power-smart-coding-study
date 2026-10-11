# SEAM review — 2026-10-11-deploy-vps-web (reviewer mối nối)

Đối chiếu bằng lệnh thật: `diff` file cài trên VPS với repo (nginx + unit: giống từng byte), `curl` origin 8090,
đọc `alembic_version`/`content_meta` qua `ssh vps` (chỉ SELECT), `git grep`, `journalctl`.

INV-01: CÒN ĐÚNG — deploy/deploy.sh:13 · deploy/deploy.sh:18 · mobile/lib/data/content_repository.dart:12 · deploy/nginx/smart-coding-study.conf:5 — main.dart.js tải từ server chứa "http://178.105.5.12:8090" (2 chỗ), nginx nghe 8090, /content qua origin trả 200.
INV-02: CÒN ĐÚNG — deploy/nginx/smart-coding-study.conf:19 · deploy/nginx/smart-coding-study.conf:26 · deploy/systemd/smart-coding-study-api.service:12 · backend/app/main.py:106 · backend/app/content_api.py:169 — proxy_pass 127.0.0.1:8100 = uvicorn --port 8100 (ss: uvicorn 127.0.0.1:8100); GET /content 200, GET /run 405 (route có thật, chỉ POST).
INV-03: CÒN ĐÚNG — deploy/nginx/smart-coding-study.conf:10 · deploy/nginx/smart-coding-study.conf:31 · backend/app/main.py:34 · backend/app/runner.py:75 · mobile/lib/data/judge_client.dart:63 — 80k > 64KB; read_timeout 18s nằm giữa HTTP 15s và client 20s; POST body 70KB nhận 413 từ backend (không phải nginx), POST chunked vẫn tới backend với Content-Length (422 chứ không 411).
INV-04: CÒN ĐÚNG — deploy/deploy.sh:71 · deploy/deploy.sh:72 · backend/migrations/versions/0001_content_tables.py · backend/content/content.json — alembic_version=0001 (head duy nhất); content_meta.version = sha256:c22b6dff… = tự tính lại từ content.json của repo bằng compute_version = version /content trả về.
INV-05: CÒN ĐÚNG — deploy/deploy.sh:84 · deploy/deploy.sh:94 · deploy/deploy.sh:22 — mọi đường dẫn/tên đều thuộc smart-coding-study/smartcs; reload sau `nginx -t` (có rollback); e2e/vps_baseline.txt vs vps_after.txt khác đúng một dòng (8090: 000→200), 11 site khác giữ mã cũ; STAGE dưới /root đã bị xoá.
INV-06: CÒN ĐÚNG — deploy/deploy.sh:48 · deploy/deploy.sh:52 · deploy/systemd/smart-coding-study-api.service:11 — `git grep` hex-48/DATABASE_URL: chỉ có template printf `%s` ở deploy.sh:48, không có mật khẩu thật; mật khẩu đi qua stdin psql; env root:smartcs 640; journalctl unit, /var/log/syslog, auth.log: 0 khớp.

## Phát hiện khác

- Minor · deploy/nginx/smart-coding-study.conf:31 — `proxy_read_timeout 18s` nhưng backend có Semaphore(4) (backend/app/main.py:34): request xếp hàng chờ slot cộng 15s Judge0 có thể vượt 18s -> nginx 504 trong khi backend vẫn chạy. Chỉ lộ khi tải cao; client đằng nào cũng timeout 20s và hiện "unavailable". Test: bắn 6 /run đồng thời.
- Minor · deploy/nginx/smart-coding-study.conf:25 — /run công khai không limit_req (user đã chấp nhận, đã ở Backlog).
- Minor · deploy/deploy.sh:22 — STAGE không dọn nếu script chết giữa chừng (root 700, không bí mật). Đã ở Backlog.
- Ghi chú: cổng 8090/8100 lặp ở 3 file; hiện khớp, chỉ smoke test bắt lệch (đã ở Backlog).

Không kiểm được: code backend đã rsync trên VPS có giống repo từng byte không (không chạy rsync -n); chỉ suy ra từ version nội dung + unit/nginx giống hệt. Không có second opinion khác họ (DEVIATIONS.md).

Kết luận: không có VỠ — 6/6 CÒN ĐÚNG, chỉ Minor.
