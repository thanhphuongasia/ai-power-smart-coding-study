# content-admin

> Nội dung học nằm trong Postgres là nguồn chính; admin sửa qua `/api/admin/*` hoặc CLI, mọi đường ghi đi qua đúng một hàm `load_content` với một bộ luật chung; app có màn Admin (cây nội dung + form sửa bài).

## Là gì

Trước run này, `content.json` là nguồn thật và mỗi lần deploy thay toàn bộ DB bằng file đó, nên sửa trong DB sẽ bị ghi đè. Giờ ngược lại: DB là nguồn chính, admin sửa nội dung trong app và bấm Lưu, còn deploy chỉ nạp file khi DB còn rỗng. Để hai đường ghi (CLI và admin) không cho ra dữ liệu khác nhau, cả hai cùng đi qua `load_content`: kiểm bộ luật nội dung, kiểm phiên bản, rồi xoá hết và ghi lại trong một transaction (một lô thao tác DB hoặc xong hết hoặc huỷ hết). Các luật nội dung trước đây chỉ chạy trong test Dart trên `content.json` nay được port sang Python để chạy trên mọi bộ nội dung trước khi ghi. Nhờ vậy admin không thể lưu một bài mà học viên gõ đúng đáp án vẫn bị chấm sai.

## Dùng khi nào

Admin dùng màn Admin trong app (nút chỉ hiện với role admin, nhưng server mới là nơi chặn thật). Developer dùng CLI khi cần sửa nội dung bằng file: `export_content` để lấy bản đang chạy, sửa, rồi `load_content --force`. Deploy gọi `load_content --if-empty` mỗi lần. Đụng vào module này khi thêm luật nội dung mới (sửa `content_rules.py`, cả hai đường ghi hưởng ngay) hoặc thêm trường cho bài.

## Cách hoạt động

API admin (router gắn `Depends(require_admin)` ở cấp router nên route thêm sau không thể quên kiểm quyền, backend/app/admin_api.py:33):

| Endpoint | Việc | Mã trả | file:dòng |
| --- | --- | --- | --- |
| `GET /api/admin/content` | xuất toàn bộ nội dung CÓ `judge` + `version` | 200 `{version, content}` | backend/app/admin_api.py:77-80 |
| `POST /api/admin/validate` `{content}` | chạy đủ luật, không ghi | 200 `{ok, errors[]}`; body sai 422 | backend/app/admin_api.py:83-90 |
| `PUT /api/admin/content` `{base_version, content}` | kiểm luật, kiểm version, thay toàn bộ | 200 `{version}` · 409 `version_conflict` · 422 `{errors[]}` · 413 | backend/app/admin_api.py:93-124 |

Không token là 401, học viên là 403 (xem `docs/modules/auth-progress.md`). Mọi 422 của admin cùng dạng `{errors:[...]}`, tối đa 200 lỗi, để app hiện được trên form (backend/app/admin_api.py:35-61). Body được đọc sau khi qua kiểm quyền, nên khách chưa đăng nhập không bắt server parse tới 4MB (backend/app/admin_api.py:64-66, backend/app/main.py:26-27).

Một đường ghi duy nhất. `_save` kiểm luật TRƯỚC khi giữ khoá (nội dung sai thì không chặn ai), sau đó lấy khoá ghi, so `base_version` với phiên bản hiện tại, rồi gọi `load_content(validated=True)`:

```python
def lock_content(session: Session) -> None:
    session.execute(text(f"SET LOCAL lock_timeout = '{LOCK_TIMEOUT}'"))
    session.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": CONTENT_WRITE_LOCK})
```
(backend/app/load_content.py:298-300)

`pg_advisory_xact_lock` là khoá ứng dụng của Postgres, giữ tới hết transaction; kiểm version và ghi nằm trong cùng một khoá nên hai admin lưu cùng lúc không ghi đè nhau (người đến sau thấy 409), và CLI cũng xếp hàng trên khoá đó. Chờ khoá tối đa 15 giây (backend/app/load_content.py:295). Hai loại phiên bản khác nhau cố ý:

| Phiên bản | Tính trên | Dùng cho | file:dòng |
| --- | --- | --- | --- |
| `version` công khai | sha256 của nội dung bỏ `judge` | `/content`, cache của app | backend/app/load_content.py:46-48 |
| `admin_version` | sha256 của TOÀN BỘ nội dung (gồm `judge`) | `base_version` của PUT / 409 | backend/app/export_content.py:52-55 |

