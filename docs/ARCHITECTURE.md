# Architecture

> Repo demo cho ứng dụng học lập trình di động "Smart Coding Study" — phase 1 là app Flutter
> đơn máy (không backend) tập trung vào một trải nghiệm: làm bài code trong ô nhỏ trên điện
> thoại, có autocomplete đủ tốt để không nản.

## Bản đồ nhanh

| thành phần | vai trò | file:dòng |
|---|---|---|
| domain | model dữ liệu bất biến (theme/topic/file/exercise/block) + hàm chấm bài | mobile/lib/domain/models.dart:1, mobile/lib/domain/answer_checker.dart:1 |
| data | nội dung mẫu tĩnh (seed), thay cho gọi API | mobile/lib/data/seed.dart:1 |
| features/exercise | luồng làm bài: session state, editor có autocomplete, màn Block list + Cell | mobile/lib/features/exercise/session_controller.dart:1, mobile/lib/features/exercise/code_input.dart:1 |
| features/browse | luồng duyệt nội dung: Home → Theme detail → Topic detail | mobile/lib/features/browse/home_screen.dart:1 |
| app | theme (design tokens) + router, điểm nối toàn app | mobile/lib/app/theme.dart:1, mobile/lib/app/router.dart:1 |
| shared | widget dùng chung nhiều màn (card, chip, nút, progress bar...) | mobile/lib/shared/widgets.dart:1 |

## Domain + Data

### Là gì

Đây là tầng dữ liệu thuần Dart, không phụ thuộc Flutter UI. Nó định nghĩa cấu trúc nội dung học
(theme → topic → file → exercise → block) và logic chấm bài — tách riêng khỏi UI để test được
mà không cần dựng widget. Vì phase 1 chưa có backend, `seed.dart` đóng vai trò "database giả":
toàn bộ nội dung bài học được viết tay, nạp sẵn trong bộ nhớ lúc app khởi động.

### Cách hoạt động

```dart
class Block {
  final String id, title, prompt;
  final int indentLevel;
  final List<String> acceptedAnswers; // nhiều cách viết đúng được chấp nhận
  final String expectedOutput;
  final List<String> hints;           // đúng 3, mờ → rõ
  final List<String> vocab;           // từ gợi ý riêng cho block
}
```

Chấm bài không chạy code Python thật — `runBlock()` chuẩn hoá code người học gõ
(`normalizeCode`, bỏ khoảng trắng thừa, đổi nháy đơn thành nháy kép, giữ nguyên thụt tương đối
giữa các dòng) rồi so trực tiếp với danh sách `acceptedAnswers` của block
(mobile/lib/domain/answer_checker.dart:23-90). Đúng thì trả `expectedOutput` mẫu có sẵn trong
seed, sai thì trả thông báo tiếng Việt cố định.

### Ranh giới

Không chạy Python thật — nghĩa là hai cách viết ra cùng kết quả nhưng khác cấu trúc code (vd
dùng `while` thay vì `for`) sẽ bị chấm sai nếu không nằm trong danh sách `acceptedAnswers` viết
tay. Đây là đánh đổi có chủ đích (xem PLAN.md quyết định 3): dựng sandbox chạy Python thật trên
di động tốn công vượt quá phạm vi một app demo phase 1.

## features/exercise — session + autocomplete editor

### Là gì

Đây là phần lõi mà user ưu tiên nhất trong run này: màn hình người học thực sự gõ code. Nó gồm
ba phần ăn khớp với nhau — `SessionController` theo dõi đồng hồ/idle/timeout của một bài đang
làm, `CodeInput` là ô soạn code có autocomplete kiểu thanh gợi ý (không phải popup desktop), và
hai màn hình (Block list, Cell) ráp chúng lại thành luồng làm bài từng block một, mở khoá tuần
tự. Chi tiết engine autocomplete và editor xem `docs/modules/exercise-autocomplete.md`.

### Cách hoạt động

Trạng thái từng block (đã xong/đang làm/khoá) suy ra từ đúng MỘT hàm, không lưu trùng ở nơi
khác:

```dart
BlockStatus blockStatusOf(ExerciseProgress p, int index) {
  if (index < p.completedBlocks) return BlockStatus.done;
  if (index == p.completedBlocks) return BlockStatus.active;
  return BlockStatus.locked;
}
```
(mobile/lib/features/exercise/session_controller.dart:276-280)

`markBlockPassed` chỉ tăng `completedBlocks` khi `blockIndex` đúng bằng block đang active — chặn
việc Run muộn/Run sai thứ tự làm tiến độ nhảy sai
(mobile/lib/features/exercise/session_controller.dart:82-91).

### Ranh giới

Tiến độ (`ProgressController`, không `autoDispose`) sống trong bộ nhớ Riverpod của phiên app,
không ghi xuống đĩa — thoát app là mất hết (xem mục Giới hạn đã biết cuối file, và
`docs/modules/exercise-autocomplete.md` phần "Giới hạn đã biết" cho phần liên quan editor).

## features/browse — Home / Theme detail / Topic detail

### Là gì

Ba màn hình đưa người học từ danh sách chủ đề tới đúng bài tập cần làm: Home liệt kê theme, Theme
detail liệt kê topic trong theme đó, Topic detail liệt kê file/exercise trong topic. Đây là
đường vào duy nhất tới màn làm bài — không có bottom nav ở phase 1 vì chưa có tab thứ hai thật
(PLAN.md, mục Phạm vi phase 1).

### Cách hoạt động

