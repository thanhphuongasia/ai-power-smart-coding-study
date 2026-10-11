# Run `users-progress-admin` — đăng nhập, tiến độ theo user trên server, trang quản trị nội dung (DB là nguồn chính)

## Context

Hiện app **không có user**: tiến độ (draft, passed, gợi ý, đã xem lời giải), lịch ôn và streak chỉ ở RAM từ
`mobile/lib/data/demo_seed.dart` → tải lại là mất. Màn Admin (`mobile/lib/features/admin/*`) chỉ là mô phỏng
hàng chờ duyệt. Nội dung: `content.json` → `load_content` thay toàn bộ DB **mỗi lần deploy**.

User đã chốt: seed `test@gmail.com` (học viên) + `phuongtt.tech1508@gmail.com` (admin + học viên); email +
mật khẩu (random, chỉ lưu hash, mật khẩu ban đầu ở file root-only trên VPS, không qua chat); **DB là nguồn
chính** của nội dung, trang quản trị sửa thẳng DB, deploy không ghi đè. Git: thẳng trên main.

## Quyết định thiết kế

1. **Auth** (backend, `app/auth.py`):
   - Bảng `users` (email unique, `password_hash` argon2id qua `argon2-cffi`, `roles text[]` ⊆ {learner, admin}).
   - Bảng `sessions` (lưu **sha256 của token**, `user_id`, `expires_at` 30 ngày). Token opaque `secrets.token_urlsafe(32)`, gửi `Authorization: Bearer`.
   - Login sai 5 lần / 15 phút theo (IP, email) → 429 (đếm trong RAM, đủ cho 1 process uvicorn).
   - Đổi mật khẩu bắt buộc mật khẩu cũ, mật khẩu mới ≥ 10 ký tự; đổi xong thu hồi các session khác.
2. **API mới dưới `/api/`** (nginx thêm `location /api/`; `/content`, `/run` giữ nguyên, công khai):
   ```text
   POST /api/auth/login     {email,password} → 200 {token, user:{email, roles}} | 401 invalid_credentials | 429
   POST /api/auth/logout    (Bearer) → 204
   GET  /api/me             (Bearer) → {email, roles}
   POST /api/auth/password  (Bearer) {current_password,new_password} → 204 | 400 weak_password | 401
   GET  /api/progress       (Bearer) → {exercises:{id:{passed,drafts{label:code},hints_used{label:int},solution_viewed[label]}}, state:{review:{…}, activity:{"YYYY-MM-DD":n}}}
   PUT  /api/progress/{exercise_id} (Bearer) {drafts,hints_used,solution_viewed} → 204   (KHÔNG nhận passed)
   PUT  /api/progress/state (Bearer) {review, activity} → 204
   POST /run                nếu kèm Bearer hợp lệ và judge trả passed → server ghi passed=true
   GET  /api/admin/content  (admin) → {version, content}   (content = đúng shape content.json, CÓ judge)
   POST /api/admin/validate (admin) {content} → {ok, errors[]}           (chạy thử, không ghi)
   PUT  /api/admin/content  (admin) {base_version, content} → {version} | 409 version_conflict | 422 {errors[]}
   ```
   Không có/hết hạn token → 401; thiếu role admin → 403. Kiểm ở **server**; UI ẩn nút chỉ là phụ.
3. **Tiến độ trên server**:
   - Bảng `user_progress (user_id, exercise_id, passed, drafts jsonb, hints_used jsonb, solution_viewed jsonb, updated_at)`, PK `(user_id, exercise_id)`.
   - `exercise_id` là chuỗi, **không FK tới exercises**, vì `load_content` thay toàn bộ nội dung mà tiến độ phải sống sót qua đó.
   - Bảng `user_state (user_id, review jsonb, activity jsonb)` cho lịch ôn và streak.
   - Giới hạn: drafts ≤ 64KB mỗi bài, chỉ lưu id bài đang có trong nội dung.
