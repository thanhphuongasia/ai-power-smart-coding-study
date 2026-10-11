# auth-progress

> Đăng nhập email + mật khẩu, token Bearer, phân quyền learner/admin, và tiến độ học của từng user lưu trên server; backend `/api/*` cho cả hai, app tải/đẩy lại qua `AuthGate` và `ProgressController`.

## Là gì

Trước đây app không biết ai đang dùng: tiến độ (bài đã xong, bản nháp code, gợi ý đã mở, ô đã xem lời giải), lịch ôn và chuỗi ngày học chỉ nằm trong bộ nhớ nên tải lại trang là mất sạch. Module này thêm tài khoản (email + mật khẩu), phiên đăng nhập bằng một token ngẫu nhiên, và lưu tiến độ theo từng user trong Postgres. Mật khẩu chỉ tồn tại dạng băm argon2id (hàm băm cố ý chậm, khó dò ngược), token chỉ tồn tại dạng sha256 trong DB nên lộ bảng phiên cũng không dùng lại được token. Phân quyền kiểm ở server; app chỉ ẩn nút Admin với người không phải admin cho gọn giao diện. Chấm bài vẫn công khai: ai cũng Run được, nhưng chỉ khi đã đăng nhập thì kết quả "passed" mới được server ghi vào tiến độ.

## Dùng khi nào

App gọi khi mở (`AuthGate` đứng sau `ContentGate`, nên `/content` vẫn tải được trước khi đăng nhập), khi gõ code (đẩy draft), khi Run đạt, và khi mở menu tài khoản (đổi mật khẩu, đăng xuất). Developer đụng vào khi thêm API cần đăng nhập (dùng `Depends(current_user)` hoặc `require_admin`), khi đổi hạn chế tiến độ, hoặc khi thêm user (hiện chỉ qua `seed_users`, xem `docs/modules/deploy.md`).

## Cách hoạt động

Bảng API (mọi đường dẫn nằm dưới `/api`, router `backend/app/auth.py:32`, `backend/app/progress.py:25`):

| Endpoint | Cần | Thành công | Lỗi | file:dòng |
| --- | --- | --- | --- | --- |
| `POST /api/auth/login` `{email,password}` | không | 200 `{token, user:{email,roles}}` | 401 `invalid_credentials` · 429 `too_many_attempts` | backend/app/auth.py:222-245 |
| `POST /api/auth/logout` | Bearer | 204 (xoá đúng phiên này) | 401 | backend/app/auth.py:248-252 |
| `GET /api/me` | Bearer | `{email, roles}` | 401 | backend/app/auth.py:255-257 |
| `POST /api/auth/password` `{current_password,new_password}` | Bearer | 204, thu hồi các phiên KHÁC | 401 `wrong_password` · 400 `weak_password` (<10 ký tự) · 429 | backend/app/auth.py:260-281 |
| `GET /api/progress` | Bearer | `{exercises:{id:{passed,drafts,hints_used,solution_viewed}}, state:{review,activity}}` | 401 | backend/app/progress.py:196-216 |
| `PUT /api/progress/{exercise_id}` `{drafts,hints_used,solution_viewed}` | Bearer | 204 | 404 `exercise_not_found` · 422 `unknown_labels` hoặc có field `passed` · 413 | backend/app/progress.py:219-256 |
| `PUT /api/progress/state` `{review,activity}` | Bearer | 204 | 401 · 422 | backend/app/progress.py:179-193 |
| `POST /run` (kèm Bearer tuỳ chọn) | không | như cũ; `passed` + token hợp lệ thì server ghi passed | token sai/hết hạn: chấm như khách, không 401 | backend/app/main.py:131-146 |

Hợp đồng 401/403: không có token, token sai hoặc hết hạn (phiên sống 30 ngày) đều là 401 `not_authenticated` kèm `WWW-Authenticate: Bearer` (backend/app/auth.py:155-165, 35); đã đăng nhập nhưng thiếu role `admin` ở route admin là 403 `admin_required`, role đọc lại từ DB mỗi request (backend/app/auth.py:168-171). Phía app, `ApiClient` thấy 401 cho đúng token đang dùng thì xoá phiên local và `AuthGate` hiện lại màn đăng nhập (mobile/lib/data/api_client.dart:59-75, mobile/lib/app/auth_gate.dart:13-36).

