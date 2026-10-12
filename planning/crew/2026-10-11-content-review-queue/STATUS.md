Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    (không tạo)

# Status: done

| Task | Trạng thái |
|---|---|
| T-01/T-02 backend (orchestrator, L4) | vòng 1 CẦN SỬA → sửa; vòng 2 CẦN SỬA (M1 xoá project có sơ đồ kẹt) + external timeout → sửa (kéo kèm mục xoá bài; reject kèm project mới mất module) → vòng 3 (cuối) còn Major (đổi cha module) → user chọn chặn đầu vào (422 unsupported_move) → done |
| T-03 MCP → pending | PASS với Minor (+ test file mới + bài) |
| T-04 Dart repo/controller | vòng 2 PASS với Minor |
| T-05a preview | vòng 2 PASS với Minor |
| T-05b màn Duyệt + route | vòng 2 PASS với Minor |

Kiểm: backend 623 passed, 2 skipped (DB scs_progressive_verify_test) · flutter 491 passed · analyze sạch.

## Backlog (Minor)
- T-03: docstring 5/8 write tool chưa nhắc "hàng chờ"; thiếu test update_* trên mục live.
- T-01: merge_pending deepcopy mỗi change O(k·N); /api/admin/changes không phân trang; MNT-03 if/elif theo kind; CLI --force đổi thứ tự rồi approve áp lại thứ tự draft.
- T-04: moduleCard dùng ref.read thay vì nhận state.
- T-05a: containerOf(listen:false).
- T-05b: hàng "Vị trí" có thể hiện "trước → sau" giống nhau (tiêu chí nhạy hơn LCS backend); SnackBar "kèm N mục" không nêu tên.

Gate: verify-seam exit 0 (SEAM: 7/7 CÒN ĐÚNG) · e2e HTTP local 22/22 PASS · backend 626 passed, 2 skipped · flutter 491 passed.
Commit b702b91 (main, đã push) · deploy: migration 0006 chạy trên VPS · smoke prod: /content 31 bài, hàng chờ rỗng; PUT sửa tiêu đề → 1 mục chờ, học viên không thấy; reject → rỗng.

Next action: không còn — distill đã dispatch.
