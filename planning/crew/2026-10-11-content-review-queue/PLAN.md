# Run `content-review-queue` — mọi thay đổi nội dung vào hàng chờ, admin duyệt từng mục

## Context

Từ khi có MCP, Claude trên claude.ai (và admin editor) ghi thẳng vào nội dung đang chạy: `PUT /api/admin/content`
và `mcp_server._write` đều `load_content` (xoá + ghi lại toàn bộ). User muốn: **mọi** thay đổi (MCP lẫn admin)
vào hàng chờ; admin **preview đúng màn học viên**, **Approve/Reject theo từng bài**; project/module/file là mục
duyệt riêng; học viên chỉ thấy bản đã duyệt. (Chuyện gộp bài `__init__` tạm gác — user sẽ sửa nội dung qua
luồng duyệt này.)

## Thiết kế — "live" và "draft" là hai khái niệm tách biệt

- **live** = các bảng nội dung hiện có. Chỉ có 2 đường ghi: **approve** và CLI `load_content --force`.
  Học viên (`/content`, `/run`, progress) chỉ đọc live — giữ nguyên code hiện tại.
- **pending** = bảng mới `content_changes`, mỗi dòng là thay đổi của **một mục** so với live:
  `kind (project|module|file|exercise) · item_id · action (create|update|delete) · before JSONB (mục live lúc
  gửi, null nếu create) · after JSONB (null nếu delete) · status (pending|approved|rejected) · author (email
  admin hoặc `mcp:<sub>`) · created/decided_at · decided_by`. Partial unique `(kind,item_id) WHERE pending`.
  Giữ dòng approved/rejected làm lịch sử.
- **draft** = live ⊕ mọi dòng pending. Admin editor và MCP đọc/ghi trên draft (MCP tạo file rồi tạo bài trong
  file đó vẫn được).

**Mục (item) chuẩn hoá** để diff được:
- project = `{id, name, description, tags, diagram, position}`
- module = `{id, name, description, theme_id, parent_id, position}`
- file = `{id, name, module_id, position}`
- exercise = toàn bộ object exercise + `placements: [{file_id, position}]`. Vị trí bài trong file thuộc về bài,
  nên duyệt một bài mới thì bài hiện đúng chỗ.

**Đường ghi:**

| Đường | Hành vi mới |
|---|---|
| `PUT /api/admin/content {base_version, content}` | `validation_errors(content)` → khoá → `base_version` == hash(draft) → diff(live, content) theo mục → upsert pending (mục quay về giống live thì xoá dòng pending). Trả `{version, pending}` |
| MCP write tools | `op(draft)` → validate → cùng hàm "submit" như trên. Câu hướng dẫn "có hiệu lực NGAY" đổi thành "vào hàng chờ duyệt" |
| `POST /api/admin/changes/{id}/approve` | khoá → mục live hiện tại == `before` (lệch → 409 `item_conflict`; create mà id đã có → 409) → áp **một** mục lên live → `validation_errors(live mới)` (lỗi → 422 `{errors}`, vd bài nằm trong file chưa duyệt → "duyệt file X trước") → `load_content` → status approved |
| `POST /api/admin/changes/{id}/reject` | status rejected (draft của mục đó quay về live) |
| `GET /api/admin/content` | trả draft + `version` = hash(draft) + `pending: [{id, kind, item_id, action}]` |
| `GET /api/admin/changes` | danh sách pending kèm `before`/`after`, author, thời gian |
| `POST /api/admin/run {exercise_id, code}` | chấm bằng judge của **draft**, KHÔNG `record_pass` — cho preview |

**App:**
- Editor giữ nguyên thao tác; nút "Lưu" thành "Gửi duyệt"; cây admin có nhãn "chờ duyệt" trên mục pending.
- Màn **Duyệt** mới: vào từ Admin, ≤2 chạm từ Home (admin-button → "Chờ duyệt (N)"). Danh sách mục, mỗi mục có
  Approve/Reject. Chạm vào mục → chi tiết có diff theo trường (trước/sau) và nút "Xem như học viên".
- Preview dùng `ExerciseScreen` thêm chế độ preview: nhận `Exercise` + content draft qua `ProviderScope` override,
  tắt khoá bài, tắt đồng bộ tiến độ, judge = `/api/admin/run`, ẩn nút "bài tiếp".
- Approve lỗi: 409/422 hiện rõ lý do trên màn; lỗi phụ thuộc thì nêu tên mục cần duyệt trước.

## Sổ bất biến