Admin chỉ sửa test case thì `admin_version` đổi còn `version` công khai không đổi, nên mới phát hiện được xung đột.

Bộ luật chung (`validation_errors`, rỗng = hợp lệ): schema pydantic, ký tự Postgres không lưu được (NUL, surrogate lẻ, NaN), trần kích thước, id trùng, shape case chấm, sơ đồ class, rồi `content_rule_errors` (backend/app/load_content.py:217-283, backend/app/content_rules.py:274-310). Luật port từ Dart nằm ở `content_rules.py`:

| Luật | file:dòng |
| --- | --- |
| mỗi ô đúng một dòng `# TODO <nhãn>`, thụt = 4 × `indent_level`, không marker thừa | backend/app/content_rules.py:95-116 |
| id ô = `<id bài>-<nhãn chữ thường>`; nhãn là một chữ in hoa | backend/app/content_rules.py:108-111 |
| ≤3 ô; mỗi đáp án ≤2 dòng; tổng dòng đáp án đầu ≤10; đúng 3 gợi ý; vocab, explanation không rỗng | backend/app/content_rules.py:18-21, 92-93, 118-135 |
| ghép `accepted_answers[0]` của mọi ô vào template phải == `judge.solution` (port `mergeCells`) | backend/app/content_rules.py:38-51, 147 |
| không có ô nằm sau `return` trong cùng nhánh (code chết) | backend/app/content_rules.py:175 |
| `challenge` không rỗng, ví dụ gọi đúng hàm; sơ đồ class khớp code (class, `self.x =`, `def m(`) | backend/app/content_rules.py:181-187, 233-267 |
| id duy nhất toàn cục giữa theme/module/file/bài/ô, ≤100 ký tự (cột `String(100)`); `__init__` cần `class_name`; theme cần ≥1 module | backend/app/content_rules.py:271-307 |

Trần để chặn input xấu (chi phí kiểm là CPU của server dùng chung với `/run`): ≤50 theme, ≤1000 module, ≤1000 bài, ≤200 class mỗi sơ đồ, ≤100 thành viên mỗi class, ≤1000 test case, chuỗi ≤20000 ký tự, danh sách ≤1000 phần tử, đáp án ≤500 ký tự, một `steps`/`call` ≤1000 ký tự, lồng ≤64 tầng, ≤200000 giá trị (backend/app/load_content.py:131-132, 169-214). Body admin ≤4MB, các route khác ≤64KB (backend/app/main.py:30-31).

CLI (backend/app/load_content.py:390-416):

| Lệnh | Hành vi |
| --- | --- |
| `python -m app.load_content --if-empty [path]` | lấy khoá, nếu DB đã có `version` thì in `skip` và thoát 0; deploy dùng cái này |
| `python -m app.load_content --force [path]` | validate rồi thay toàn bộ có chủ ý |
| `python -m app.export_content [path]` | xuất DB ra đúng shape `content.json` (kèm `judge`), mặc định ra stdout |

Quy trình sửa nội dung bằng file: `export_content` → sửa file → `load_content --force`.

Đưa nội dung mới từ repo lên VPS (vì deploy chỉ nạp `--if-empty` nên không tự cập nhật nội dung): (1) export DB của VPS ra file và so với `backend/content/content.json` cũ trong repo, để biết admin đã sửa gì trên VPS mà bản repo chưa có; (2) `deploy.sh` đưa code mới (gồm harness) lên; (3) chạy `load_content --force` trên VPS với `content.json` mới; (4) kiểm `/content` trả đúng số theme/bài. Bỏ bước 1 thì `--force` ghi đè mất chỉnh sửa của admin (run planning/crew/2026-10-11-python-oop-bank/, STATUS.md; chưa có script cho chuỗi này, làm tay). Không có `--if-empty` hay `--force` thì lệnh từ chối chạy (exit 2), nên không còn cách "vô tình ghi đè" (backend/app/load_content.py:398-400).

Màn Admin trong app đi từng tầng (drill-down: chạm một thẻ để xuống tầng sâu hơn, mỗi tầng một màn riêng), thay cho cây phẳng nhiều icon trước đây. Bốn route go_router đều đăng ký ở `mobile/lib/app/router.dart:88-110`, và mỗi tầng được `push` từ tầng trên nên nút back lùi đúng một tầng:

