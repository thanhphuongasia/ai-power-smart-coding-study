# STATUS — 2026-10-11-deploy-vps-web

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-deploy-vps-web
Branch:   crew/2026-10-11-deploy-vps-web (từ origin/main e68a600)
Issue:    #13 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/13

State: done (chờ user merge PR) — deploy chạy ở http://178.105.5.12:8090; verify-seam exit 0 (6/6)

| Task | Title | State |
|---|---|---|
| T-01 | File deploy (nginx, systemd, deploy.sh, README) | done — r1 CẦN SỬA (mật khẩu argv/log, /tmp cố định) → sửa → r2 PASS với Minor; external timeout 2 lần (chưa có second opinion) |
| T-02 | Build web + deploy lần đầu + e2e | done — deploy 2 lần (idempotent), e2e đạt |

E2E (link http://178.105.5.12:8090):
- curl: / 200 text/html; main.dart.js gzip 1.45MB; /content 3 theme 5 bài, 0 judge/cases; /run split-chunks passed 6/6 2.8s
- bí mật: auth.log 0 lần mật khẩu, log Postgres 0; env root:smartcs 640; staging dir đã xoá
- site khác trước/sau deploy: chỉ 8090 đổi 000→200, mọi site/cổng khác giữ nguyên (e2e/vps_baseline.txt vs vps_after.txt)
- deploy lần 2: cùng version sha256:c22b6dff…, env không bị sinh lại (mtime giữ), không lỗi
- Chrome thật: Home nội dung API → tiếp tục split-chunks → gõ B, C → Run → 6/6 test đạt (e2e/browser_run_passed.jpg) → Bài tiếp theo mở overlap-chunks
rsync dry-run repo↔VPS: 0 khác biệt.
Next action: user review + merge PR (file deploy); deploy lại: deploy/deploy.sh.

Backlog (Minor):
- /run công khai không limit_req (user chấp nhận tạm)
- cổng 8090/8100 lặp ở 3 file, chỉ smoke test bắt lệch
- STAGE không xoá nếu script chết giữa chừng (root 700, không chứa bí mật)
- main.dart.js/flutter_bootstrap.js chưa có cache-busting riêng (Flutter tự gắn hash qua service worker)
- crew-review-external timeout 2 lần với Codex (360s, 600s) cho task deploy
- SEAM: /run xếp hàng (Semaphore 4) + Judge0 15s có thể vượt proxy_read_timeout 18s → 504 khi tải cao
