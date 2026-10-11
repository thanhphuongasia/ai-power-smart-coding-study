# Run `admin-ux-levels` — trang Admin "đi từng tầng": Projects → module → file + thẻ bài

## Context

Trang Admin hiện là một cây phẳng nhiều icon sửa/thêm/xoá, chữ to, rối trên điện thoại (ảnh user gửi).
User chọn hướng **đi từng tầng**: hiển thị theo module, đẹp, thêm nội dung dễ. Controller/API giữ nguyên
(chỉ thêm 2 hàm nhỏ); hành vi giữ: dirty, 409, 422, xác nhận Hủy sửa, refresh /content sau lưu.
Git: thẳng trên main, commit + push + deploy sau test xanh + seam gate.

## Thiết kế

1. **Điều hướng bằng go_router** (back và URL web đúng): `/admin` (Projects) → `/admin/theme/:themeId`
   → `/admin/module/:moduleId` → `/admin/exercise/:id` (đã có, form `ExerciseEditorScreen`). Mỗi màn có
   breadcrumb ngắn ("Projects / Airline / Flight"), chạm để lùi.
2. **Tầng 1 Projects** (`admin_screen.dart`): thẻ theme — tên, mô tả 2 dòng, "N module · M bài", nút sơ đồ
   class (dialog JSON có sẵn), menu ⋯ (Đổi tên/mô tả). Nút lớn "+ Thêm project". AppBar chỉ "Soạn nội dung"
   (bỏ hash version).
3. **Tầng 2 theme** (`admin_theme_screen.dart`): thẻ module cấp 1 (tên, "N file · M bài", sub-module lồng
   đếm gộp), chấm đỏ nếu lỗi validate thuộc bài trong module; menu ⋯ (Đổi tên/mô tả); "+ Thêm module".
4. **Tầng 3 module** (`admin_module_screen.dart`): mỗi file là một nhóm (tiêu đề tên file, ⋯ đổi tên),
   bài là thẻ nhỏ (tiêu đề, `class.hàm`/`hàm`, "K ô", chấm đỏ nếu lỗi) → chạm mở form sửa bài; ⋯ trên thẻ
   bài: Xoá (xác nhận như cũ). "+ Thêm bài" cuối mỗi file, "+ Thêm file", sub-module là thẻ (mở tầng 3 của nó),
   "+ Thêm module con".
5. **Thêm bài = hộp thoại hướng dẫn**: Tiêu đề, Tên hàm, Class (tuỳ chọn) → tạo bài với template/solution
   khung đúng hàm/class đó → mở thẳng form sửa bài.
6. **Thanh dưới ghim** (widget dùng chung cho cả 3 tầng): "Đã đồng bộ" / "● Chưa lưu", Kiểm tra, Lưu;
   có lỗi → "N lỗi" chạm mở bottom sheet danh sách lỗi; banner 409 + Tải lại; Hủy sửa (xác nhận) trong menu.
7. **Widget dùng chung** (`admin_widgets.dart`): thẻ, breadcrumb, menu ⋯, nút "+ Thêm …", thanh lưu,
   sheet lỗi, hàm map lỗi → id bài (lỗi server dạng `bài <id>: …`). Dùng `context.palette`, `SurfaceCard`,
   `PrimaryButton`/`GhostButton` ở `lib/shared/widgets.dart` — cùng phong cách màn học viên.
8. **Controller (thêm nhỏ)**: `String? addTheme(String name)` (theme rỗng: diagram `{classes:[],relations:[]}`,
   topics `[]`); `addExercise(fileId, title, {String functionName, String? className})` — scaffold dùng đúng
   hàm/class: template `def fn(…):\n    # TODO A` (hoặc `class C:\n    def fn(self):\n        # TODO A`),
   indent_level khớp. Tham số mặc định giữ hành vi cũ cho caller hiện có.

## Sổ bất biến

```text
INV-01 · Mọi thao tác trên UI mới đi qua API controller (updateNode/addTheme/addModule/addFile/addExercise/deleteExercise/replaceDiagram/validate/save/discardChanges) — không sửa JSON trực tiếp; dirty/409/422/xác nhận Hủy sửa/refresh /content sau lưu giữ nguyên
         phải khớp: mobile/lib/features/admin/admin_controller.dart · mobile/lib/features/admin/admin_screen.dart · admin_theme_screen.dart · admin_module_screen.dart · admin_widgets.dart
         vỡ thì thấy gì: sửa xong không hiện "Chưa lưu", lưu mất sửa, 409 không có banner
INV-02 · Route admin: /admin, /admin/theme/:themeId, /admin/module/:moduleId, /admin/exercise/:id đều đăng ký và breadcrumb/back đúng; từ Home ≤2 chạm tới danh sách project (admin-button)
         phải khớp: mobile/lib/app/router.dart · các màn admin · mobile/test/admin_screen_test.dart
         vỡ thì thấy gì: bấm thẻ module không mở được / back thoát khỏi admin
INV-03 · Bài tạo bằng hộp thoại có function_name/class_name khớp template khung (form sửa bài + preview ghép không vỡ, server không báo `def <fn>(` thiếu khi đã điền solution)
         phải khớp: admin_controller.dart (addExercise, exerciseScaffold) · mobile/lib/features/admin/exercise_editor.dart · backend/app/content_rules.py (_exercise_errors)
         vỡ thì thấy gì: bài mới mở form thấy hàm/class sai, preview "Chưa ghép được"
INV-04 · Chấm đỏ đọc đúng định dạng lỗi server `bài <id>: …` và gắn đúng bài/module chứa bài
         phải khớp: admin_widgets.dart (map lỗi) · backend/app/content_rules.py · backend/app/load_content.py
         vỡ thì thấy gì: Kiểm tra báo lỗi nhưng không thẻ nào có chấm đỏ, hoặc chấm nhầm chỗ
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | `crew-impl-light` · T1 · haiku | `addTheme`, `addExercise(..., functionName, className)` scaffold khớp hàm/class + test | `mobile/lib/features/admin/admin_controller.dart`, `mobile/test/admin_controller_test.dart` | `cd mobile && flutter test test/admin_controller_test.dart` |
| T-02 | `crew-impl-standard` · T2 · sonnet | 3 màn tầng + widget dùng chung + route + test luồng mới từ Home | `mobile/lib/features/admin/admin_screen.dart`, `admin_theme_screen.dart` (mới), `admin_module_screen.dart` (mới), `admin_widgets.dart` (mới), `mobile/lib/app/router.dart`, `mobile/test/admin_screen_test.dart` | `cd mobile && flutter analyze && flutter test` |

T-02 có 6 file (4 file màn/widget + router + test) — test màn cũ chắc chắn đỏ khi đổi UI nên phải cùng task.
Thứ tự: T-01 → T-02 (T-02 gọi API mới). Review: mỗi task một `crew-review`; seam reviewer INV-01..04 →
`verify-seam.sh` → commit, push, deploy.

## Verification (orchestrator tự chạy)

1. `flutter analyze`, `flutter test` (cả phase2_screens_test: nút Admin mở được trang).
2. Chạy web local (localhost) cùng backend local ở chế độ mở, Chrome: Home → Admin → Airline → Flight →
   thấy file + thẻ bài; thêm bài qua hộp thoại → form sửa bài đúng hàm; Kiểm tra → chấm đỏ đúng bài nháp;
   xoá bài nháp → Lưu → Home vẫn đúng (mối nối INV-01/03/04). Chụp màn hình đối chiếu ảnh user gửi.
3. Deploy, mở trang Admin trên VPS kiểm nhanh.
