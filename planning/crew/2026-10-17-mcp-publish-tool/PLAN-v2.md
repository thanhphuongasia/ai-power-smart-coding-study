# PLAN-v2 — thêm UI publish tài liệu SD (PLAN.md vẫn hiệu lực cho T-01)

Lý do: giữa run user yêu cầu "trên UI chưa có button approve, publish, thêm vào luôn".
Khảo sát (main 52da8c8): nút Duyệt/Bỏ bài code ĐÃ CÓ trong app — Admin → "Chờ duyệt (N)" có nút trên từng dòng
(`mobile/lib/features/admin/review_screen.dart`, Key `approve-<id>`/`reject-<id>`) và trong màn chi tiết. Thiếu thật: UI publish
tài liệu System Design (API admin đã có: `GET /api/admin/sd/docs?include_archived=`, `PUT /api/admin/sd/docs/{id}/status`).

## T-02 · L3 · crew-impl-standard · T2 · sonnet — màn "Tài liệu SD" trong Admin
- Owned: `mobile/lib/data/admin_repository.dart`, `mobile/lib/features/admin/admin_sd_docs_screen.dart` (mới), `mobile/lib/features/admin/admin_screen.dart`, `mobile/lib/app/router.dart`, `mobile/test/admin_sd_docs_screen_test.dart` (mới)
- Forbidden: `backend/**`, file mobile khác
- Acceptance: từ màn Admin có nút "Tài liệu SD" (1 chạm) → danh sách doc (kể cả archived) với trạng thái; nút Publish (draft/archived → published), Ẩn (published → draft), Khôi phục (archived → draft); bấm xong tải lại; lỗi hiện thông điệp; học viên không vào được (route nằm trong admin, server vẫn chặn 403).
- Validation: `cd mobile && flutter test test/admin_sd_docs_screen_test.dart test/admin_screen_test.dart && flutter analyze lib`
- Evidence: `git diff --stat -- <owned>`

Bất biến thêm:
INV-07 · Nút publish trong app và tool sd_publish_doc đi cùng một đường (sd/docs.set_status qua API admin / MCP), cùng tập trạng thái {draft,published,archived}
         phải khớp: backend/app/sd/admin.py (StatusIn, put_status) · backend/app/mcp_server.py (sd_publish_doc) · mobile/lib/data/admin_repository.dart
         vỡ thì thấy gì: bấm Publish trong app báo 422, hoặc app hiện trạng thái khác với Claude thấy
