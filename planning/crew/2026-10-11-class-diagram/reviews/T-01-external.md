# T-01/T-02 external review (Codex gpt-5.6-sol, EXTERNAL_AGENT_TIMEOUT=360)

Lần 1: TIMEOUT 90s (wrapper quên đặt EXTERNAL_AGENT_TIMEOUT) → coi như chưa review, chạy lại.
Lần 2 verdict: CẦN SỬA — 1 Major.
- Major — backend/app/load_content.py:79 + backend/app/content_schema.py:92: schema bật populate_by_name nên nhận cả `from_`, còn loader đọc raw `from` → nội dung viết `from_` qua schema rồi báo lỗi khó hiểu "quan hệ None → …".
  → ĐÃ SỬA: bỏ populate_by_name, hợp đồng chỉ nhận đúng `from`; `from_` bị chặn ở schema với thông báo rõ. Test: test_relation_key_must_be_from_not_from_.
- Không thấy: mismatch migration/model, lỗi alias output, N+1, bảo mật.
