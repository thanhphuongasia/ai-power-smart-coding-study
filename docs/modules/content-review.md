# content-review

> Hàng chờ duyệt nội dung: mọi sửa từ admin editor và MCP chỉ vào bảng `content_changes`; admin xem diff, xem thử đúng màn học viên rồi duyệt hoặc bỏ từng project/module/file/bài. Học viên chỉ đọc bản đã duyệt.

## Là gì

Trước run này, bấm Lưu ở màn Admin hay để Claude ghi qua MCP đều thay luôn nội dung học viên đang xem. Giờ có hai khái niệm tách hẳn: "live" là các bảng nội dung thật (học viên chỉ đọc cái này), còn "draft" là live cộng với mọi thay đổi đang chờ duyệt. Admin editor và MCP làm việc trên draft; học viên không bao giờ thấy draft. Mỗi thay đổi chờ duyệt là một dòng trong bảng `content_changes` ứng với đúng một mục (project, module, file hoặc bài), nên admin duyệt hay bỏ được từng mục riêng. Chỉ có hai đường ghi vào live: duyệt (admin bấm trong app, hoặc MCP `publish_changes`, cùng một hàm `approve`), và CLI `load_content --force`.

## Dùng khi nào

Admin dùng màn "Chờ duyệt (N)" trong app (Home, nút Admin, rồi "Chờ duyệt": 2 chạm). Claude trên claude.ai cũng duyệt được khi người dùng bảo publish: `list_pending_changes`, rồi `publish_changes` hoặc `reject_changes` (xem `docs/modules/mcp.md`); các tool này gọi đúng `review.approve`/`review.reject` mà `POST /api/admin/changes/{id}/approve|reject` gọi, nên luật cha–con và khoá ghi y hệt, chỉ khác `decided_by` = `mcp:<sub> (<email>)`. Mọi thao tác sửa nội dung từ màn Admin (nút giờ là "Gửi duyệt") và mọi tool ghi của MCP tự đi vào hàng chờ, không cần gọi gì thêm. Đụng vào module này khi thêm loại mục mới (thêm vào `KINDS` và `items`/`apply_change`), đổi luật cha–con khi duyệt, hoặc thêm đường ghi nội dung mới (phải đi qua `review.submit`, không gọi thẳng `load_content`).

## Cách hoạt động

Hai khái niệm và đường đi của chúng:

| | live | draft |
| --- | --- | --- |
| Là gì | các bảng nội dung; `content_meta.version` | live + mọi dòng `pending` (`merge_pending`) |
| Ai đọc | học viên (`/content`, `/run`, tiến độ) | `GET /api/admin/content`, MCP đọc/ghi, `/api/admin/run` |
| Ai ghi | `approve`, CLI `load_content --force` | `PUT /api/admin/content`, MCP write tool (qua `submit`) |
| Phiên bản | hash công khai (bỏ `judge`) | `admin_version(draft)`, là `base_version` của PUT |

(backend/app/review.py:1-11, backend/app/review.py:390-396)

Endpoint (router admin, mọi route sau `require_admin`):

| Endpoint | Việc | Mã lỗi | file:dòng |
| --- | --- | --- | --- |
| `GET /api/admin/content` | trả draft, `version` = hash draft, `pending: [{id, kind, item_id, action}]` | | backend/app/admin_api.py:94-98 |
| `PUT /api/admin/content` | validate rồi `submit`: diff với live thành các mục, upsert dòng pending; mục quay về giống live thì xoá dòng pending | 409 `version_conflict`; 422 `{errors}` | backend/app/admin_api.py:118-144 |
| `GET /api/admin/changes` | các dòng pending kèm `before`/`after`, author, thời gian | | backend/app/admin_api.py:147-149 |
| `POST /api/admin/changes/{id}/approve` | áp một mục (kèm mục bắt buộc đi cùng) lên live | 404 `change_not_found`; 409 `item_conflict`; 422 `dependency_missing` / `invalid` | backend/app/admin_api.py:152-174 |
| `POST /api/admin/changes/{id}/reject` | bỏ mục (kèm mục không còn áp được) | 404 | backend/app/admin_api.py:152-174 |
| `POST /api/admin/run` | chấm bài theo judge của draft, KHÔNG gọi `record_pass` | 404 `exercise_not_found` | backend/app/main.py:225-242 |

Mọi lỗi nghiệp vụ của hàng chờ có cùng dạng `{detail: <mã>, message, errors[]}` (backend/app/admin_api.py:~108-114 qua `_review_error`; mã ở backend/app/review.py:51-102). `approve`/`reject` trả thêm `version` mới của draft để editor đang mở không bị 409 giả (backend/app/admin_api.py:152-164).

