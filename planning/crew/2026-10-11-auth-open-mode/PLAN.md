# Run `auth-open-mode` — bỏ màn đăng nhập (chế độ mở bằng cờ), demo không cần mật khẩu

## Context

User đang demo, không muốn đăng nhập/đặt mật khẩu ("bỏ auth đi"). Giữ toàn bộ code auth của run
`users-progress-admin`, chỉ thêm **chế độ mở** bật bằng biến môi trường `AUTH_OPEN_AS=<email>`:
request không có token hợp lệ được coi là user đó (test@gmail.com — đã có role learner + admin trên VPS).
Tắt biến → hành vi y như hiện tại. Git: thẳng trên main, commit + push + deploy sau khi test xanh và
qua seam gate.

## Thiết kế

1. **Backend** (`backend/app/auth.py`, `backend/app/main.py`):
   - `open_user(session)`: đọc `AUTH_OPEN_AS` lúc gọi → `CurrentUser(..., session_id=0)` hoặc None
     (biến rỗng / email không có trong DB → None → hành vi cũ 401).
   - `current_user`: token hợp lệ thắng (user thật); không có/sai → `open_user`; vẫn None → 401.
     `require_admin` dùng lại nên /api/admin/* mở theo role của user đó.
   - `/run`: `get_user_lookup` nhận `token | None`; không có user từ token → `open_user` → ghi
     passed cho user đó.
   - `GET /api/me` trả thêm `"open": true|false` (true khi phiên là user mở). Login response
     không đổi.
   - Logout ở chế độ mở: `session_id=0` không xoá gì → 204 (vô hại).
2. **App** (`mobile/lib/data/auth_repository.dart`, `api_client.dart`,
   `features/browse/home_screen.dart`):
   - `restore()`: không có token lưu → gọi `GET /api/me` không header; 200 + `open:true` →
     `AuthSession(token: '', user, open: true)`. Lỗi/401 → null (màn login như cũ).
   - `ApiClient`: chỉ gắn `Authorization` khi token khác rỗng; 401 với token rỗng không gọi
     `expire()` (không vòng lặp).
   - Menu tài khoản: phiên `open` → ẩn "Đổi mật khẩu" và "Đăng xuất", hiện email + "Chế độ mở".
     AuthGate không đổi (restore trả phiên → vào thẳng app, tiến độ tải như cũ).
3. **Deploy** (`deploy/deploy.sh`, `deploy/README.md`): biến local `DEPLOY_AUTH_OPEN_AS` (mặc định
   `test@gmail.com`). Bước cài đặt: xoá dòng `AUTH_OPEN_AS=` cũ trong `/etc/smart-coding-study.env`
   rồi ghi lại nếu biến khác rỗng (idempotent; systemd đã đọc file qua `EnvironmentFile`). Bật lại
   đăng nhập: `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh`.

## Sổ bất biến

```text
INV-01 · Tắt cờ (không có AUTH_OPEN_AS) → mọi hành vi auth y như trước: 401/403, login, logout, đổi mật khẩu
         phải khớp: backend/app/auth.py (current_user, open_user) · backend/tests/test_auth.py · mobile/test/auth_gate_test.dart
         vỡ thì thấy gì: test auth cũ đỏ; tắt cờ mà vẫn vào được không cần token
INV-02 · Hợp đồng `/api/me` field `open` khớp backend ↔ app; phiên mở có token rỗng
         phải khớp: backend/app/auth.py (me) · mobile/lib/data/auth_repository.dart (restore, AuthSession.open)
         vỡ thì thấy gì: bật cờ mà app vẫn hiện màn đăng nhập
INV-03 · Bật cờ: tiến độ + passed ghi cho đúng user mở (PUT progress không token → 204; /run không token đúng → passed được lưu)
         phải khớp: backend/app/main.py (/run) · backend/app/progress.py (Depends(current_user)) · mobile/lib/data/progress_api.dart (snapshot gắn token '')
         vỡ thì thấy gì: tải lại trang mất tiến độ ở chế độ mở
INV-04 · Token thật luôn thắng user mở; header Bearer rỗng không bao giờ được gửi; 401 với token rỗng không gây vòng expire
         phải khớp: backend/app/auth.py (current_user) · mobile/lib/data/api_client.dart (ApiClient.send)
         vỡ thì thấy gì: admin đăng nhập thật lại bị coi là test user; app nhấp nháy về màn login
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | orchestrator · L4 (authz) · session | `open_user`, current_user/require_admin/`/run`/`/api/me open` + test chế độ mở | `backend/app/auth.py`, `backend/app/main.py`, `backend/tests/test_open_mode.py` | `cd backend && .venv/bin/python -m pytest -q` |
| T-02 | `crew-impl-standard` · T2 · sonnet | restore chế độ mở, ApiClient không gửi Bearer rỗng, ẩn menu đăng xuất/đổi mật khẩu + test (bắt đầu từ Home) | `mobile/lib/data/auth_repository.dart`, `mobile/lib/data/api_client.dart`, `mobile/lib/features/browse/home_screen.dart`, `mobile/test/open_mode_test.dart` | `cd mobile && flutter analyze && flutter test` |
| T-03 | orchestrator · L1 · session | deploy bật cờ idempotent + README | `deploy/deploy.sh`, `deploy/README.md` | `bash -n deploy/deploy.sh` |

Thứ tự: T-01 ‖ T-02 (ownership rời) → T-03. Review: T-01 `crew-review` + `crew-review-external`
(`EXTERNAL_AGENT_TIMEOUT=360`, rule L4); T-02 `crew-review`; T-03 kiểm bằng `bash -n` + e2e VPS.
Rồi reviewer mối nối INV-01..04 → `verify-seam.sh` → commit, push, deploy.

## Verification (orchestrator tự chạy)

1. `pytest -q`, `flutter analyze`, `flutter test`.
2. Local, uvicorn **không** có cờ: e2e script cũ 20/20 (INV-01).
3. Local, uvicorn **có** `AUTH_OPEN_AS=test@gmail.com`: `/api/me` không token → 200 `open:true`;
   PUT progress không token → 204; `/run` lời giải không token → GET progress thấy passed (INV-03);
   login thật bằng admin → `/api/me` trả admin, không phải test (INV-04).
4. VPS sau deploy: `/api/me` không token → 200 `open:true`; mở web vào thẳng Home, có nút Admin.

## Giới hạn (1 dòng trong báo cáo)

Chế độ mở: ai có link cũng là test@gmail.com (admin) — tắt bằng `DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh`.
