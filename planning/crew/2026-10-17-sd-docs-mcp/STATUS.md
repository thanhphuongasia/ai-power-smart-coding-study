# STATUS — 2026-10-17-sd-docs-mcp

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-17-sd-docs-mcp
Branch:   crew/2026-10-17-sd-docs-mcp
Issue:    #54 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/54

| Task | Tier | Trạng thái |
|---|---|---|
| T-01 migration 0008 + sd/docs.py + admin dùng service | L4 orchestrator | đóng — r2 PASS với Minor; external 2 Major: 1 sửa, 1 bác một phần (DEVIATIONS) |
| T-02 7 tool MCP + body /mcp 2MB | L4 orchestrator | đóng — PASS với Minor (đã sửa); external lần 1 timeout, lần 2: Medium sửa, Low bác |
| T-03 review_queue bỏ archived + test học viên | T2 | đóng — PASS với Minor (Minor 1 sửa ở T-02) |
| T-04 CLI import_file + nginx + README | T1 | đóng — PASS với Minor (F1–F3 sửa) |

Cổng mối nối: SEAM 7/7 CÒN ĐÚNG, verify-seam exit 0.

Next action: PR → merge (CI tự deploy) → kiểm /mcp → backfill markdown gốc 10 doc (dry-run trước, chỉ nhập doc có cards_added=cards_removed=0).

## Bằng chứng

- Full suite: `878 passed, 2 skipped` (commit 0a594dc; 3d8737b chỉ đổi annotation, 69 test MCP xanh).
- E2E uvicorn thật + JWKS giả, DB smart_coding_study_e2e: 14/14 PASS (INV-01..07).
- Mutation bắt: bỏ lưu source_md, bỏ chặn create trùng id, rollback ở dry_run (test_dry_run_and_parser_errors), bỏ bộ lọc archived ở review_queue.
- Audit model: T2 = claude-sonnet-5-5; 4 lượt T1 (impl-light T-04 + 3 external wrapper) = claude-haiku-5-5.

## Backlog

- T-01: NFC trong apply_edits (M-4); base_revision khi doc chưa có (M-5); test downgrade với dòng archived + 2 connection thật (M-3); không có test máy cho populate_existing (DEVIATIONS); SdSection/SdTask đọc không populate_existing (N-1).
- T-02: test 411 chunked cho /mcp.
- T-03: test attempt mồ côi; đối chứng 200 trước archive.
- T-04: test --status sai.
- SEAM: API admin POST có status rõ lên doc archived sẽ khôi phục nó (chưa test khẳng định chủ ý); include_archived mặc định khác nhau (admin True, MCP False).
- Màn admin SD trong app Flutter; xoá cứng (purge) doc archived.
