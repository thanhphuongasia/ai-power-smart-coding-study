# SEAM review — oop-bank-progressive

Đã chạy thật: (1) `ssh vps ... python -m app.export_content` (read-only) so với `git show HEAD:backend/content/content.json` → themes + exercises bằng nhau; (2) so 22 bài ngoài bank-* và 4 theme khác giữa HEAD và working tree → y nguyên; (3) SELECT read-only `user_progress` trên VPS; (4) `backend: TEST_DATABASE_URL=...scs_progressive_verify_test pytest -q` → 360 passed, 2 skipped; (5) `flutter test test/content_contract_test.dart` → 23 passed; (6) `validation_errors(content.json)` → []. Không ghi gì lên VPS.

INV-01: CÒN ĐÚNG — backend/app/load_content.py:217 — `validation_errors(content.json) == []`, pytest 360 xanh, Dart content_contract_test (mobile/test/content_contract_test.dart:123-129) xanh; admin Lưu dùng cùng luật server nên không 422 với nội dung này.
INV-02: CÒN ĐÚNG — backend/tests/test_load_content.py:415 — test mới xanh; template bài 1 (backend/content/content.json:4275) và bài 6 (content.json:5061) chỉ có method bài trước + `pass`; reviewer T-01 đã chèn thử lộ và test bắt (trừ lỗ Minor: chỉ so accepted_answers[0]).
INV-03: CÒN ĐÚNG (một phần dựa reviewer T-01) — backend/tests/test_harness.py:40 — test_reference_solution_passes xanh cho 31 bài; 32 mutant do T-01 review chạy đều bị bắt. Tôi không tự chạy lại mutant; chưa kiểm trên Judge0 thật (Python 3.12).
INV-04: CÒN ĐÚNG (phần kiểm được trước nạp) — backend/app/export_content.py:36 — export VPS == HEAD (--force không mất sửa admin lúc này); 22 bài cũ + 4 theme khác y nguyên; 7 id bank-* cũ đều còn (content.json:4275-5631). VPS user_progress: bank-properties (passed, drafts rỗng), bank-balance-setter (solution_viewed A,B,C) → nhãn A/B/C vẫn có trong bài mới, không 422. Phần sau nạp (/content 31 bài) chưa kiểm vì T-02 chưa chạy.
INV-05: CÒN ĐÚNG — backend/tests/test_load_content.py:67 — 31/30/31/31 khớp; mobile/test/content_contract_test.dart:101,129 có bank-init-validate/bank-withdraw-funds và 26 bài method; cả hai suite xanh.

## Mối nối chưa khai
1. Nhãn ô đổi nghĩa/giảm: bank-properties mất ô C (backend/content/content.json:4573, chỉ còn A,B); bank-init A/B/C giờ là ô khác hẳn trước. Thiết bị có draft/hints_used cũ: app đã lọc nhãn lạ (mobile/lib/features/exercise/session_controller.dart:100-110, :146) nên không 422 kẹt đồng bộ; nhưng draft nhãn A/B/C cũ của bank-init, bank-withdraw, bank-deposit… sẽ hiện nhầm vào ô mới cùng nhãn. VPS hiện chỉ có 2 dòng bank-*, drafts rỗng → tác động thực tế gần 0 hôm nay.
2. `passed=true` cũ của bank-properties (VPS user 1) giữ nguyên dù bài đã đổi yêu cầu (judge mới) — không phá, chỉ là tiến độ "đã qua" theo đề cũ.
3. mobile/lib giả định (class_scope.dart:27, merge.dart:28-90): ghép ô theo marker `# TODO X` + indent của marker, lấy attribute từ thân `def` của function_name — không giả định thứ tự bài hay số ô; template mới (marker thụt 12 space ở bank-withdraw) ghép đúng, contract test xanh. Không thấy id bank-* hardcode trong mobile/lib.
4. Test chống lộ chỉ so accepted_answers[0] và bỏ dòng <12 ký tự (Minor, từ review T-01) — lỗ hổng bảo vệ INV-02 về sau.
5. File ngoài scope trong working tree (mobile/ios/*, planning/crew/_index.md) — chỉ liệt kê, không phán xét; DEVIATIONS.md đã ghi.

## Verdict
PASS với Minor — không bất biến nào vỡ. Chặn nạp VPS: không. Lưu ý INV-04 phải kiểm lại sau T-02 (31 bài, template bank-init không chứa `self.__balance -= amount`).
