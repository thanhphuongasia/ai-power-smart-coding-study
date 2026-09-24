# STATUS — 2026-09-24-pr4-codex-fixes

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-09-24-flutter-demo-core
Branch:   crew/2026-09-24-flutter-demo-core (PR #4 đã mở — push thêm commit)
Issue:    #3 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/3
PR:       #4 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/pull/4
State: done — pushed to PR #4, chờ user merge

| Task | Trạng thái |
|---|---|
| T-01 widgets a11y | done — re-review vòng 2 PASS với Minor (phá 2 chiều đều đỏ đúng 1 test) |
| T-02 cell idle + layout | done — review PASS với Minor (số đo thật sau maxLines header: 251/404/457dp) |
| T-03 code_input placeholder + focus | done — review PASS với Minor (Minor 1 bác bỏ: Container có decoration tự cộng border vào padding, comment đúng) |
| T-04 home continue label | done — review PASS với Minor |

Next action: chờ reviewer mối nối (reviews/SEAM.md) → verify-seam.sh → push vào PR #4 + comment trả lời Codex.
E2E: analyze sạch, 184 test pass, app_flow + cell_idle pass, web build + ảnh Home/Cell OK. Commits: 874cca0 f5180f5 16dc6b1 1d6d039.

## Backlog
- T-04 Minor: chữ "Tiếp tục" lặp giữa SectionLabel và dòng chính (home_screen.dart:71,74)
- T-03 Minor: thiếu test getSize khoá "viền 1↔2px không nhảy khung", thiếu test IME composing rỗng + placeholder
- T-01 Minor: 3 test trùng kiểm InkWell (theme_test.dart:419,454,532); chưa có test maxLines ScreenHeader; breadcrumb 2 dòng có thể cắt mất tên file
- UI Minor (ảnh chụp): khung editor sát mép màn (không có gutter 16px), placeholder cách mép 8px
