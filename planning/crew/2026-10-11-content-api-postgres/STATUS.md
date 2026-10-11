# STATUS — 2026-10-11-content-api-postgres

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-content-api-postgres
Branch:   crew/2026-10-11-content-api-postgres (stacked trên crew/2026-10-11-exercise-tabs-judge = PR #9)
Issue:    #10 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/10

State: open — Wave 2 (T-02, T-04, T-05 dispatched; review T-01 (+external), T-03)

| Task | Title | State |
|---|---|---|
| T-01 | Schema Postgres + Alembic | gate 0 (58 pass); review + external đang chạy |
| T-02 | content.json + load_content | dispatched |
| T-03 | Content index + JSON + provider | done — gate 0, review PASS với Minor |
| T-04 | Exercise readers → provider | dispatched |
| T-05 | Browse/stats/review readers → provider | dispatched |
| T-06 | GET /content + /run từ DB | todo (orchestrator) |
| T-07 | ContentRepository + cache | todo |
| T-08 | ContentGate + main | todo |
| T-09 | Xoá nội dung khỏi seed + test fixture | todo |

Next action: chờ wave 2 + review → checkpoint 1 → T-06 (tôi) · T-07.

Backlog (Minor):
- T-03: helper jsonField/jsonStrings/jsonObjects public top-level; FormatException không kèm id bài; thiếu test note sai kiểu/id≠key (reviews/T-03.md)
