Worktree: (không dùng — làm thẳng trên main, xem DEVIATIONS)
Branch:   main
Issue:    #21 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/21

# Status: done

| Task | Trạng thái |
|---|---|
| T-01 DB + loader diagram | closed — PASS Minor; external Major (alias from_) ĐÃ SỬA |
| T-02 /content diagram | closed — PASS |
| T-03 Dart model + classScope | closed — PASS Minor |
| T-04 ClassDiagramView + Challenge | closed — PASS Minor |
| T-05 Airline diagram + contract test | closed — vòng 1 CẦN SỬA (2 Major), T-05b sửa, vòng 2 PASS Minor |
| Seam INV-01..05 | CÒN ĐÚNG cả 5; verify-seam exit 0 |

Validation cuối: backend 161 passed / 2 skipped; mobile +334; flutter analyze sạch.
E2E VPS: migration 0003 chạy; /content airline 6 class 6 quan hệ, theme cũ rỗng, không lộ judge, không có "from_"; /run split-chunks + flight-init passed; Chrome (theme tối) Flight.__init__ → Challenge: hộp Flight core/support, highlight 6 thuộc tính + __init__, 5 quan hệ, class khác chỉ hiện method via (e2e/*.jpg).
Model audit: worker/review T2 = claude-sonnet-5-5; external wrapper T1 = claude-haiku-5-5 (Codex gpt-5.6-sol).

## Backlog (Minor)
- loader: class trùng tên gây lỗi nhiễu; via rỗng/trùng, thuộc tính trùng chưa kiểm; quan hệ tự trỏ
- classScope: def nhiều dòng/một dòng → attributes rỗng (0 bài dính); self.x trong comment/string
- view: key quan hệ trùng nếu 2 quan hệ cùng cặp; test highlight chỉ kiểm key; chưa test kiểu dài/dark/375px riêng cho view; classScope chạy mỗi build
- nội dung: Booking/SeatMap→Flight có thể là dependency theo UML chặt (nhãn đã nói rõ); test không kiểm nhãn khớp code

Next action: không có — chờ user dùng thử.
