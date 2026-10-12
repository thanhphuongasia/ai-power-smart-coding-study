Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-12-issue29-reskin
Branch:   crew/2026-10-12-issue29-reskin
Issue:    #29 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/29

State: wave 3 xong, đã commit; đang review T-03/T-05b/T-06 → reviewer mối nối → e2e
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
T-06: PASS với Minor (đã đóng)
- T-06 Backlog: _HexPainter gloss=ink làm mặt trong khối 3D theme sáng tối hơn; icon surfaceRaised trên node đang làm ~3.1:1 (tối)/2.7:1 (sáng, như cũ); chữ 'Đã xong' success trên nền sáng ~2.9:1; test 'không còn Colors.white/black' bằng contains hờ (lọt Color(0xFFFFFFFF)); _FileHeader (topic_detail_screen.dart:685-704) Text tên file thiếu Flexible/ellipsis → tràn với tên file dài (sẵn có trên main) — làm task riêng
T-05b: PASS với Minor (đã đóng)
- T-05b Backlog: đổi cỡ qua 900 → editor mất focus, tab index bị cắt theo length mới; text solution-warning còn nhắc 'tab Code' ở split (solution_tab.dart:54-55); ExercisePreview (admin) cũng có ☰ ≥700 và drawer điều hướng ra khỏi preview, chưa test; test chưa kiểm biên 699/700, 899/900
T-03: PASS với Minor (đã đóng)
- T-03 Backlog: widgets.dart:3 import features/shell (shared→feature, MNT-02 FAIL Minor); lưới Home đo LayoutBuilder (sau padding) lệch biên với ScreenHeader (MediaQuery): 700–731px đã ☰ nhưng Home 1 cột; caption trắng trên gradient g1/g2 3.1–3.6:1 < 4.5 (theme.dart); bóng nút vô hiệu theme tối 1.23:1, test chỉ kiểm sáng; biên 699/700 ScreenHeader chưa test
