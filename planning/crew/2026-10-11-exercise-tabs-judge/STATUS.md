# STATUS — 2026-10-11-exercise-tabs-judge

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-exercise-tabs-judge
Branch:   crew/2026-10-11-exercise-tabs-judge
Issue:    #8 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/8

State: open — Wave 2 (T-06 đang chạy; review T-02/T-04 đang chạy)

| Task | Title | State |
|---|---|---|
| T-01 | Harness + dữ liệu test 5 bài | done — gate 0, review PASS với Minor |
| T-02 | CodeRunner + Judge0 + /run | gate 0, e2e 1–6 đạt (Judge0 thật); review + external đang chạy |
| T-03 | Model + merge + seed mới | done — gate 0, review PASS với Minor |
| T-04 | JudgeClient + contract test | gate 0; review đang chạy |
| T-05 | Editor nhiều ô + toolbar chung | done — gate 0, review PASS với Minor |
| T-06 | Progress + khoá bài | dispatched |
| T-07 | ExerciseRow/Stats/Review | todo |
| T-08 | ExerciseScreen + Challenge + Solution | todo |
| T-09 | Tab Code + Run | todo |
| T-10 | Dọn màn cũ + full suite | todo |

Next action: chờ T-06 + review T-02/T-04 → checkpoint 1 → Wave 3 (T-07, T-08).

Backlog (Minor):
- T-01: harness so bằng `==` (True==1); test deepcopy yếu; INV-05 chưa phủ dòng trống/comment đầu code (reviews/T-01.md)
- T-03: ô rỗng không sinh dòng (UI phải chặn — đã đưa vào T-09); không chuẩn hoá \r\n
- T-05: thụt lề thừa code_input.dart:321-337 (cần dart format); notifyListeners trong initState khi ô đã focus (đã đưa vào T-09); thiếu test dispose/đổi toolbar/Tab
