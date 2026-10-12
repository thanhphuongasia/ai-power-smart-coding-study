Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-12-issue29-reskin
Branch:   crew/2026-10-12-issue29-reskin
Issue:    #29 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/29

State: P4 xong — T-01..T-07 đóng, verify-seam OK (vòng 2), 567 test xanh, analyze sạch. PR mở, chờ user merge.
Next action: user xem bằng mắt web 3 bề rộng + merge; PR #26 (màn Soạn bài tập) merge cùng: chỉ trùng planning/crew/_index.md (giữ cả hai dòng)

Backlog (Minor, không sửa trong run):
- Chưa xem bằng mắt: Nunito variable thật, bóng nút, drawer animation, ghost text/IME trên thiết bị
- Tương phản: chữ trắng trên primary sáng 3.58:1; caption trắng trên gradient g1/g2 3.1–3.6:1; bóng nút vô hiệu theme tối 1.23:1; chữ 'Đã xong' success trên nền sáng ~2.9:1 (< AA 4.5)
- INV-08 còn lệch ngoài sổ: challenge_tab example-box (:182-198) và review_screen _CodeBox (:298-312) nền theo theme; code_cell.dart của PR #26 cũng vậy
- ☰: widgets.dart:3 shared→features/shell import ngược lớp; lưới Home đo LayoutBuilder lệch biên 700–731px so với ScreenHeader; ExercisePreview (admin) có ☰ mở drawer ra ngoài preview; drawer vẫn mở khi co <700; biên 699/700, 899/900 chưa test đủ
- Màn luyện: đổi cỡ qua 900 mất focus + kết quả Run; solution-warning nhắc 'tab Code' ở split
- code_input/code_tab: ghost bị ẩn khi IME composing (Android); chip bước khoá test hờ; _CollapsedCell không codeSurface
- topic_detail: _FileHeader (:685-704) tên file thiếu Flexible → tràn ≤412px (sẵn có trên main)
- Dọn: 3 file IBMPlexSans-*.ttf còn trong assets; docs ARCHITECTURE.md:322, DECISIONS.md:90 còn nhắc IBM Plex (distill); Nunito chỉ có bản variable
- Không làm (theo plan): lưu lựa chọn sáng/tối, màn Cài đặt, vẽ lại lộ trình, nút micro