4. **App**:
   - **AuthGate** đặt sau ContentGate (`/content` vẫn công khai). Chưa đăng nhập thì hiện màn Login.
   - Đăng nhập xong: tải `/api/progress` rồi mới vào app. Token lưu ở SharedPreferences `auth.token`.
   - Một `http.BaseClient` gắn Bearer dùng chung cho judge, progress và admin. 401 thì về màn Login.
   - **ProgressController / ReviewController / ActivityController** khởi tạo từ snapshot server, không dùng demo seed nữa. Demo seed chỉ còn làm fixture cho test.
   - Mỗi thay đổi đẩy lên server: draft có debounce 800ms; hint, xem lời giải, lịch ôn và activity đẩy ngay. Lỗi mạng thì giữ local và thử lại ở thay đổi kế; ghi giới hạn này.
   - Header Home có nút tài khoản (đổi mật khẩu, đăng xuất). Nút Admin chỉ hiện khi user có role `admin`, cách màn chính 1 chạm.
5. **Nội dung: DB là nguồn chính**:
   - Một đường ghi duy nhất là `load_content` (validate + thay toàn bộ trong 1 transaction).
   - Cả admin PUT và CLI đều đi qua `validate()`. Port thêm luật nội dung đang chỉ có ở test Dart sang Python, trong `app/content_rules.py`:
     - mỗi marker xuất hiện một lần, indent = 4×indent_level;
     - ghép `accepted_answers[0]` vào template == solution (port `mergeCells`);
     - ≤ 3 ô, mỗi đáp án ≤ 2 dòng, đúng 3 hint;
     - không có ô nằm sau `return` trong cùng nhánh;
     - sơ đồ class khớp code (INV-02/03 của run sơ đồ).
   - Lưu: kiểm `base_version`; lệch thì 409, tránh 2 admin ghi đè nhau.
   - `deploy.sh` chạy `load_content --if-empty` (chỉ nạp khi DB chưa có nội dung). Ghi đè có chủ ý thì dùng `--force` bằng tay.
   - Thêm `python -m app.export_content` để xuất DB ra `content.json`. Từ nay sửa nội dung bằng file thì phải export trước, sửa, rồi `--force`; ghi rõ trong README.
6. **Trang quản trị** thay màn mô phỏng:
   - Cây nội dung: theme → module lồng → file → bài.
   - Sửa theme/module/file (tên, mô tả); thêm module/file/bài; xoá bài (có xác nhận).
   - Form sửa bài: các field chính, từng ô, code template/solution, judge cases dạng JSON.
   - Sửa sơ đồ class dạng JSON theo theme.
   - Bấm "Kiểm tra" gọi `validate`, bấm "Lưu" gọi PUT; hiện danh sách lỗi ngay trên form.
   - Không chạy lời giải mẫu trên server (tránh thực thi code ở server); cảnh báo đó là việc của Run.
7. **Seed user** (`app/seed_users.py`, idempotent):
   - Tạo user còn thiếu với mật khẩu ngẫu nhiên. Mật khẩu ghi **append** vào `INITIAL_PASSWORDS_FILE` (VPS: `/etc/smart-coding-study/initial-passwords`, root 600).
   - stdout chỉ in "created N user(s)", **không bao giờ in mật khẩu**. User đã có thì không đổi mật khẩu.

## Sổ bất biến

