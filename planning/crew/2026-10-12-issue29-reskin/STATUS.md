Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-12-issue29-reskin
Branch:   crew/2026-10-12-issue29-reskin
Issue:    #29 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/29

State: wave 1 xong (T-01, T-04 verify OK, đã commit). Đang review T-01/T-04 → wave 2
Next action: verify-task T-01/T-04 → review → checkpoint → wave 2 (T-02, T-05a)

T-01: PASS với Minor · T-04: PASS với Minor (đã đóng)
Backlog (Minor):
- T-01: bóng nút vô hiệu theme sáng trùng nền (giao T-03 sửa); chữ trắng trên primary sáng 3.58:1 < AA 4.5 (khớp mockup, cần user quyết); test GhostButton/HintButton tap/vô hiệu còn hờ; 3 file IBMPlexSans-*.ttf còn trong assets; docs/ARCHITECTURE.md:322, DECISIONS.md:90 còn nhắc IBM Plex (distill)
- T-04: chip ghost-accept nhãn rỗng (giao T-05a sửa); ghost ẩn khi IME composing trên Android (chưa kiểm máy thật); test thiếu composing/selection/đáp án nhiều dòng sau dòng 1
- T-06 Backlog: Topic detail tràn ngang ≤412px sẵn có (kiểm trên main); chưa xác nhận là lỗi thật trên thiết bị hay chỉ do font Ahem trong test
T-02: PASS với Minor (+T-02b đã sửa nút theme trùng) · T-05a: PASS với Minor (đã đóng)
Backlog:
- T-02: drawer vẫn mở nếu co cửa sổ xuống <700 (barrier/back đóng được); bài chồng stack khi mở từ drawer; key drawer-exercise-<id> trùng khi bài thuộc nhiều topic
- T-05a: test chip bước khoá còn hờ (bỏ guard `unlocked` test không đỏ); _CollapsedCell không dùng codeSurface (hàng danh sách, không tính FAIL INV-08)
