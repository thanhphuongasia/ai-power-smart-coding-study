Answer: Chưa đạt — có 2 Major, 1 Minor và lỗ hổng test; migration hiện không thấy lỗi up/down thực thi.  
Before vs After: transaction dùng chung có thể bị rollback, revision có thể bị bypass; cần cô lập transaction và refresh dữ liệu dưới lock.  
- **Major — `backend/app/sd/docs.py:131,156-160,205-213,283`:** `dry_run`/lỗi gọi `session.rollback()` toàn phần, xoá cả thay đổi chưa commit của caller. Dùng savepoint hoặc session riêng; caller quản lý commit.  
- **Major — `backend/app/sd/docs.py:101,109,203`:** `session.get()` có thể trả identity-map cũ sau khi đã lấy advisory lock; `base_revision` cũ vẫn pass và ghi đè bản mới. Ép reload/populate-existing dưới lock; thêm test hai Session.  
- **Minor — `backend/app/sd/docs.py:254-258`:** `get_doc` đọc doc rồi sections/tasks bằng các statement riêng, nên import commit xen giữa trả markdown cũ kèm outline mới. Đọc trong snapshot nhất quán hoặc cùng doc lock.  
- **Minor (test) — `backend/tests/test_sd_docs.py:65-86,143-147`; `test_sd_schema.py:14-20`:** tests không có pending caller work/concurrent sessions và không chạy downgrade, nên các lỗi trên vẫn xanh. Thêm các case đó.  
Example: advisory lock lồng nhau cùng transaction an toàn; upsert archived không tự publish, và benchmark `apply_edits` 1MB/50×20k ~0,02s.