Chống dò mật khẩu (đếm trong RAM): đăng nhập sai quá 5 lần/15 phút theo cặp (IP, email) hoặc quá 30 lần/15 phút theo IP trên mọi email thì 429; đổi mật khẩu sai cũng bị đếm theo (IP, user). Một lượt thử được "giữ chỗ" trước khi verify, trong cùng một lock, để nhiều request song song không cùng lọt qua; đăng nhập đúng thì trả chỗ lại. Email không tồn tại vẫn tốn thời gian verify như email thật (băm sẵn một hash giả) để không lộ email nào có tài khoản.

```python
# token trả cho client MỘT lần; DB chỉ giữ sha256 của nó
def create_session(session: Session, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    session.add(UserSession(token_hash=token_digest(token), user_id=user_id, expires_at=_now() + SESSION_TTL))
    return token
```
(backend/app/auth.py:216-219)

Dữ liệu tiến độ nằm ở hai bảng không thuộc vòng "xoá hết rồi nạp lại" của nội dung:

| Bảng | Khoá | Cột chính | Ghi chú | file:dòng |
| --- | --- | --- | --- | --- |
| `users` | `id`, `email` unique | `password_hash` (argon2id), `roles text[]` ⊆ {learner, admin} | email chuẩn hoá chữ thường | backend/app/tables.py:128-138 |
| `user_sessions` | `id`, `token_hash` unique | `user_id` FK cascade, `expires_at` | chỉ sha256 của token | backend/app/tables.py:141-150 |
| `user_progress` | `(user_id, exercise_id)` | `passed`, `drafts`, `hints_used`, `solution_viewed` (JSONB) | `exercise_id` là chuỗi, KHÔNG FK tới `exercises` | backend/app/tables.py:153-171 |
| `user_state` | `user_id` | `review`, `activity` (JSONB) | lịch ôn + số hoạt động theo ngày | backend/app/tables.py:174-184 |

Hai bất biến của run này (INV-04, INV-05), cách giữ và test:

- **INV-04: tiến độ sống sót qua mọi lần nạp/sửa nội dung.** `exercise_id` không có khoá ngoại nên `load_content` (xoá rồi ghi lại cả nội dung) không đụng được `user_progress`; `GET /api/progress` ẩn các id không còn trong nội dung (backend/app/progress.py:199-210), và app bỏ id lạ cũng như nhãn ô không còn trong bài (mobile/lib/features/exercise/session_controller.dart:97-110, :144-147). Giữ nhãn lạ thì mọi PUT của bài đó bị 422 `unknown_labels` và tiến độ bài đó ngừng đồng bộ trong im lặng.
- **INV-05: `passed` chỉ do server ghi.** Body PUT có `extra="forbid"` và không có field `passed`, câu `ON CONFLICT … DO UPDATE` của PUT không đưa `passed` vào `set_` (backend/app/progress.py:108-111, 243-253); chỉ `record_pass`, do `/run` gọi sau khi máy chấm trả `passed` cho user có token hợp lệ, đặt `passed=true` (backend/app/progress.py:28-44, backend/app/main.py:178-184). App chỉ gọi `markPassed` khi `JudgeStatus.passed` và hiển thị "xong" từ tiến độ nạp từ server.

Phía app: `AuthController` lưu token ở SharedPreferences khoá `auth.token` (mobile/lib/data/auth_repository.dart:61). Đăng nhập xong `AuthGate` tải `/api/progress` rồi mới cho vào app; tải lỗi thì hiện màn "Thử lại / Đăng xuất" thay vì mở app rỗng (mobile/lib/app/auth_gate.dart:26-60). `ProgressController`, `ReviewController`, `ActivityController` khởi tạo từ snapshot đó. Đẩy lên server: draft gom 800 ms mỗi bài; số hint, ô đã xem lời giải, lịch ôn và activity đẩy ngay; lỗi mạng không ném, state local giữ nguyên và lần đổi kế tiếp đẩy lại cả bài (mobile/lib/features/exercise/session_controller.dart:74-86, :186). Header Home có nút tài khoản (đổi mật khẩu, đăng xuất); nút Admin chỉ hiện khi `isAdmin` (mobile/lib/features/browse/home_screen.dart:40-45).

