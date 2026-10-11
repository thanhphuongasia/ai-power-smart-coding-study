Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-project-tree-airline
Branch:   crew/2026-10-11-project-tree-airline
Issue:    #16 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/16

# Status: open

Baseline: backend 94 passed / 2 skipped; mobile 294 passed (base feat/cell-gating 475f124).

| Task | Trạng thái |
|---|---|
| T-01 DB + loader | closed — PASS Minor (2 test bổ sung đã làm), external Major bác bỏ (reviews/T-01-external.md) |
| T-02 /content tree | closed — PASS Minor (test thứ tự đã thêm) |
| T-03 harness | closed — PASS Minor (validate case lúc nạp đã thêm ở load_content) |
| T-04 mobile domain | closed — PASS Minor |
| T-05 cell location | closed — PASS Minor |
| T-06 browse screens | closed — PASS Minor |
| T-07 tree walkers | gate 0 (65c1d14) — review đang chạy |
| T-08 airline seed | đang chạy |

Commits: d40533e (wave 1), 4e95476 (T-03/T-05), 72c5f3d (T-06), 65c1d14 (T-07).
Next action: gate T-08 → test _scenario_errors trong test_load_content.py → full test → deploy VPS → e2e → reviewer mối nối → verify-seam → PR.

## Backlog (Minor)
- content_api children không kiểm theme_id (sửa DB tay); `in` trên list O(n²) chưa đo
- harness: test leak class-attr; SystemExit trong steps
- cellLocation: comment `#` thụt ít hơn làm cha; async for/with; header nhiều dòng; self.x từ đáp án ô trước
- browse: sub-module hiện trước file của chính module; card module chưa có tiến độ; test ≥3 tầng/375px
- content_json_test: chưa test bài dùng chung giữa file cha và sub-module