Bảng `content_changes` (migration 0006): `kind`, `item_id`, `action` (create/update/delete), `before` và `after` (JSONB), `status` (pending/approved/rejected), `author`, `decided_by`, `decided_at`. Partial unique index đảm bảo mỗi mục có tối đa một dòng `pending`; dòng đã duyệt/bỏ giữ làm lịch sử, không có FK tới bảng nội dung vì `load_content` xoá rồi ghi lại toàn bộ (backend/app/tables.py:203-232).

Shape một mục (hàm `items`): project có `fields` (id, name, description, tags, diagram), module có thêm `theme_id`, `parent_id`, file có `module_id`, bài là toàn bộ object bài cộng `placements` (bài nằm ở file nào, thứ tự ra sao). Mọi mục (trừ bài) mang `order`, là thứ tự ĐẦY ĐỦ các anh em trong draft (backend/app/review.py:114-144).

```python
if kind == "exercise":
    return {"fields": item["fields"], "files": sorted(item["placements"])}
return {k: v for k, v in item.items() if k != "order"}
```
(backend/app/review.py:152-154, hàm `_core`: phần dùng để so "mục này có đổi không", cố ý bỏ `order`)

Cách chọn thứ tự, vì sao không dùng "anchor prev":

| | Lưu `order` đầy đủ (đang dùng) | Lưu `prev` (đứng sau ai) |
| --- | --- | --- |
| Áp mục theo thứ tự bất kỳ | ra đúng draft (`_place` xếp các anh em có trong `order`, giữ nguyên anh em chỉ có trên live) | phụ thuộc `prev` đã được duyệt chưa |
| Đổi thứ tự rồi lưu lại | round-trip đúng | không biểu diễn được hết |
| Chèn 1 bài vào đầu file | diff chỉ đánh dấu "đổi chỗ" cho mục thật sự đổi chỗ theo dãy con chung dài nhất (LCS: dãy con dài nhất mà hai danh sách cùng thứ tự), không phải mọi bài phía sau | |

(backend/app/review.py:157-227 cho `_lcs_keep`, `_moved`, `diff`; backend/app/review.py:230-242 cho `_place`)

Duyệt từng mục và ràng buộc cha–con:

| Tình huống | Hành vi | file:dòng |
| --- | --- | --- |
| duyệt con khi cha chưa duyệt (bài trong file mới, file trong module mới) | 422 `dependency_missing` "Cần duyệt X trước" | backend/app/review.py:264-266, 272-343 |
| duyệt project mới | kéo theo module cấp 1 mới của nó (luật "project cần ít nhất 1 module") | backend/app/review.py:464-472 |
| duyệt xoá project/module | kéo theo các mục XOÁ đang chờ của file/module con và bài trong nhánh; còn bài hay con không có mục xoá thì 422 "Còn … bên trong"; bài không bao giờ bị xoá ngầm | backend/app/review.py:473-484, 268-270 |
| mục live hiện tại khác `before` lúc gửi | 409 `item_conflict`, không ghi đè | backend/app/review.py:497-506 |
| áp xong, toàn bộ live mới vi phạm luật nội dung | 422 `invalid` kèm danh sách lỗi | backend/app/review.py:507-509 |
| bỏ (reject) một mục | mục chờ nào không còn áp được vì thiếu nó thì bỏ kèm; project mới mất module mới cuối cùng cũng bỏ kèm | backend/app/review.py:517-539 |
| gửi duyệt chuyển module sang cha khác | 422 `unsupported_move` (chặn đầu vào) | backend/app/review.py:87-95, 411-417 |

`approve` giữ khoá ghi (`lock_content`), khoá dòng pending, so từng mục với `before`, áp, chạy `validation_errors` trên live mới, rồi mới `load_content`. Thứ tự đó chặn việc duyệt một mục đè lên sửa của mục khác (backend/app/review.py:487-514).

Phía app:

