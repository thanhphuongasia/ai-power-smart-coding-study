Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    (không tạo)

# Status: open

| Task | Trạng thái |
|---|---|
| T-01 soạn theme + 7 bài (crew-impl-standard) | done — review PASS sau sửa 1 Major (reviews/T-01.md); seam PASS với Minor (reviews/SEAM.md), verify-seam exit 0 |
| T-02 nạp VPS (orchestrator) | chưa chạy |

Kiểm: pytest 353 passed, 2 skipped · flutter test 452 passed · validation_errors = [].

## Backlog (Minor)

- accepted_answers: thêm biến thể hay gặp (vd `self.balance` thay `self.__balance` ở vài ô).
- mobile/lib/domain/class_scope.dart:41 lấy `def balance(` đầu tiên (getter) cho bài setter — hiện không sai hiển thị.
- harness.py: thành viên non-callable trùng tên giờ báo lỗi runtime "not callable" thay vì "Không tìm thấy method".

Next action: T-02 — export DB VPS, so với HEAD content.json cũ → deploy.sh → load_content --force → kiểm /content 5 theme, 29 bài.
