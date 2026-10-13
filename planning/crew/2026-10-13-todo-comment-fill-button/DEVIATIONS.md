# DEVIATIONS — todo-comment-fill-button

Append-only. Mỗi dòng: plan nói gì · thực tế là gì · quyết định gì · ai duyệt.

- Plan/contract T-01 nói dòng comment hiện `# TODO <nhãn> — <tiêu đề>` · Thực tế: Codex review
  PR #40 chỉ ra trên màn 375px title bị lặp lại (header ngay phía trên đã hiện sẵn title) ·
  Quyết định: bỏ phần `<tiêu đề>`, chỉ còn `# TODO <nhãn>`; sửa `code_tab.dart` +
  `code_tab_test.dart`, 17/17 test vẫn pass · User duyệt qua yêu cầu "fix comment của codex đi".

- PR #40 ban đầu lẫn theo 5 bài RAG (768 dòng, `backend/content/content.json` +
  `backend/tests/test_load_content.py` + `mobile/test/content_contract_test.dart`) không thuộc
  phạm vi run này · Nguyên nhân: branch `ci/deploy-vps-on-merge` (base của PR) có commit RAG
  trên local nhưng chưa push lên origin lúc mở PR, GitHub so sánh với bản origin cũ nên diff
  kéo theo · Quyết định: push `ci/deploy-vps-on-merge` lên origin (fast-forward, không force) để
  đồng bộ base, PR tự gọn lại đúng phạm vi · User chọn qua AskUserQuestion ("Push
  ci/deploy-vps-on-merge lên origin").

- Góp ý UX lớn của Codex (exact-match khoá ô TODO, 23/36 bài bị chia quá nhỏ) · Đây không phải
  bug của run này, là vấn đề kiến trúc/content có sẵn từ trước, đụng `session_controller.dart` +
  cách soạn nội dung hàng chục bài · Quyết định: KHÔNG sửa trong run này, tách issue riêng #42
  (https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/42) để track · User
  chọn qua AskUserQuestion ("Tạo issue riêng để track, không làm ngay").