| Tầng | Route | Màn | Hiện gì |
| --- | --- | --- | --- |
| 1 | `/admin` | `AdminScreen` | thẻ project (theme): tên, mô tả, "N module · M bài", nút sơ đồ class (dialog JSON), menu ⋯ "Đổi tên / mô tả"; nút lớn "Thêm project" |
| 2 | `/admin/theme/:themeId` | `AdminThemeScreen` | thẻ module cấp 1 (sub-module đếm gộp), menu ⋯ đổi tên/mô tả, nút "Thêm module" |
| 3 | `/admin/module/:moduleId` | `AdminModuleScreen` | mỗi file là một nhóm (⋯ "Đổi tên"), bài là thẻ nhỏ (tiêu đề, `class.hàm`, số ô), ⋯ trên thẻ bài là "Xoá" (có xác nhận); "Thêm bài" cuối mỗi file, "Thêm file", sub-module là thẻ, "Thêm module con" |
| 4 | `/admin/exercise/:id` | `ExerciseEditorScreen` | form sửa một bài (không đổi so với trước) |

**Breadcrumb**: mỗi màn có một hàng ngắn kiểu "Projects / Airline / Flight"; chạm một mục là quay về cấp đó. `adminGoToLevel` pop đúng số tầng nếu stack đúng là chuỗi đã đi xuống, còn không (mở thẳng URL sâu, refresh web) thì `go` thẳng tới route cấp đó (mobile/lib/features/admin/admin_widgets.dart:117-130).

**Menu ⋯** (`AdminActionMenu` + `AdminMenuEntry`) gom hành động phụ của thẻ vào một nút; thao tác thêm dùng nút lớn `AdminAddButton`. **Hộp thoại thêm bài** có ba ô: Tiêu đề, Tên hàm, Class (tuỳ chọn); tên hàm và class phải là định danh Python (`^[A-Za-z_][A-Za-z0-9_]*$`), tiêu đề rỗng thì không tạo. Bấm Thêm thì tạo bài với template khung đúng hàm/class đó rồi mở thẳng form sửa bài.

**Thanh dưới ghim** `AdminSaveBar` dùng chung cho cả ba tầng: "Đã đồng bộ" hoặc "● Chưa lưu", nút Kiểm tra và Lưu; có lỗi thì hiện chip "N lỗi" chạm mở bottom sheet danh sách lỗi; "Hủy sửa" có hộp xác nhận. 409 hiện `AdminConflictBanner` (tải lại sẽ bỏ thay đổi chưa lưu); 422 đưa lỗi vào chip/sheet. Mọi ghi đi qua controller (`updateNode`, `addTheme`, `addModule`, `addFile`, `addExercise`, `deleteExercise`, ...), không màn nào sửa JSON trực tiếp, nên dirty/409/422 giữ nguyên hành vi cũ.

**Chấm đỏ** trên thẻ bài, module và project lấy từ chuỗi lỗi server (hàm `exerciseIdsWithErrors` đổi chuỗi lỗi thành tập id bài), nhận ba dạng:

| Dạng lỗi server | Ví dụ | Khớp bằng |
| --- | --- | --- |
| `bài <id>: …` | `bài e1: thiếu judge.solution` | `_errorIdPattern` |
| `bài <id> ô <X>: …` | `bài e1 ô A: cần ít nhất 1 đáp án` | `_errorIdPattern` (nhóm `ô <X>` tuỳ chọn) |
| `… (bài <id>)` ở cuối dòng | `theme X: thiếu class C (bài e1)` | `_errorTrailingIdPattern` |

Lỗi không đúng dạng nào (ví dụ pydantic `exercises.<id>.field: msg`, lỗi cấp theme không kèm id bài) bị bỏ qua: chỉ thấy qua chip "N lỗi", không có chấm đỏ.

**Controller**: `addTheme(name, {description})` tạo theme rỗng (sơ đồ `{classes:[],relations:[]}`, `topics: []`), trả id mới hoặc null nếu tên rỗng. `addExercise(fileId, title, {functionName, className})` dựng khung qua `exerciseScaffold`:

```dart
final template = cls == null
    ? 'def $fn():\n    # TODO A'
    : 'class $cls:\n    def $fn(self):\n        # TODO A';
// ... 'indent_level': cls == null ? 1 : 2,
```

Tham số mặc định (`run`, `Draft`) giữ hành vi cho caller cũ. Sau khi Lưu thành công, `AdminController` gọi `contentProvider.notifier.refresh()` để Home thấy tên mới ngay; thiếu bước này admin lưu xong vẫn thấy dữ liệu cũ tới khi tải lại trang.

