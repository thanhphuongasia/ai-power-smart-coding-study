# STATUS — 2026-10-11-mcp-content

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-11-mcp-content
Branch:   crew/2026-10-11-mcp-content
Issue:    #24 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/24
identity-service: PR #5 — https://github.com/thanhphuongasia/identity-service/pull/5 (branch chore/codewithphuong-mcp-resource)

| Task | Tier | Trạng thái |
|---|---|---|
| T-01 mcp_auth (PRM + JWT + mcp_access) | L4 orchestrator | đóng — r2 PASS với Minor (đã sửa), external 2 Major đã xử lý |
| T-02 content_ops | T2 | đóng — PASS với Minor (Backlog) |
| T-03 mcp_access API + CLI | T2 | đóng — PASS với Minor (Backlog) |
| T-04 /mcp server + tool | L4 orchestrator | chờ re-review r2 (external Major = thiếu test, đã thêm test + mutation) |
| T-05 deploy + README | T1 | đóng — PASS với Minor (1, 2 đã sửa) |
| T-06 identity-service AllowedResources | L1 orchestrator | PR #5 mở, dotnet test 99/99 — chờ user merge + deploy |

Next action: chờ re-review T-04 r2 + reviewer mối nối (SEAM.md) → verify-seam.sh → merge main + deploy app; identity-service cần merge PR #5 + deploy.

## Bằng chứng

- Full suite (commit 12f9085 + 78f0785): `453 passed, 2 skipped`.
- Mutation đã bắt: bỏ validate, open-mode fallback, bỏ verify token, bỏ lock_content, bỏ so version dưới khoá, ContextVar → global.
- E2E uvicorn thật + JWKS giả, DB `smart_coding_study_e2e`: 12/12 PASS (INV-01, 02, 03, 04, 06, 07).

## Backlog

- T-02 m1: key lạ trong module/file/project bị bỏ lặng lẽ (LLM không biết field mất).
- T-02 m2: module/file con lồng sẵn không qua kiểm id toàn cục.
- T-02 m3: update_* không kiểm kiểu giá trị (lỗi pydantic khó đọc hơn).
- T-03 m1: nhánh IntegrityError chưa có test; m2: allow sub đang hiệu lực cho email khác đổi user im lặng; m3: email không giới hạn độ dài; m4: list không phân trang.
- T-04 m4: lock_timeout 15s giữ connection DB khi ghi đồng thời.
- T-05 m3: README chưa nhắc PUBLIC_BASE_URL / IDENTITY_ISSUER khi chạy local.
- Tool xoá; màn quản lý quyền MCP trong app; identity-service khai `scopes_supported: ["expense"]` cứng.
