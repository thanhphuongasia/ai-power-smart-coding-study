# STATUS — 2026-10-17-sd-courses

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-17-sd-courses
Branch:   crew/2026-10-17-sd-courses
Issue:    #56 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/56

| Task | Tier | Trạng thái |
|---|---|---|
| T-01 migration 0009 + sd/courses.py | L4 orchestrator | đóng — r2 PASS; external Medium (skills falsy) đã sửa |
| T-02 5 tool MCP course | L4 orchestrator | đóng — PASS với Minor (1–2 sửa); external Medium (schema changes) đã sửa |
| T-03 API học viên nhóm course | T2 | đóng — PASS với Minor (Backlog) |
| T-04 Flutter tab Design theo course (+T-04b nới parse) | T2 | đóng — r2 PASS với Minor (code chết đã xoá) |

Cổng mối nối: SEAM 7/7 CÒN ĐÚNG, verify-seam exit 0.

Next action: PR → merge (CI deploy) → curl /api/sd/docs có key `courses`.

## Bằng chứng

- Backend full: `915 passed, 2 skipped`. Flutter full: `+794: All tests passed!`, `flutter analyze lib` sạch.
- E2E uvicorn thật + JWKS giả: 10/10 PASS (INV-01..07).
- Mutation bắt: bỏ chặn gán vào course archived; bỏ course_position khỏi DOC_ORDER.

## Backlog

- T-01: dedupe skill phân biệt hoa/thường; không test đồng thời cho khoá; xoá cứng course để lại course_position; list_courses không phân trang/trần số course.
- T-02: test annotations 5 tool, include_archived, skills sai kiểu ở tầng tool.
- T-03: test course_position NULL, trùng position; test khoá số truy vấn; hai chỗ sort lặp key.
- T-04: thứ tự nhóm theo lần xuất hiện (không theo courses[]); header thiếu Semantics; withCourse liệt kê tay field.
- Course cho themes (bảng nối không FK); API admin + màn quản lý course trong app.
