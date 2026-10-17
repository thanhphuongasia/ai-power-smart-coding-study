# SEAM — 2026-10-17-mcp-publish-tool (reviewer mối nối)

Chạy lại: `pytest -q tests/test_mcp_publish.py tests/test_mcp.py tests/test_sd_mcp.py tests/test_review.py` → 230 passed.

INV-01: CÒN ĐÚNG — backend/app/mcp_server.py:557 · backend/app/admin_api.py:169 · backend/app/review.py:487-515 — cả hai đường gọi cùng `review.approve`; MCP chỉ khác ở savepoint từng id và commit cuối lô, không có nhánh logic riêng.
INV-02: CÒN ĐÚNG — backend/app/mcp_server.py:505 · backend/app/review.py:510,521,536 — reviewer=`mcp:<sub>` ghi vào decided_by/decided_at (test_mcp_publish.py:59); app chỉ lấy pending, ContentChange Flutter không đọc decided_by (mobile/lib/data/admin_repository.dart:108-121) nên không vỡ.
INV-03: CÒN ĐÚNG — backend/app/mcp_server.py:508-524 · backend/app/load_content.py:298-300 — mỗi id `begin_nested`, mọi lỗi (NotPending/ReviewError/DataError/OperationalError) rollback savepoint rồi sang id sau; SET LOCAL + advisory xact lock lấy lại ở id kế.
INV-04: CÒN ĐÚNG — backend/app/mcp_server.py:489 (list/get qua _queue_read) · :504 (_decide_many) · :331 (_sd_doc cho sd_publish/unpublish) — cả 6 tool đều gọi `_authorized` trước khi chạm DB.
INV-05: CÒN ĐÚNG — backend/app/review.py:390-396,510 · backend/app/mcp_server.py:526-528 — approve/reject đổi status khỏi pending, rồi `draft_version` tính lại sau lô và trả về làm base; draft = live ⊕ pending nên ghi tiếp không 409 oan.
INV-06: CÒN ĐÚNG — backend/app/mcp_server.py:567-578,385-389 · backend/app/sd/docs.py:295-308 · backend/app/sd/learner.py:43-46,121 — sd_publish_doc/sd_unpublish_doc = `set_status(published|draft)`, cùng hàm với sd_set_status; học viên lọc theo `status=='published'`.
INV-07: CÒN ĐÚNG — backend/app/sd/admin.py:49-52,95-100 · backend/app/mcp_server.py:567-578 · mobile/lib/features/admin/admin_sd_docs_screen.dart:183-185 · mobile/lib/data/admin_repository.dart:284-297 — StatusIn và STATUSES cùng {draft,published,archived}; app gửi published/draft/draft (Publish/Ẩn/Khôi phục) nên không gặp 422; API và MCP đều gọi docs.set_status.

## Mối nối khác

1. Minor — INSTRUCTIONS không nhắc `sd_publish_doc`/`sd_unpublish_doc` và không dặn "chỉ khi người dùng đồng ý" cho SD: backend/app/mcp_server.py:69-73 (đoạn SD vẫn chỉ kể `sd_set_status`; bảo "doc đang published thì học viên thấy NGAY" nhưng không nói publish phải có người dùng đồng ý). Dặn "CHỈ khi người dùng bảo publish" chỉ có cho publish_changes (:63) và trong docstring tool (:567-569). Claude đọc được docstring nên rủi ro thấp; nên thêm một câu vào INSTRUCTIONS.
2. Minor — `sd_set_status` (mcp_server.py:385) vẫn publish được y hệt `sd_publish_doc`, cùng annotation `_UPDATE`; "tool publish riêng" không phải cổng duy nhất. Lớp chặn "Needs approval" hoạt động như nhau ở cả hai nên không vỡ, chỉ là có hai tên cho một việc.
3. Minor — dấu vết hai đường không đồng dạng: app ghi `decided_by=user.email` (admin_api.py:156 → review.py:510) còn MCP ghi `mcp:<sub>` không kèm email (mcp_server.py:505), trong khi `author` của lúc gửi lại có email (mcp_server.py:131). Hiện không chỗ nào hiển thị decided_by nên không vỡ; sẽ khó đọc nếu sau này thêm màn lịch sử duyệt.
4. Ghi nhận — danh sách "Chờ duyệt" trong app tự đúng sau MCP publish: GET /api/admin/changes dùng `pending_rows` (admin_api.py:~148-150, review.py:380) lọc status=pending, và MCP commit ở mcp_server.py:529 nên thay đổi thấy được ngay khi app kéo lại.
