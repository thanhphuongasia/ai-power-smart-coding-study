# STATUS — 2026-10-11-exercise-tabs-judge

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-exercise-tabs-judge
Branch:   crew/2026-10-11-exercise-tabs-judge
Issue:    #8 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/8

State: open — Wave 3/4: T-07b, T-09 đang chạy; review T-07, T-08 đang chạy

| Task | Title | State |
|---|---|---|
| T-01 | Harness + dữ liệu test 5 bài | done — gate 0, review PASS với Minor |
| T-02 | CodeRunner + Judge0 + /run | external Codex: 1 Critical (bác — giới hạn đã khai) + 3 Major → vòng sửa 2 (body 413, whitelist status, fail-fast CODE_RUNNER), 54 pass + live pass; re-review r3 (cuối) đang chạy |
| T-03 | Model + merge + seed mới | done — gate 0, review PASS với Minor |
| T-04 | JudgeClient + contract test | done — gate 0, review PASS với Minor |
| T-05 | Editor nhiều ô + toolbar chung | done — gate 0, review PASS với Minor |
| T-06 | Progress + khoá bài | done — gate 0, review PASS với Minor |
| T-07 | ExerciseRow/Stats/Review | done — gate 0, review PASS với Minor |
| T-07b | Home continue card + Practice (task bổ sung) | done — gate 0, review PASS với Minor |
| T-08 | ExerciseScreen + Challenge + Solution | done — gate 0, review PASS với Minor (INV-08 lệch + idle → T-11) |
| T-11 | Correction: một quy tắc khoá + idle khi đọc đề | xong phần mình; chờ T-09 để gate (4 test cũ đỏ do code_tab.dart đang dở) |
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
- T-07: ô đã xem lời giải bị kéo hạn ôn về ngày mai vĩnh viễn → ôn mỗi ngày mãi (reviews/T-07.md) — HỎI USER có muốn vậy không
- T-07b: 'ô đã viết' đếm cả draft nhãn lạ; Practice xếp bài khoá có draft vào Đang dở
- T-08: acceptedAnswers.first không guard rỗng (solution_tab.dart:124); test idle/timeout màn mới thiếu (T-10 port)
