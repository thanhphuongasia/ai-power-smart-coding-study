**Answer**: Không có finding thực sự trong phạm vi đã chỉ định.

**Before vs After**: Savepoint bao bọc toàn bộ `approve`/`reject`; rollback hoàn tác delete/rewrite content và session vẫn dùng được cho ID kế tiếp. Authorization có mặt trước thao tác, annotation phân biệt read/write đúng.