```text
INV-01 · Hợp đồng API (đường dẫn, JSON, mã lỗi) giữa backend và app khớp nhau cho auth, progress, admin
         phải khớp: backend/app/auth.py · backend/app/progress.py · backend/app/admin_api.py · mobile/lib/data/auth_repository.dart · mobile/lib/data/progress_api.dart · mobile/lib/data/admin_repository.dart
         vỡ thì thấy gì: đăng nhập/lưu/sửa nội dung báo lỗi dù server chạy
INV-02 · Phân quyền ở server: mọi /api/progress*, /api/me, /api/auth/password cần token hợp lệ; mọi /api/admin* cần role admin; không có token hợp lệ thì 401/403
         phải khớp: backend/app/auth.py (current_user, require_admin) · backend/app/progress.py · backend/app/admin_api.py · backend/tests/test_auth.py
         vỡ thì thấy gì: học viên sửa được nội dung, hoặc đọc tiến độ người khác
INV-03 · Mật khẩu chỉ tồn tại dạng hash; mật khẩu ban đầu chỉ ở file root 600; không lọt stdout/log/git/chat/URL; token lưu dạng sha256
         phải khớp: backend/app/seed_users.py · backend/app/auth.py · deploy/deploy.sh · .gitignore
         vỡ thì thấy gì: grep thấy mật khẩu trong log deploy/journal/repo
INV-04 · Tiến độ sống sót qua nạp lại/sửa nội dung: user_progress khoá theo exercise_id chuỗi, không FK cascade; client bỏ qua id không còn trong nội dung
         phải khớp: backend/app/tables.py · backend/migrations/versions/0004_*.py · backend/app/load_content.py · mobile/lib/features/exercise/session_controller.dart
         vỡ thì thấy gì: admin lưu nội dung xong mọi học viên mất tiến độ
INV-05 · passed chỉ do server ghi khi /run trả passed cho user đã đăng nhập; PUT progress không nhận passed; app chỉ coi là xong theo server
         phải khớp: backend/app/main.py (/run) · backend/app/progress.py · mobile/lib/features/exercise/code_tab.dart · mobile/lib/features/exercise/session_controller.dart
         vỡ thì thấy gì: gửi request tay là "xong bài" không cần giải
INV-06 · Một đường ghi nội dung: CLI load và admin PUT cùng qua load_content.validate (+ content_rules) và kiểm version; deploy chỉ nạp khi DB rỗng
         phải khớp: backend/app/load_content.py · backend/app/content_rules.py · backend/app/admin_api.py · deploy/deploy.sh
         vỡ thì thấy gì: admin lưu được bài sai luật (gõ đúng vẫn bị chấm sai); deploy xoá mất nội dung admin vừa sửa
INV-07 · Hành vi cũ: GET /content công khai không đổi shape; /run không token vẫn chấm được; mọi test cũ xanh (test app dựng full app dùng fixture đăng nhập)
         phải khớp: backend/app/content_api.py · backend/app/main.py · mobile/test/support/* · mobile/lib/app/auth_gate.dart
         vỡ thì thấy gì: app chưa đăng nhập không tải được nội dung; test cũ đỏ hàng loạt
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | orchestrator · L4 (auth/schema) · session | users/sessions/user_progress/user_state + migration 0004; auth.py (hash, token, login/logout/me/password, rate limit, current_user/require_admin); main.py gắn router + /run ghi passed; khung progress.py/admin_api.py rỗng | `backend/app/tables.py`, `backend/migrations/versions/0004_users_progress.py`, `backend/app/auth.py`, `backend/app/main.py`, `backend/requirements.txt`, `backend/tests/test_auth.py` | `cd backend && .venv/bin/python -m pytest -q` |
| T-02 | `crew-impl-standard` · T2 · sonnet | progress API (GET/PUT, giới hạn, bỏ id lạ) | `backend/app/progress.py`, `backend/tests/test_progress.py` | `… pytest -q tests/test_progress.py tests/test_auth.py` |
| T-03 | orchestrator · L4 (public API/authz/integrity) · session | content_rules.py (port luật Dart) vào validate; admin_api (GET/validate/PUT + version); export_content; load_content --if-empty/--force | `backend/app/content_rules.py`, `backend/app/admin_api.py`, `backend/app/load_content.py`, `backend/app/export_content.py`, `backend/tests/test_admin_api.py` | `… pytest -q` |
| T-04 | orchestrator · L4 (secrets/deploy) · session | seed_users.py + deploy.sh (if-empty, seed, file mật khẩu) + nginx /api/ + README | `backend/app/seed_users.py`, `backend/tests/test_seed_users.py`, `deploy/deploy.sh`, `deploy/nginx/smart-coding-study.conf`, `deploy/README.md` | `… pytest -q tests/test_seed_users.py && bash -n deploy/deploy.sh` |
| T-05 | `crew-impl-standard` · T2 · sonnet | App auth: AuthRepository + http client Bearer + AuthGate + màn Login + fixture test đăng nhập | `mobile/lib/data/auth_repository.dart`, `mobile/lib/data/api_client.dart`, `mobile/lib/app/auth_gate.dart`, `mobile/lib/features/account/login_screen.dart`, `mobile/lib/main.dart` (+ test mới, sửa test full-app) | `cd mobile && flutter test` |
| T-06 | `crew-impl-standard` · T2 · sonnet | Đồng bộ tiến độ: progress_api + Progress/Review/Activity khởi tạo từ server, đẩy thay đổi; seed → fixture test | `mobile/lib/data/progress_api.dart`, `mobile/lib/features/exercise/session_controller.dart`, `mobile/lib/features/review/review_controller.dart`, `mobile/lib/features/stats/activity.dart`, `mobile/lib/data/demo_seed.dart` (+ test bị ảnh hưởng) | `cd mobile && flutter test` |
| T-07 | `crew-impl-standard` · T2 · sonnet | Admin: repository + controller + màn cây nội dung, sửa theme/module/file, sơ đồ JSON, Kiểm tra/Lưu/409 | `mobile/lib/data/admin_repository.dart`, `mobile/lib/features/admin/admin_controller.dart`, `mobile/lib/features/admin/admin_screen.dart`, `mobile/lib/domain/models.dart` (bỏ PendingContent) (+ test admin) | `cd mobile && flutter test` |
| T-08 | `crew-impl-standard` · T2 · sonnet | Form sửa bài (field, ô, code, judge cases JSON) + thêm/xoá bài | `mobile/lib/features/admin/exercise_editor.dart` (+ test) | `cd mobile && flutter test` |
| T-09 | `crew-impl-light` · T1 · haiku | Header: nút tài khoản (đổi mật khẩu, đăng xuất), nút Admin chỉ cho admin, màn đổi mật khẩu + route | `mobile/lib/features/browse/home_screen.dart`, `mobile/lib/features/account/change_password_screen.dart`, `mobile/lib/app/router.dart` (+ test) | `cd mobile && flutter test` |

**Thứ tự**:
- **Wave 1**: T-01 (tôi), song song với T-05 và T-06. App làm theo hợp đồng API ở mục 2, dùng fake trong test.
- **Wave 2**: T-02, song song với T-03 (tôi), T-07 và T-09.
- **Wave 3**: T-08, song song với T-04 (tôi).
- Commit checkpoint sau mỗi wave, trên main.

**Review**:
- Mỗi task một `crew-review`.
- T-01, T-03, T-04 thêm **external review**, ghi nguyên lệnh trong prompt: `EXTERNAL_AGENT_TIMEOUT=360 "$HOME/.claude/scripts/external-agent.sh" …`.
- Reviewer mối nối kiểm INV-01..07, rồi chạy `verify-seam.sh`, rồi mới push và deploy.

## Verification (e2e — orchestrator tự chạy)

1. `pytest -q`, `flutter test`, `flutter analyze`.
2. **Local** (localhost, dùng tài khoản test seed local — mật khẩu đọc từ file gitignore `backend/.initial-passwords`, không in ra chat):
   - Chrome đăng nhập học viên, gõ draft, Run passed, tải lại trang: tiến độ còn nguyên.
   - Đăng xuất rồi đăng nhập admin: sửa tên một bài và lưu, Home thấy tên mới.
   - Sửa sai luật (đáp án lệch solution) rồi lưu: thấy lỗi 422.
   - **Mối nối cũ**: sau khi admin lưu (nội dung bị thay toàn bộ), tiến độ học viên vẫn còn (INV-04).
3. **VPS** (không đăng nhập hộ):
   - deploy chạy migration 0004 và seed 2 user; log deploy không có mật khẩu.
   - `/api/progress` không token trả 401; `/api/admin/content` không token trả 401.
   - login sai trả 401, sai 6 lần trả 429.
   - `/content` và `/run` vẫn chạy như trước.
   - Bạn tự lấy mật khẩu: `ssh vps sudo cat /etc/smart-coding-study/initial-passwords`.

## Rủi ro / giới hạn (nói rõ với user)

- **HTTP thường**: mật khẩu và token đi không mã hoá. Cần domain + HTTPS sớm.
- Token lưu localStorage (web), lộ nếu dính XSS. App không render HTML người dùng nên rủi ro thấp.
- Rate limit đếm trong RAM, mất khi restart, chỉ đúng với 1 process.
- Đồng bộ tiến độ "mới nhất thắng", không gộp. Mất mạng thì thay đổi chỉ được đẩy ở lần đổi kế tiếp.
- Admin lưu là thay toàn bộ nội dung trong 1 transaction, có kiểm version. Không có lịch sử phiên bản; khôi phục thì dùng export và git.
- Chưa có trang quản lý user (thêm/xoá user, đổi role); user chỉ tạo qua seed.
