# T-01 external review (vendor=codex, model=gpt-5.6-terra, timeout=540s)

**Answer:** Có 1 finding.

- `backend/app/sd/learner.py:234-239` — **Major**. Bằng chứng: `select(SdProgress.section_id)...` chỉ lock các section đã có progress; PUT cho section chưa có row không bị lock rồi có thể insert sau DELETE. Cách sửa: lấy và `sorted` toàn bộ `SdSection.id` của doc để lock trước DELETE, không lấy từ `SdProgress`.
- Before vs After: hiện tại reset có thể trả 204 nhưng progress mới vẫn tồn tại; lock mọi section thực của doc sẽ tuần tự hoá DELETE với mọi PUT hợp lệ.
- (b) sorted lock hiện tại tránh deadlock giữa các DELETE trên cùng tập row; (c) `unlocked` vẫn trả về nên tương thích; (d) DELETE lọc đúng `user_id` + `doc_id`, không đụng `SdAttempt`.
