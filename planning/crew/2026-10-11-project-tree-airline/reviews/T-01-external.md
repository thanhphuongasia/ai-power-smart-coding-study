# T-01/T-02 external review (Codex, gpt-5.6-sol, EXTERNAL_AGENT_TIMEOUT=360)

Verdict của agent ngoài: CẦN SỬA — 1 Major.
- Major — backend/migrations/versions/0002_module_tree_class.py:31: downgrade drop_column làm mất quan hệ cha–con và class_name.
  Quyết định orchestrator: BÁC BỎ. Lý do: dữ liệu bảng nội dung là bản dẫn xuất của backend/content/content.json, `load_content` thay toàn bộ mỗi lần deploy (deploy.sh chạy alembic upgrade rồi load_content); downgrade→upgrade rồi nạp lại là khôi phục đủ. Đã thêm docstring ghi rõ ở downgrade.
- Không thấy: mismatch model/migration, sai preorder, mất sub-module, lỗi flush/FK, N+1, bảo mật (đánh giá tĩnh — sandbox của agent không kết nối được Postgres).
