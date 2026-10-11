Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    #23 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/23

# Status: open (đã qua seam gate, đang commit + deploy)

| Task | Trạng thái | Review |
|---|---|---|
| T-01 auth backend | done | PASS với Minor + external (F1/F5/F6 bác bỏ/chấp nhận, xem DEVIATIONS) |
| T-02 progress API | done | vòng 3 PASS với Minor (T-02b, T-02c) |
| T-03 content rules + admin API | done | 3 vòng CẦN SỬA → sửa sau vòng 3 + test hiệu năng; user chọn đóng không vòng 4 |
| T-04 seed + deploy | done | vòng 2 PASS với Minor + external (2 HIGH đã sửa) |
| T-05 app auth | done | PASS với Minor |
| T-06 progress sync | done | vòng 2 PASS với Minor (T-06b) |
| T-07 admin UI | done | vòng 2 PASS với Minor (T-07b) |
| T-08 exercise editor | done | vòng 2 PASS với Minor (T-08b) |
| T-09 account header | done | vòng 2 code đúng; test xanh sau T-06b (T-09b) |
| SEAM | PASS sau xử lý #2/#3 | verify-seam.sh exit 0 |

Kiểm chứng: backend `pytest -q` 320 passed, 2 skipped · mobile `flutter analyze` sạch, `flutter test` +429 · e2e local (script API, mật khẩu đọc từ file gitignore) 20/20 PASS gồm mối nối INV-04.

## Backlog
- SEC-01: HTTP trần — cần domain + HTTPS trước khi dùng thật.
- Code học viên có thể in giả dòng kết quả "passed" (harness cùng tiến trình) — giới hạn đã biết.
- PUT tiến độ không tuần tự hoá (có thể đến sai thứ tự); state lỡ đẩy chỉ thử lại ở thao tác sau; không flush draft khi app vào nền.
- "Xong bài" có thể lệch local/server khi token hết hạn đúng lúc Run (SEAM #1).
- Lịch ôn theo block id mồ côi khi admin đổi nhãn ô (SEAM #3 phần còn lại).
- Admin: sửa trong lúc reload bị ghi đè; "Tải lại" ở banner 409 không có dialog; editor chỉ cảnh báo 4/12 luật; lý do khi replaceExercise false; field lạ trong challenge.small/project mất khi Áp dụng.
- Backend: activity value không có cận trên; giữ kết nối DB khi đọc body admin; JSONB đổi float lớn → int; test DB dùng chung (2 pytest song song đỏ lẻ tẻ); chưa có test tranh khoá bằng 2 kết nối thật.
- App: client không chặn mật khẩu >256 ký tự; chưa có trang quản lý user.

Next action: commit + push main → deploy → kiểm VPS (không đăng nhập hộ) → comment issue #23 → distill.