## Ranh giới & đánh đổi

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| DB là nguồn chính; deploy `--if-empty` | `content.json` là nguồn, deploy ghi đè | admin sửa trực tiếp mà không bị deploy xoá; đổi lại sửa bằng file phải export trước |
| Port luật Dart sang Python, chạy ở server | chỉ test Dart trên `content.json` | admin ghi được bộ nội dung bất kỳ, nên luật phải chạy trên bộ đó |
| Một hàm ghi `load_content` cho CLI và admin | admin có đường ghi riêng | không thể có hai bộ luật lệch nhau; khoá ghi chung |
| `409` theo `admin_version` | ghi đè "người lưu sau thắng" | hai admin không âm thầm xoá việc của nhau |
| Lưu = thay toàn bộ nội dung | cập nhật từng bản ghi | một đường ghi, kiểm cả bộ luật liên bài (id toàn cục, sơ đồ) |
| Server KHÔNG chạy lời giải mẫu khi Lưu | chạy `judge.solution` qua harness | tránh thực thi code ở server admin; việc đó là của nút Run trên máy chấm |
| Server cho module rỗng (không có luật "mỗi module có ≥1 bài") | port nguyên luật Dart | admin xoá bài cuối của module hoặc dựng khung trước sẽ bị chặn; test Dart vẫn giữ luật trên `content.json` (DEVIATIONS.md) |

Sau khi bác bỏ review: bài không thuộc file nào ("bài mồ côi") vẫn hợp lệ, được liệt kê cuối và vẫn Run được, vì test hiện có coi đó là thiết kế được hỗ trợ (DEVIATIONS.md).

Không làm: lịch sử phiên bản (khôi phục dùng `export_content` và git), quản lý user, sửa từng field ở server (luôn gửi cả bộ nội dung), tự động đồng bộ ngược DB sang `content.json`.

## Giới hạn đã biết

- Luật nội dung có hai bản cài (Dart `mergeCells` cho preview/test, Python `content_rules.py` cho server); không có test so trực tiếp hai bản nên có thể trôi dần. Server là nguồn quyết định (backend/app/content_rules.py:8-11).
- Form editor chỉ cảnh báo 4 trong 12 luật; "Tải lại" ở banner 409 không có hộp xác nhận; sửa trong lúc đang tải lại bị ghi đè; field lạ trong `challenge.small/project` mất khi "Áp dụng"; chưa rõ lý do khi `replaceExercise` trả false (STATUS.md Backlog).
- UI drill-down: web luôn mở lại Home khi tải trang nên deep link `/admin/...` chưa dùng được (có từ trước); đếm số bài/lỗi tính lại mỗi lần build, chưa đo; test chưa phân biệt nhánh pop/go của breadcrumb trên stack sâu (planning/crew/2026-10-11-admin-ux-levels/reviews/T-02.md Backlog).
- Admin đổi nhãn ô thì lịch ôn khoá theo `block.id` cũ thành mồ côi (SEAM #3).
- Backend: giữ kết nối DB khi đọc body admin; chưa có test tranh khoá bằng hai kết nối thật; phép kiểm chéo CPU của sơ đồ được đo <1s ở payload xấu nhất bằng test hiệu năng, nhưng run đóng sau 3 vòng review (vòng 3 vẫn CẦN SỬA, orchestrator sửa rồi đóng, không có vòng 4; user duyệt).
- Admin lưu xong, học viên đang mở bài giữ nội dung cũ tới lần tải kế; bài bị xoá thì `/run` trả 404.
- Chưa xác minh: hành vi nginx thật với `location /api/admin/` ngoài lần smoke test 401 sau deploy; CORS khi `flutter run` khác origin backend local.

## Nguồn

backend/app/admin_api.py:1-124; backend/app/load_content.py:1-420; backend/app/content_rules.py:1-320; backend/app/export_content.py:1-73; backend/app/main.py:26-60; backend/README.md:34-62; mobile/lib/features/admin/ (admin_controller.dart:178-218,337-395,519, admin_screen.dart, admin_theme_screen.dart, admin_module_screen.dart:255-352, admin_widgets.dart:14-35,117-130,561-660, exercise_editor.dart); mobile/lib/app/router.dart:88-110; planning/crew/2026-10-11-admin-ux-levels/PLAN.md (mục 1-8, INV-01..04), reviews/SEAM.md, T-02.md; mobile/lib/data/admin_repository.dart; planning/crew/2026-10-11-users-progress-admin/PLAN.md (mục 5, 6; INV-06), reviews/SEAM.md, DEVIATIONS.md, STATUS.md.