```text
INV-01 · Học viên chỉ thấy live: /content, /run, /api/progress đọc bảng live; không đường nào của học viên đọc content_changes
         phải khớp: backend/app/content_api.py:185 · backend/app/content_api.py:157 · backend/app/progress.py:219 · backend/app/review.py
         vỡ thì thấy gì: bài chưa duyệt hiện cho học viên
INV-02 · Chỉ approve và CLI ghi live: mọi lời gọi load_content( ngoài load_content.py CLI nằm trong approve
         phải khớp: backend/app/admin_api.py · backend/app/mcp_server.py · backend/app/review.py (grep "load_content(")
         vỡ thì thấy gì: admin Lưu / Claude MCP sửa xong học viên thấy ngay
INV-03 · draft = live ⊕ pending; admin GET và MCP read đọc draft; version admin = hash(draft); approve không đổi draft, reject đưa mục về live
         phải khớp: backend/app/review.py · backend/app/admin_api.py · backend/app/mcp_server.py · mobile/lib/features/admin/admin_controller.dart
         vỡ thì thấy gì: Lưu xong editor mất sửa; MCP tạo file rồi tạo bài báo "không có file"; 409 giả
INV-04 · Approve an toàn: khoá + kiểm before == live item + validation_errors(live mới) == [] TRƯỚC khi ghi; lệch → 409, không ghi đè
         phải khớp: backend/app/review.py · backend/app/load_content.py:298 · backend/tests/test_review.py
         vỡ thì thấy gì: approve đè sửa của mục khác / live hỏng luật
INV-05 · Hợp đồng API ↔ app: JSON changes/approve/reject/run và mã lỗi (409 item_conflict, 422 {errors}) parse đúng ở Dart
         phải khớp: backend/app/admin_api.py · mobile/lib/data/admin_repository.dart · mobile/test (MockClient)
         vỡ thì thấy gì: màn Duyệt trống / báo "Lỗi mạng" thay vì lý do thật
INV-06 · Preview không ghi gì của học viên: không PUT /api/progress*, không record_pass, chấm bằng judge draft
         phải khớp: mobile/lib/features/exercise/exercise_screen.dart · backend/app/admin_api.py (/api/admin/run)
         vỡ thì thấy gì: admin preview làm đổi tiến độ của chính mình / chấm theo case cũ
INV-07 · Màn Duyệt vào được ≤2 chạm từ Home; mục pending có nhãn trên cây admin
         phải khớp: mobile/lib/features/browse/home_screen.dart:40 · mobile/lib/features/admin/admin_screen.dart · mobile/lib/app/router.dart
         vỡ thì thấy gì: có hàng chờ nhưng không ai tìm thấy
```

Khái niệm "đang dùng": live (bảng nội dung, `content_meta.version` = hash public của live) và draft (live ⊕ pending,
`admin version` = hash draft). Đây là **hai khái niệm khác nhau**, tên gọi cố định là live/draft; test
`test_review.py` phải đỏ khi admin GET trả live thay vì draft.

## Task (owned PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned | Validation |
|---|---|---|---|---|
| T-01 | orchestrator · L4 (schema + public API) · session | migration 0006 + bảng; `review.py` (chuẩn hoá mục, diff, draft, submit, approve/reject); test pure + DB | `backend/migrations/versions/0006_content_changes.py`, `backend/app/tables.py`, `backend/app/review.py`, `backend/tests/test_review.py` | `cd backend && .venv/bin/python -m pytest -q tests/test_review.py` |
| T-02 | orchestrator · L4 (public API) · session | admin API: GET draft, PUT → pending, changes/approve/reject, `/api/admin/run` | `backend/app/admin_api.py`, `backend/tests/test_admin_api.py`, `backend/app/main.py` (nếu cần cho run) | `pytest -q tests/test_admin_api.py tests/test_review.py` |
| T-03 | `crew-impl-standard` · T2 · sonnet | MCP ghi vào pending, đọc draft, đổi hướng dẫn | `backend/app/mcp_server.py`, `backend/tests/test_mcp.py` | `pytest -q tests/test_mcp.py` |
| T-04 | `crew-impl-standard` · T2 · sonnet | Dart: repository (changes/approve/reject/run), controller (Gửi duyệt, pending badge), nút "Chờ duyệt (N)", route | `mobile/lib/data/admin_repository.dart`, `mobile/lib/features/admin/admin_controller.dart`, `mobile/lib/features/admin/admin_widgets.dart`, `mobile/lib/features/admin/admin_screen.dart`, `mobile/lib/app/router.dart` + test | `cd mobile && flutter test` |
| T-05 | `crew-impl-standard` · T2 · sonnet | màn Duyệt + chi tiết diff + preview học viên | `mobile/lib/features/admin/review_screen.dart` (mới), `mobile/lib/features/admin/review_detail_screen.dart` (mới), `mobile/lib/features/exercise/exercise_screen.dart`, `mobile/lib/features/exercise/code_tab.dart` + test | `cd mobile && flutter test` |

Thứ tự: T-01 → T-02 (orchestrator, L4: crew-review + crew-review-external song song, `EXTERNAL_AGENT_TIMEOUT=360`)
→ checkpoint full pytest → T-03 ∥ T-04 (owned rời nhau) → T-05 → seam reviewer INV-01..07 → `verify-seam.sh`
→ e2e → `git fetch` + main không behind → commit, push, `deploy.sh` (migration 0006) → smoke prod → distill.
Test backend dùng `TEST_DATABASE_URL` DB riêng (DB test chung có thể bị phiên khác nâng migration).

## Verification (e2e — orchestrator tự chạy)

1. Local uvicorn + DB sạch: admin PUT đổi tiêu đề 1 bài → `/content` **không đổi**, `GET /api/admin/changes` có 1
   mục → approve → `/content` đổi. MCP `create_file` + `create_lesson` → 2 mục pending, `/content` không đổi →
   approve bài trước file → 422 "duyệt file trước" → approve file rồi bài → học viên thấy bài đúng chỗ. Reject một
   mục → draft quay về live.
2. Mối nối: sau approve, tiến độ học viên còn nguyên (`/api/progress`), `/run` bài đã duyệt chấm theo case mới.
3. App (Chrome visible): Home → admin → "Chờ duyệt" (2 chạm) → mở mục → "Xem như học viên" → Run (judge draft)
   → không có PUT /api/progress trong network.
4. Prod sau deploy: GET `/api/admin/changes` = `[]`, `/content` vẫn 31 bài; sửa thử 1 tiêu đề qua admin → pending,
   `/content` không đổi → reject.
