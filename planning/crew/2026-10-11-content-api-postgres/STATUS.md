# STATUS — 2026-10-11-content-api-postgres

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-content-api-postgres
Branch:   crew/2026-10-11-content-api-postgres (stacked trên crew/2026-10-11-exercise-tabs-judge = PR #9)
Issue:    #10 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/10

State: open — mọi task chính đã gate; chờ T-08b, external T-06 → re-review T-06 → e2e simulator → seam

| Task | Title | State |
|---|---|---|
| T-01 | Schema Postgres + Alembic | done — r1 CẦN SỬA (guard DB test) → sửa → r2 PASS với Minor |
| T-02 | content.json + load_content | done — gate 0, review PASS với Minor |
| T-03 | Content index + JSON + provider | done — gate 0, review PASS với Minor |
| T-04 | Exercise readers → provider | done — gate 0, review PASS với Minor |
| T-05 | Browse/stats/review readers → provider | done — gate 0, review PASS với Minor |
| T-06 | GET /content + /run từ DB | gate 0; review r1 PASS+M1 (giữ kết nối khi chấm) → đã sửa; external đang chạy |
| T-07 | ContentRepository + cache | done — gate 0, review PASS với Minor |
| T-08 | ContentGate + main | gate 0; review F1 Major (mất State khi Thử lại) → T-08b |
| T-08b | Correction ContentGate giữ cây widget | dispatched |
| T-09 | Xoá nội dung khỏi seed + test fixture | done — gate 0, review PASS với Minor |

Checkpoint 2: backend 82 passed/2 skipped; mobile analyze sạch, +284 passed; grep seedThemes rỗng.
E2E backend (DB dev smart_coding_study, Judge0 thật): nạp 2 lần cùng version sha256:c22b6dff…; /content 3 theme 5 bài, split-chunks ở 2 file, 0 judge/cases; /run 5/5 passed (~2.5s).
Next action: T-08b + external T-06 → re-review T-06 → e2e simulator (bước 4–6) → reviewer mối nối → verify-seam → P4.

Backlog (Minor):
- T-03: helper jsonField/jsonStrings/jsonObjects public top-level; FormatException không kèm id bài; thiếu test note sai kiểu/id≠key (reviews/T-03.md)
- T-02: validate không kiểm field bắt buộc (KeyError sau delete, an toàn nhờ rollback); thiếu test lỗi sau khi xoá
- T-04/05: CodeTab dựng ô từ widget.exercise ở initState (nội dung đổi khi đang mở bài thì ô cũ); theme/topic id lạ → StateError
- T-06: 7 SELECT không cùng snapshot (cửa sổ hẹp khi nạp lại đúng lúc đọc); /content chưa có response_model
- T-07: ghi cache body rồi version (kill giữa chừng lệch, version chưa ai đọc); 2 load đồng thời
- T-09: matcher test UnimplementedError lỏng; id demo vắng bị bỏ im lặng
