# Deviations — 2026-10-11-exercise-tabs-judge

| Plan nói gì | Thực tế là gì | Quyết định | Ai duyệt |
|---|---|---|---|
| T-05 AC1: test cũ code_input_test xanh không sửa assertion | Seed mới của T-03 (chạy song song) đổi số block split-chunks 5→3, 4 dòng `_splitChunks[2]/[3]` gãy (RangeError) | Orchestrator đổi chỉ số [2]→[0], [3]→[1] (cùng nội dung lời giải `for`/`append`), không đổi assertion | orchestrator (không đổi AC) |
| T-06 owned seed.dart: xoá seedCompletedBlocks | test/seed_test.dart (T-03) còn tham chiếu seedCompletedBlocks, xoá thì gãy compile file ngoài owned | Giữ lại; chuyển việc xoá (seed.dart + seed_test.dart) sang T-10 | orchestrator (không đổi AC) |
| Plan gốc: INV-06/09 phải khớp home_screen/practice_screen nhưng không task nào sở hữu | T-07 báo continue card "Block 1/n" và Practice dùng completed>0 (luôn rỗng nhóm đang làm) — home_screen.dart:69-97, practice_screen.dart:25-28 | Thêm task hẹp T-07b (3 file), cùng mục tiêu, không đổi AC của run | orchestrator — luật "biết từ đầu user có duyệt khác không": không |
| INV-08: một quy tắc khoá cho Row/Screen/Next | Review T-08: Row cho mở bài passed khi bài trước chưa pass, Screen thì khoá (progression.dart:26 chỉ xét bài trước). Review T-08 M2: idle không reset khi đọc đề | Thêm correction T-11 (progression.dart + exercise_screen.dart + 2 test), instance mới | orchestrator (không đổi AC run) |
| T-02 review external (Codex) Critical: monkey-patch json.dumps giả passed | Đúng kỹ thuật nhưng là giới hạn "không chống gian lận" đã khai trong PLAN, user đã duyệt | BÁC — hệ quả chỉ là học viên tự mở khoá bài của mình; ghi lại để reviewer r3 phản biện | orchestrator |