| Route | Widget | Điều hướng tiếp |
|---|---|---|
| `/` | HomeScreen | `context.push('/theme/:themeId')` |
| `/theme/:themeId` | ThemeDetailScreen | `context.push('/topic/:topicId')` |
| `/topic/:topicId` | TopicDetailScreen | `context.push('/exercise/:exerciseId')` |
| `/exercise/:exerciseId` | BlockListScreen | `context.push('/exercise/:exerciseId/block/:index')` |
| `/exercise/:exerciseId/block/:index` | CellScreen | — |

(mobile/lib/app/router.dart:11-40)

Từ Home có thẻ "Tiếp tục" nhảy thẳng vào bài đang dở — mục tiêu thiết kế là vào được Cell trong
≤2 chạm từ Home (PLAN.md, AC của T-06).

### Ranh giới

Home dùng khái niệm `completedBlocks`/`total` để hiển thị trạng thái TOÀN BỘ exercise
("Mới/Đang dở/Đã xong") — khác với `blockStatusOf` ở tầng exercise vốn nói về từng BLOCK riêng lẻ
bên trong một exercise. Hai khái niệm cùng tên biến nguồn (`completedBlocks`) nhưng ý nghĩa khác
cấp độ; xem review mối nối INV-01 trong `reviews/SEAM.md` của run gốc để biết ranh giới này đã
được kiểm tra rõ.

## app — theme + router

### Là gì

Tầng `app/` giữ hai thứ chạm tới toàn bộ ứng dụng: bảng màu/kiểu chữ/khoảng cách dùng chung
(`theme.dart`) và bảng route (`router.dart`). Mọi màn hình đọc màu qua `AppColors`/
`Theme.of(context).colorScheme`, không tự định nghĩa `Color(0x...)` riêng — quy tắc này được
kiểm bằng `grep` (INV-04 trong sổ bất biến của run, xem `reviews/SEAM.md`).

### Cách hoạt động

```dart
abstract final class AppColors {
  static const Color surface = Color(0xFF111418);
  static const Color primary = Color(0xFF5ccfb0);   // teal — màu chính
  static const Color accent = Color(0xFFf5b94a);     // amber — CHỈ dùng cho hint
  static const Color danger = Color(0xFFff7b72);
  // ...
}
```
(mobile/lib/app/theme.dart:6-17)

Font không tải qua mạng (không dùng gói `google_fonts`) — hai font family (IBM Plex Sans,
JetBrains Mono) được bundle sẵn dạng file `.ttf` trong `mobile/assets/fonts/` và khai trong
`pubspec.yaml` (mobile/pubspec.yaml:64-76).

### Ranh giới

`router.dart` không có auth guard hay redirect — mọi route mở thẳng, đúng với một app demo
không backend. `int.parse` trên tham số `:index` của route Cell không có try/catch
(mobile/lib/app/router.dart:35), ghi trong Backlog Minor của run gốc, chưa sửa.

## shared — widget dùng chung

### Là gì

Bộ widget tái dùng giữa các màn: `SurfaceCard`, `TagChip`, `ResultBadge`, `TimerPill`,
`ThinProgressBar`, `ScreenHeader`, `SectionLabel`, `PrimaryButton`, `GhostButton`, `HintButton`.
Tồn tại để tránh mỗi màn tự viết lại card/nút/progress bar theo phong cách khác nhau.

### Cách hoạt động

Tất cả đọc token từ `AppColors`/`AppSpace`/`AppRadius`/`AppText`, không hardcode giá trị —
`elevation` mặc định 0 (không đổ bóng), bo góc theo 3 mức cố định (`sm`=6, `md`=12,
`pill`=999) (mobile/lib/app/theme.dart:26-29).

### Ranh giới

`PrimaryButton`/`HintButton` bọc `ElevatedButton` của Material — còn giữ elevation mặc định của
Material thay vì elevation 0 tường minh ở hai chỗ này (mobile/lib/shared/widgets.dart:266,335);
đã ghi Minor trong Backlog, chưa sửa tại thời điểm run này kết thúc.

## Giới hạn đã biết

- Không có tầng lưu trữ bền vững (không Hive, không SQLite) — mọi tiến độ, draft code, hint đã
  dùng sống trong `ProgressController` (Riverpod `Notifier`, không `autoDispose`) và mất khi
  app bị kill. Phase 2 (issue #5) dự kiến thêm Hive để giữ qua restart.
- Không có tầng network/DI cho backend thật — `Dio`/`Retrofit`/`get_it`/`injectable` bị bỏ khỏi
  phase 1 vì chưa có backend để gọi; Riverpod đã đóng vai trò dependency injection đủ dùng
  (PLAN.md, quyết định 2). Thêm backend thật ở phase 2 sẽ cần quyết định lại có đưa các gói này
  trở lại hay không.
- Run = so khớp chuỗi đáp án đã chuẩn hoá, không chạy Python thật — xem mục Ranh giới của
  Domain + Data ở trên.
- `flutter run` trên simulator/device thật chưa được orchestrator chạy trong run gốc; việc kiểm
  layout màn hình nhỏ + bàn phím mở dựa vào widget test kích thước cố định (360×640,
  `viewInsets` giả lập 300), không phải ảnh chụp app chạy thật — Chrome headless không xuống
  được dưới ~500px nên không dùng để chụp màn hình 390px như dự tính ban đầu trong plan (xem
  DEVIATIONS.md của run 2026-09-24-flutter-demo-core).