## Ranh giới & đánh đổi

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| Token opaque ngẫu nhiên, lưu sha256 trong bảng phiên | JWT | thu hồi được ngay (đổi mật khẩu, đăng xuất xoá hàng); không cần khoá ký |
| Đếm đăng nhập sai trong RAM | bảng DB / Redis | chỉ 1 process uvicorn; đủ cho quy mô này (backend/app/auth.py:5-7) |
| `exercise_id` chuỗi, không FK | FK cascade tới `exercises` | `load_content` thay toàn bộ nội dung; FK cascade sẽ xoá sạch tiến độ mỗi lần admin lưu |
| PUT không nhận `passed` | client tự khai xong bài | gửi request tay không thể "xong bài" mà không giải (trừ giả kết quả harness, xem Giới hạn) |
| `/run` chấm như khách khi token sai | trả 401 | Run không bị chặn bởi phiên hỏng; đổi lại có lệch local/server (Giới hạn) |
| Tiến độ "mới nhất thắng", không gộp | gộp theo thời gian | một học viên một thiết bị là chính; gộp tốn công cho ít lợi |

Không làm: đăng ký tự do (user chỉ tạo qua `seed_users`), quản lý user (thêm/xoá, đổi role), quên mật khẩu, xếp hạng giữa người học. Mật khẩu mới chỉ cần ≥10 ký tự (backend/app/auth.py:36), không có luật độ phức tạp. Giới hạn kích thước: mỗi bài draft tổng ≤64KB, hint ≤3 mỗi ô, `activity` ≤400 mục khoá `YYYY-MM-DD`, `review` ≤2000 mục / 64KB / sâu ≤32 và cấm ký tự NUL hoặc surrogate lẻ vì Postgres JSONB không lưu được (backend/app/progress.py:62-70, 73-105).

## Giới hạn đã biết

- HTTP thường (chưa domain/HTTPS): mật khẩu và token đi không mã hoá; token lưu localStorage (web) 30 ngày nên lộ nếu dính XSS (deploy/README.md:70-73).
- Rate limit mất khi restart và chỉ đúng với 1 process (backend/app/auth.py:5-7).
- Code học viên có thể in giả dòng kết quả "passed" vì harness chạy cùng tiến trình (xem `docs/modules/judge-backend.md`); tiến độ chỉ ảnh hưởng chính người đó, không xếp hạng.
- "Xong bài" có thể lệch local/server: app đặt passed local mọi khi `/run` trả passed, còn server coi token hết hạn là khách (không ghi) và nuốt lỗi ghi DB; `/run` không bao giờ trả 401 nên app không tự đăng xuất ngay (planning/crew/2026-10-11-users-progress-admin/reviews/SEAM.md, mục 1).
- PUT tiến độ không tuần tự hoá (có thể đến sai thứ tự); không flush draft khi app vào nền; lịch ôn khoá theo `block.id` thành mồ côi khi admin đổi nhãn ô (STATUS.md Backlog).
- Draft sát 64KB bị middleware body chặn 413 `body_too_large` trước nhánh `draft_too_large`; client nuốt lỗi (DEVIATIONS.md).
- Backend: `activity` không có cận trên cho giá trị số; JSONB có thể đổi float lớn thành int; test DB dùng chung nên hai pytest song song đỏ lẻ tẻ.
- Chưa xác minh: luồng UI thật trên Chrome/VPS do reviewer chạy (e2e tự chạy bằng script API 20/20 và widget test).

## Nguồn

backend/app/auth.py:1-281; backend/app/progress.py:1-256; backend/app/tables.py:128-184; backend/migrations/versions/0004_users_progress.py:1-65; backend/app/main.py:131-184; mobile/lib/data/auth_repository.dart; mobile/lib/data/api_client.dart; mobile/lib/data/progress_api.dart; mobile/lib/app/auth_gate.dart; mobile/lib/features/exercise/session_controller.dart; mobile/lib/features/account/; planning/crew/2026-10-11-users-progress-admin/PLAN.md (INV-01..05), reviews/SEAM.md, DEVIATIONS.md, STATUS.md.
