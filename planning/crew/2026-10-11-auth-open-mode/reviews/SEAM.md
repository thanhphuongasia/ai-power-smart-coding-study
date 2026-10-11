# SEAM review — auth-open-mode

Đã chạy lại (working tree ổn định): `pytest -q` -> 330 passed, 2 skipped; `flutter analyze` -> No issues; `flutter test` -> All tests passed (434); `bash -n deploy/deploy.sh` ok.
Lưu ý: lần chạy đầu thấy file mobile bị đổi tạm thời (analyze/test đỏ, test_load_content đỏ) do tiến trình khác đang sửa working tree song song; chạy lại sau khi yên thì xanh hết.

INV-01: CÒN ĐÚNG — backend/app/auth.py:164-187 (open_user trả None khi env rỗng/thiếu; current_user raise 401 khi user None) · backend/tests/test_open_mode.py:19-31 + backend/tests/test_auth.py:109 (flag off 401; /me thêm open:false) — tắt cờ thì resolve_user = user_for_token như cũ; app: mobile/lib/data/auth_repository.dart:84 (có token lưu thì đi nhánh cũ) · mobile/lib/data/api_client.dart:68-72
INV-02: CÒN ĐÚNG — backend/app/auth.py:224-225,283-284 (MeOut.open = session_id == 0) · mobile/lib/data/auth_repository.dart:110-121 (_restoreOpen: chỉ vào khi 200 và json['open']==true, token '') và :96-101 (token cũ + open:true -> clearLocal, phiên mở) — hai đầu khớp, AuthGate đi tiếp vì snapshot.token '' == session.token '' (mobile/lib/app/auth_gate.dart:31, mobile/lib/data/progress_api.dart:244-247,255-261)
INV-03: CÒN ĐÚNG — backend/app/progress.py:182,197,223 (Depends(current_user) -> user mở) · backend/app/main.py:147 (lookup_user(token) luôn gọi, resolve_user -> backend/app/auth.py:200-208) — test backend/tests/test_open_mode.py:52 ghi progress + passed cho user mở; app: progress_api.dart:244-247 token '' không null nên vẫn tải/đẩy tiến độ
INV-04: CÒN ĐÚNG — backend/app/auth.py:179-181 (`user_for_token(...) or open_user`, token thật thắng) · mobile/lib/data/api_client.dart:68-72 (không gửi Bearer rỗng; 401 với token rỗng không expire) — test backend/tests/test_open_mode.py:43, mobile/test/open_mode_test.dart:~100-111

## Mối nối chưa khai

1. Minor — `POST /api/auth/password` mở cho người không token ở chế độ mở (backend/app/auth.py:289-307): app ẩn menu nhưng server vẫn nhận, chỉ chặn bằng current_password + throttle theo IP+user. Ai có link có thể dò mật khẩu test@gmail.com (admin) và đổi nó; đổi xong còn xoá mọi phiên thật khác của user (`id != 0`). Không phá demo, nhưng là lỗ so với "UI ẩn nút chỉ là phụ". Sửa nếu muốn: chặn change_password khi user.session_id == OPEN_SESSION_ID (403). Cần orchestrator quyết (security).
2. Minor — AuthGate lỗi tải tiến độ có nút "Đăng xuất" (mobile/lib/app/auth_gate.dart:60-63) vẫn hiện ở chế độ mở. Bấm: logout() không gọi server (không có token lưu), state=null -> LoginScreen, dù server đang mở; người demo không có mật khẩu sẽ kẹt tới khi tải lại trang (restore -> phiên mở lại). Không mất dữ liệu. Nên ẩn nút khi session.open.
3. Minor — mất mạng lúc khởi động: `_restoreOpen` bắt mọi lỗi -> null -> màn đăng nhập (auth_repository.dart:117-119); tải lại là hết. Chấp nhận được.
4. OK — deploy.sh: env ghi tại :64-65, `systemctl restart` tại :98, smoke check :120-123 mong 200 khi có cờ / 401 khi tắt, khớp backend. Email trong DB không có -> smoke 401 -> deploy fail rõ ràng (đúng ý). Giá trị cờ nằm trong ssh command bọc nháy đơn (:39): email có dấu `'` sẽ vỡ, chỉ do operator tự đặt, bỏ qua.
5. OK — logout ở chế độ mở: id=0 không khớp dòng nào, 204 (backend/app/auth.py:276-278).
6. Giới hạn đã khai: ai có link là test@gmail.com (admin), gồm /api/admin/*.

Verdict: PASS với Minor — INV-01..04 còn đúng, không finding chặn; mối nối #1 (đổi mật khẩu không token) cần orchestrator quyết có sửa trước deploy hay không.

## Orchestrator xử lý mối nối chưa khai
- #1 ĐÃ SỬA — backend/app/auth.py (change_password: phiên mở → 403 `open_mode`); test `test_change_password_refused_in_open_mode_keeps_real_sessions` ở backend/tests/test_open_mode.py.
- #2 ĐÃ SỬA (T-02b) — mobile/lib/app/auth_gate.dart (ẩn `progress-logout` khi phiên mở); test ở mobile/test/open_mode_test.dart.
- #3 chấp nhận (tải lại là hết). #4, #5 ghi nhận.
