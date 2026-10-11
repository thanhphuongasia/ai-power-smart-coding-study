# STATUS — 2026-10-11-exercise-tabs-judge

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-exercise-tabs-judge
Branch:   crew/2026-10-11-exercise-tabs-judge
Issue:    #8 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/8

State: open — Wave 3/4: T-07b, T-09 đang chạy; review T-07, T-08 đang chạy

| Task | Title | State |
|---|---|---|
| T-01 | Harness + dữ liệu test 5 bài | done — gate 0, review PASS với Minor |
| T-02 | CodeRunner + Judge0 + /run | done — r1 CẦN SỬA → sửa → r2 PASS với Minor; external lần 2 đang chạy |
| T-03 | Model + merge + seed mới | done — gate 0, review PASS với Minor |
| T-04 | JudgeClient + contract test | done — gate 0, review PASS với Minor |
| T-05 | Editor nhiều ô + toolbar chung | done — gate 0, review PASS với Minor |
| T-06 | Progress + khoá bài | done — gate 0, review PASS với Minor |
| T-07 | ExerciseRow/Stats/Review | gate 0; review đang chạy |
| T-07b | Home continue card + Practice (task bổ sung) | dispatched |
| T-08 | ExerciseScreen + Challenge + Solution | gate 0; review đang chạy |
| T-09 | Tab Code + Run | dispatched |
| T-10 | Dọn màn cũ + full suite | todo |

Checkpoint 1 (2026-10-11): backend 38 pass/1 skip; flutter analyze sạch; test T-01..T-06 +207 pass; full suite +228 -10.
Đỏ được phép tới T-07/T-10: review_stats_test (3), browse_screens_test (2), app_flow_test (1), phase2_screens_test (4).
Next action: chờ T-07b, T-09, review T-07/T-08, external T-02 → T-10 → checkpoint 2 → e2e mối nối + reviewer mối nối.

Backlog (Minor):
- T-01: harness so bằng `==` (True==1); test deepcopy yếu; INV-05 chưa phủ dòng trống/comment đầu code (reviews/T-01.md)
- T-03: ô rỗng không sinh dòng (UI phải chặn — đã đưa vào T-09); không chuẩn hoá \r\n
- T-05: thụt lề thừa code_input.dart:321-337 (cần dart format); notifyListeners trong initState khi ô đã focus (đã đưa vào T-09); thiếu test dispose/đổi toolbar/Tab
- T-04: message timeout cứng 20s; thiếu test fixture tiếng Việt; duration_ms ép int; 422 gộp vào 'bận' (reviews/T-04.md)
- T-02: JUDGE0_URL không kiểm scheme (token qua http); hàng chờ semaphore không timeout tổng; README thiếu Python tối thiểu (reviews/T-02.md)
- T-06: luồng cũ CellScreen tạm gãy (xoá ở T-10); ExerciseProgress(passed:true) dựng tay → completedBlocks 0 (reviews/T-06.md)
