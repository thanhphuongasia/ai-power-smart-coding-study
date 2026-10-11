# STATUS — 2026-10-11-exercise-tabs-judge

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-exercise-tabs-judge
Branch:   crew/2026-10-11-exercise-tabs-judge
Issue:    #8 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/8

State: done (chờ user merge PR) — mọi task đóng, verify-seam exit 0

| Task | Title | State |
|---|---|---|
| T-01 | Harness + dữ liệu test 5 bài | done — gate 0, review PASS với Minor |
| T-02 | CodeRunner + Judge0 + /run | done — r3 PASS với Minor (3 vòng review, 2 vòng sửa) |
| T-03 | Model + merge + seed mới | done — gate 0, review PASS với Minor |
| T-04 | JudgeClient + contract test | done — gate 0, review PASS với Minor |
| T-05 | Editor nhiều ô + toolbar chung | done — gate 0, review PASS với Minor |
| T-06 | Progress + khoá bài | done — gate 0, review PASS với Minor |
| T-07 | ExerciseRow/Stats/Review | done — gate 0, review PASS với Minor |
| T-07b | Home continue card + Practice (task bổ sung) | done — gate 0, review PASS với Minor |
| T-08 | ExerciseScreen + Challenge + Solution | done — gate 0, review PASS với Minor (INV-08 lệch + idle → T-11) |
| T-11 | Correction: một quy tắc khoá + idle khi đọc đề | done — gate 0, review PASS với Minor |
| T-09 | Tab Code + Run | done — gate 0, review PASS với Minor |
| T-10 | Dọn màn cũ + full suite | done — gate 0, review PASS với Minor |

Checkpoint 1 (2026-10-11): backend 38 pass/1 skip; flutter analyze sạch; test T-01..T-06 +207 pass; full suite +228 -10.
Đỏ được phép tới T-07/T-10: review_stats_test (3), browse_screens_test (2), app_flow_test (1), phase2_screens_test (4).
Checkpoint 2 (2026-10-11): flutter analyze sạch; flutter test +260 all passed; backend pytest 55 passed / 1 skipped (live, chạy riêng: pass).
E2E (orchestrator tự chạy, backend thật 127.0.0.1:8000 → Judge0 CE thật):
- backend bước 2–6: 5/5 lời giải passed (~2.5s/lần); thiếu return → failed actual None; syntax → line 4; while True → timeout; network → OSError; URL sai → 503, token không lọt log.
- mối nối bước 7 (widget test tạm, JudgeClient thật, bản lưu ở e2e_real_backend_test.dart.txt): Home→continue-card→3 ô; ô B lỗi cú pháp → "Lỗi ở ô B: '(' was never closed" (INV-05 Python↔Dart); sửa → 6/6 test đạt; Bài tiếp theo → overlap-chunks ô A rỗng (không tái dùng State); Topic: split Đã xong, overlap Mới (INV-06/08).
- Phần "xem Solution → Stats không tính sạch" chỉ phủ bằng widget test T-07 (review_stats_test), chưa chạy e2e.
Next action: user review + merge PR; sau merge dọn worktree (xem git-workflow.md).

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
- T-11: activity() gán state mới mỗi lần chạm → rebuild cả 3 tab (chưa đo giật); activity() rải rác thừa ở solution_tab/code_tab (reviews/T-11.md)
- T-09: passed về sau khi dispose → mất tiến độ; viền lỗi cũ còn sau khi sửa ô; test overflow tap ngoài màn; thiếu test timeout; prompt [n] đánh số lệch Jupyter; go_router pushReplacement có tái dùng State không → kiểm ở e2e bước 7 (reviews/T-09.md)
- e2e simulator: thẻ theme ở Home vẫn ghi 'x/y block' (home_screen.dart theme card) trong khi app giờ gọi là 'ô' — đổi chữ
- SEAM (reviews/SEAM.md): M-1 client không chặn code >8000 (422 hiện 'bận'); M-2 timeout client 20s < worst case server; M-3 rời màn khi đang Run → mất passed; M-4 INV-04 chỉ khoá bằng fixture tay; M-5 nextExerciseAfter vs isExerciseUnlocked khác phạm vi file; M-7 os._exit → 503; M-8 \r lẻ lệch lineOrigin
