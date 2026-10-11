# SEAM review — run 2026-10-11-python-oop-bank

Đã chạy thật: `pytest -q` (backend) = 352 passed, 2 skipped; `flutter test` (toàn bộ mobile) = 452 passed; `content_rule_errors(content.json)` = `[]`; export DB VPS (read-only) so với `git show HEAD:backend/content/content.json`.

INV-01: CÒN ĐÚNG — backend/app/content_rules.py:274 (content_rule_errors → []) · mobile/test/content_contract_test.dart:100-106,127 (7 id mới + 24 bài method, test xanh) — luật server trả rỗng cho 29 bài; Dart contract test xanh trên cùng file content.json.
INV-02: CÒN ĐÚNG — backend/content/content.json (exercises.bank-*.judge.cases, 4-7 case, có nhánh lỗi/biên) · backend/app/harness.py:131 — test_harness.py chạy lời giải của cả 29 bài qua harness thật: passed. Tôi tự chạy mutation (đổi toán tử, thông báo, hằng số, bỏ @property/raise) chỉ trong thân method đích của từng bài bank-*: 0 mutant sống sót.
INV-03: CÒN ĐÚNG — backend/app/export_content.py:36 · backend/app/load_content.py:398 — export DB VPS == HEAD content.json byte-semantic (so dict bằng nhau: 22 bài, mọi theme và bài bằng nhau, version "source"). File mới: 22 bài cũ và 4 theme cũ không đổi nội dung (so từng bài/theme), chỉ thêm theme python-fundamentals ở cuối + 7 bài. `--force` không mất sửa của admin tính đến lúc export. Rủi ro còn lại: admin sửa SAU lần export này, trước lúc nạp — nên export + so lại ngay trước khi nạp.
INV-04: CÒN ĐÚNG — backend/tests/test_load_content.py:66-67,280,329-330,397 (5 theme / 29 bài / 28 sau khi xoá) · mobile/test/content_contract_test.dart:100-106,127 (24 bài method, đếm thực tế 24 class_name) — các số khớp nội dung thật, cả hai suite xanh.

## Mối nối chưa khai

1. Sơ đồ/tô sáng class (mobile/lib/domain/class_scope.dart:41 `indexWhere(defRe)`): bài `bank-balance-setter` có hai `def balance(` (getter rồi setter, template dòng `@property`/`@balance.setter`); `indexWhere` lấy cái ĐẦU = getter, nên attribute tô sáng lấy từ thân getter, không phải setter. Hiện cả hai chỉ chạm `__balance` nên kết quả hiển thị không sai. Minor, không chặn.
2. harness.py:131 đổi `callable` → `hasattr`, áp cho cả 22 bài cũ: bài cũ đều `def` method thật nên kết quả như cũ (test_harness xanh cho cả 22). Chỉ khác ở chỗ học viên gán non-callable trùng tên (vd `deposit = 5`) — trước báo "Không tìm thấy method", giờ rơi xuống lỗi runtime lúc gọi ("not callable"). Thông điệp kém rõ hơn, không sai kết quả chấm. Minor.
3. Bộ chuẩn hoá ô (content_rules.py:24-72 vs Dart): đã được INV-01 phủ (đáp án có cả dấu nháy đơn/đôi, khoảng trắng); luật đã báo [] nên không phát hiện lệch.
4. Tiến độ/open-mode: progress.py:226 chỉ kiểm bài tồn tại trong DB và nhãn ô; id bank-* sau khi nạp là bài hợp lệ, không có danh sách id cứng nào ngoài hai test đã sửa. Không phát hiện vấn đề.
5. Không kiểm được: chạy app thật trên web/device (mục Verification 3), và `/content` sau nạp trên VPS (T-02 chưa chạy). Ngoài phạm vi seam: diff mobile/ios/* và planning/crew/_index.md không thuộc task này (scope khác, chỉ liệt kê).

Verdict: PASS với Minor (2 Minor, không chặn commit/nạp; trước `--force` nên export VPS lại và so một lần nữa)