| Phần | Việc | file:dòng |
| --- | --- | --- |
| Nút vào | "Chờ duyệt (N)" trên màn Admin, key `admin-review-button`, route `/admin/review` | mobile/lib/features/admin/admin_screen.dart:29-33, mobile/lib/app/router.dart:135 |
| Nhãn "chờ duyệt" | `PendingBadge` trên thẻ project, module, file, bài | mobile/lib/features/admin/admin_widgets.dart:215, mobile/lib/features/admin/admin_screen.dart:75 |
| Màn Duyệt và chi tiết | danh sách mục, diff theo trường trước/sau, nút Approve/Reject | mobile/lib/features/admin/review_screen.dart, mobile/lib/features/admin/review_detail_screen.dart |
| Xem như học viên | `ExercisePreview`: dùng chính `ExerciseScreen` với `ProviderScope` override để tắt khoá bài, tắt đẩy tiến độ, judge gọi `/api/admin/run` | mobile/lib/features/exercise/exercise_screen.dart:51-75, mobile/lib/features/admin/review_detail_screen.dart:325 |

## Ranh giới & đánh đổi

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| Hàng chờ theo MỤC (project/module/file/bài) | duyệt cả bộ nội dung một lần | admin duyệt/bỏ được riêng từng bài; đổi lại phải có luật cha–con |
| `order` đầy đủ của anh em mỗi mục | `prev` anchor | round-trip đúng khi đổi thứ tự, áp theo thứ tự nào cũng ra draft |
| Diff coi "đổi chỗ" theo LCS | so vị trí tuyệt đối | chèn một bài vào đầu file không biến mọi bài sau thành mục chờ |
| Chặn đổi cha module (422 `unsupported_move`), user chọn | hỗ trợ đổi cha | phụ thuộc vòng khi duyệt từng mục (đảo cha–con, kéo module có sẵn vào project mới) chưa an toàn; vòng 3 review vẫn còn Major này |
| Preview dùng lại `ExerciseScreen` + override | màn xem thử riêng | admin thấy đúng cái học viên thấy; không ghi tiến độ vì canPush bị tắt |
| Approve báo lỗi, không tự sửa | tự xoá/tạo mục phụ thuộc | bài không bao giờ bị xoá ngầm theo cha |

Không làm: lịch sử phiên bản nội dung ngoài các dòng approved/rejected, phân trang hàng chờ, chuyển module sang cha khác.

## Giới hạn đã biết

- CLI `load_content --force` đổi thứ tự live trong lúc có mục chờ cùng thùng chứa: mục chờ cũ vẫn mang `before` cũ nên approve trả 409 nếu mục đổi, còn nếu không đổi thì approve áp lại thứ tự của draft. Chấp nhận, thao tác vận hành hiếm, không mất nội dung (planning/crew/2026-10-11-content-review-queue/DEVIATIONS.md).
- Duyệt xoá module có bài đã được admin xoá giờ thành công (trước đó từ chối); hành vi cố ý đổi ở vòng 2 (cùng DEVIATIONS.md).
- Backlog Minor (STATUS.md): `merge_pending` deepcopy mỗi change (O(k·N)); `GET /api/admin/changes` không phân trang; hàng "Vị trí" trên app có thể hiện "trước → sau" giống nhau vì tiêu chí nhạy hơn LCS của backend; thông báo "kèm N mục" không nêu tên.
- Học viên đang mở app chỉ thấy bản mới sau lần refresh của chính họ; approve chỉ refresh provider của admin (planning/crew/2026-10-11-content-review-queue/reviews/SEAM.md).
- Migration 0006 phải chạy trước khi app mới khởi động (admin GET/changes đọc `content_changes`); lần deploy này đã chạy migration trên VPS và smoke prod sạch.
- Lỗi `DataError` ở `submit` (PUT/MCP) không bắt riêng như ở approve; `validation_errors` đã chặn độ dài nên rủi ro thấp, chưa kiểm chứng (SEAM.md).
- Chưa chạy trên trình duyệt thật: e2e dùng 22 bước HTTP trên uvicorn local và widget test bắt đầu từ Home (DEVIATIONS.md).
- Vận hành test: reviewer chạy fuzz trên DB test dùng chung để lại process giữ khoá, làm suite chậm; dùng `TEST_DATABASE_URL` DB riêng và tắt process nền.

## Nguồn

backend/app/review.py:1-571; backend/app/admin_api.py:94-174; backend/app/main.py:225-242; backend/app/tables.py:203-232; backend/migrations/versions/0006_content_changes.py; backend/tests/test_review.py; mobile/lib/features/admin/ (admin_screen.dart, review_screen.dart, review_detail_screen.dart, admin_widgets.dart); mobile/lib/features/exercise/exercise_screen.dart:51-75; mobile/lib/app/router.dart:135; planning/crew/2026-10-11-content-review-queue/PLAN.md (Thiết kế, INV-01..07), STATUS.md, DEVIATIONS.md, reviews/SEAM.md.
