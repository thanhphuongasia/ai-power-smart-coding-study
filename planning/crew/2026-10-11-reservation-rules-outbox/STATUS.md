Worktree: (không dùng — thẳng trên main)
Branch:   main
Issue:    #22 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/22

# Status: done

| Task | Trạng thái |
|---|---|
| T-01 ReservationService | closed — 3 vòng review: CẦN SỬA → CẦN SỬA → PASS Minor (T-01b, T-01c sửa case chấm) |
| T-02 Notifier + Outbox dùng chung | closed — vòng 1 Major ví dụ sai → T-02b → vòng 2 PASS |
| Seam INV-01..05 | CÒN ĐÚNG cả 5; verify-seam exit 0 |

Validation cuối: backend 179 passed / 2 skipped; mobile +334; flutter analyze sạch.
E2E VPS (e2e/run_checks.txt, twitter_outbox_shared.jpg): 6 bài mới /run passed; lời giải sai "huỷ sát giờ" failed; booking-book, like-post passed; reliability/outbox.py ở airline + twitter-feed, Chrome thấy "Dùng ở 2 theme".
Model audit: worker/review T2 = claude-sonnet-5-5.

## Backlog (Minor)
- change_seats: thiếu case new_seats == 0 và now == giờ bay (code khoá)
- harness không có timeout riêng: lời giải `while pending … continue` lặp vô hạn, chỉ dừng nhờ giới hạn runner/Judge0
- notify: dedup theo id chỉ trong bộ nhớ (bài mô phỏng)

Next action: không có — chờ user dùng thử.
