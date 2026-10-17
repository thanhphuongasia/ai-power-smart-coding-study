# SEAM review — run issue #66

INV-01: CÒN ĐÚNG — mobile/lib/features/system_design/sd_path_screen.dart:192-193 (push `/design/<id>/read?preview=1`) · mobile/lib/app/router.dart:94-100 (đọc `preview` ∈ {1,true}) → reader_screen.dart:76,212,356,472,485 (không _evaluate/_schedule/_send/dispose-PUT)
INV-02: CÒN ĐÚNG — backend/app/sd/learner.py:71 (`unlocked: True`), 185-228 (không còn 409) · mobile/lib/features/system_design/sd_path_screen.dart:61,31-35 + reader_screen.dart:186,415 (chỉ đọc cờ server)
INV-03: CÒN ĐÚNG — backend/app/sd/learner.py:140,175,226 (phase2 = mọi section done, tính lại từ sd_progress) · mobile/lib/features/system_design/sd_path_screen.dart:79-82 (đọc doc.phase2Unlocked)
INV-04: CÒN ĐÚNG — backend/app/sd/learner.py:230-240 (DELETE /api/sd/docs/{doc}/progress, 204, chỉ xoá SdProgress theo user_id+doc_id) · mobile/lib/data/sd_repository.dart:131-138 (DELETE cùng path, chấp nhận 204/200)
INV-05: CÒN ĐÚNG — backend/app/sd/learner.py:61-72 (giữ đủ key, unlocked luôn true) · mobile/lib/domain/sd_models.dart:180,216 (jsonField<bool> 'unlocked' parse được)
INV-06: CÒN ĐÚNG — mobile/lib/features/system_design/sd_path_screen.dart:160-162 (resetProgress rồi invalidate sdDocProvider + sdDocsProvider, bằng container nên kể cả đã rời màn) · mobile/lib/data/sd_repository.dart:224-232 (hai provider gọi GET /docs/{id} và GET /docs, đọc lại từ server)

## Ghi chú
- Đường vào reader khác: task_screen.dart:529-530 (`?section=`) và context_screen.dart:261 vào chế độ thường (có ghi tiến độ) — đúng ý, đó là đọc thật, không phải preview. Reader không có điều hướng ra reader khác nên không có chỗ nào đánh rơi `preview` rồi ghi tiến độ.
- Màn lộ trình vẫn còn toast "Hoàn thành section trước để mở khoá" (sd_path_screen.dart:~276) nhưng chỉ chạy khi node locked theo cờ server; backend mới không bao giờ trả locked cho section nên không hiện (Minor, code chết).
- Preview + backend cũ (section unlocked=false) không nhảy được section khoá: đã bác bỏ ở DEVIATIONS.md, hợp lý vì backend deploy trước app.
- Chạy lại: pytest test_sd_learner + test_sd_progress_reset + test_sd_attempts = 48 passed. Không chạy flutter test.
- Không kiểm được: hành vi thật trên thiết bị / e2e Flutter + uvicorn (không dựng).

Verdict: PASS (6/6 bất biến còn đúng)
