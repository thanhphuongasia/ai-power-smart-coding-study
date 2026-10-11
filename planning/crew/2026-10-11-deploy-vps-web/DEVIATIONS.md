# Deviations — 2026-10-11-deploy-vps-web

| Plan nói gì | Thực tế là gì | Quyết định | Ai duyệt |
|---|---|---|---|
| Project rule L4: có second opinion từ crew-review-external trước khi chạy | Codex timeout 2 lần (360s, 600s) — không có output | Deploy dựa trên crew-review r1 (CẦN SỬA → sửa) + r2 PASS với Minor (kiểm read-only trên VPS); ghi rõ trong báo cáo là chưa có second opinion khác họ | orchestrator |
