# Exercise screen (màn bài 3 tab, ô TODO, khoá bài)

> Màn `/exercise/:id`: tab Challenge (đề), Code (notebook các ô TODO + Run chấm thật), Solution (lời
> giải từng ô). Người học đi vào từ danh sách bài hoặc thẻ "Tiếp tục" ở Home.

## Là gì

Mỗi bài là một hàm Python ngắn (hoặc một method của class, vd `FlightService.add_flight`), chia thành vài ô nhỏ (A, B, C) vì gõ nhiều dòng trên điện thoại rất
mệt. Phần code còn lại của hàm đã có sẵn và bị khoá, người học chỉ gõ các ô TODO, không cần lo thụt
lề. Bấm Run thì app tự ghép các ô vào code khoá, gửi lên backend chấm bằng Python thật, rồi hiện
bảng test (input / mong đợi / nhận được) và tô đỏ đúng ô gây lỗi. Pass hết test thì bài được tính là
xong và bài kế tiếp trong cùng file mở khoá. Solution cho xem lời giải từng ô, nhưng ô đã xem thì
không tính điểm.

## Dùng khi nào

Router mở `ExerciseScreen` ở `/exercise/:exerciseId` (mobile/lib/app/router.dart:126). Điểm vào: dòng
bài ở Topic detail (`ExerciseRow`), thẻ "Tiếp tục" ở Home, nút "Bài tiếp theo" sau khi pass, và mở
thẳng route. Bài chưa mở khoá hiện `_LockedView` thay cho 3 tab
(mobile/lib/features/exercise/exercise_screen.dart:36-40).

## Cách hoạt động

Luồng một lần Run (mobile/lib/features/exercise/code_tab.dart:97-137):

| Bước | Hành động |
|---|---|
| 1 | Có ô rỗng → đánh dấu ô rỗng, KHÔNG gọi backend (dòng 100-111) |
| 2 | `mergeCells` ghép template + các ô, ra `code` và `lineOrigin` (dòng 115) |
| 3 | `judgeClientProvider.run(exerciseId, code)` (dòng 124-126) |
| 4 | Chỉ `JudgeStatus.passed` mới gọi `markPassed` (dòng 128-130) |
| 5 | Hiện `RunResultView`: bảng test, tô ô lỗi theo `lineOrigin[line-1]` |

Template khoá + marker, ví dụ bài `split-chunks` (marker B thụt sâu hơn vì nằm trong vòng `for`):

```json
"template": "def split_chunks(text, size):\n    chunks = []\n    # TODO A\n        # TODO B\n    # TODO C",
```
(backend/content/content.json:112, tải về app qua `GET /content`; màn bài đọc bài bằng
`ref.read(contentIndexProvider).exerciseById`, mobile/lib/features/exercise/exercise_screen.dart:115). `mergeCells` thụt nội dung ô theo thụt lề của dòng marker
(mobile/lib/domain/merge.dart:80-102), nên người học gõ ô B không cần gõ 8 dấu cách.

Tiêu đề mỗi ô có nhãn vị trí ("trong hàm", "trong method", "trong class") suy từ template, không lưu trong DB:
`cellLocation` tìm dòng marker của ô, lấy dòng cha gần nhất thụt lề nhỏ hơn rồi phân loại `def`/`class`
(mobile/lib/domain/merge.dart:135-175; dùng ở mobile/lib/features/exercise/code_tab.dart:444 và
mobile/lib/features/exercise/cell_editor_page.dart:18,113). Cha là marker ô khác thì xét dòng đầu đáp án mẫu của ô
đó; `def` lấy từ đáp án mẫu coi là hàm vì không biết có nằm trong class (mobile/lib/domain/merge.dart:158-168).
Nhãn không kèm tên method (ngắn, vừa tiêu đề ô ở 375px; planning/crew/2026-10-11-project-tree-airline/DEVIATIONS.md).

Tab Challenge có thêm mục "SƠ ĐỒ CLASS" sau phần ví dụ, chỉ hiện khi bài là method (`classScope` khác null) và theme có class đó trong `diagram` (mobile/lib/features/exercise/challenge_tab.dart:36-45,101-105). Phần được tô là thuộc tính `self.<x>` trong thân method của bài, suy từ code ghép đáp án mẫu, cộng chính method đó:

| Thành phần | Hiển thị | Nguồn |
|---|---|---|
| Class của bài | hộp đủ thuộc tính (core/support) + method; mục thuộc bài nền accent, chữ đậm | mobile/lib/features/exercise/class_diagram.dart:88-96,138,165 |
| Class có quan hệ, là `from` | hộp thu gọn, chỉ method trong `via` | mobile/lib/features/exercise/class_diagram.dart:195,232-234 |
| Class có quan hệ, là `to` | hộp thu gọn, chỉ tên | mobile/lib/features/exercise/class_diagram.dart:195-222 |
| Bài hàm rời / theme chưa có sơ đồ | không hiện mục | mobile/lib/features/exercise/challenge_tab.dart:44-45 |

Ký hiệu quan hệ: ◇ aggregation, ◆ composition, ⇢ dependency, → association (mobile/lib/features/exercise/class_diagram.dart:175-180).

Quy tắc khoá một nơi: bài k trong `CodeFile` mở khi k = 0 hoặc bài k-1 đã passed; bài đã passed luôn mở;
bài nằm ở nhiều file mở nếu mở ở bất kỳ file nào (mobile/lib/domain/progression.dart:22-33). `ExerciseRow`,
`ExerciseScreen` đều qua `exerciseUnlockedProvider` (mobile/lib/features/exercise/session_providers.dart:45-52).

| Nơi tính điểm | Cách xử lý ô đã xem lời giải | Nguồn |
|---|---|---|
| Stats | không coi là "sạch" (cùng điều kiện không dùng gợi ý) | mobile/lib/features/stats/stats_screen.dart:36-40 |
| Review | hạn ôn của thẻ bị kéo về nhiều nhất là ngày mai | mobile/lib/features/review/review_controller.dart:122-148 |

Đồng hồ/idle áp cho cả màn: mọi chạm trên màn reset idle kể cả chỉ đọc đề
(mobile/lib/features/exercise/exercise_screen.dart:228-233); idle mở hộp thoại, timeout tự thoát và
báo "Đã lưu tiến độ" (mobile/lib/features/exercise/exercise_screen.dart:205-219).

Hai bố cục theo bề rộng (từ run 2026-10-12-issue29-reskin):

| Bề rộng | Bố cục | Mở ô |
|---|---|---|
| < 900px | `TabBar` 3 tab như trên (Key `exercise-tabs`, text `Code n/m`) | route `CellEditorPage` |
| ≥ 900px | ẩn `TabBar`; cột trái 42% tab Đề / Lời giải, cột phải 58% `CodeTab(inlineEditor: true)` | editor inline trong notebook + dải bước A/B/C |

(mobile/lib/features/exercise/exercise_screen.dart:292-298,448-458; mobile/lib/features/exercise/code_tab.dart:37-47). Ngưỡng 900 lấy từ `AppBreakpoint.split`. Ghost text của editor chỉ phủ hiển thị qua `buildTextSpan`, không đổi `controller.text`, nên `_isDone` và draft không thấy chữ gợi ý (mobile/lib/features/exercise/code_input.dart:725-746, code_tab.dart:77).

## Ranh giới & đánh đổi

Ghép ô làm ở client (Dart) một chỗ duy nhất thay vì ở backend, để ánh xạ dòng lỗi → ô chỉ có một nơi.
Đổi lại hai bên phải khớp tay: `error.line` backend là 1-based trên code đã gửi, client tra
`lineOrigin[line-1]` (mobile/lib/features/exercise/run_result_view.dart:23-30). Ô rỗng không sinh dòng,
nên UI phải chặn Run khi có ô rỗng (đã chặn ở code_tab.dart:100-111). `knownIdentifiersFor` cho autocomplete
nay quét cả phần khoá của template (mobile/lib/features/exercise/session_controller.dart:286-300).

Không làm: nút "chép lời giải vào ô", khoá bài xuyên file/topic.

## Giới hạn đã biết

- `cellLocation` đoán vị trí ô bằng thụt lề nên sai ở vài ca lạ: comment `#` thụt ít hơn bị coi là cha, `async for/with`, header nhiều dòng, `self.x` gán ở ô trước (mobile/lib/domain/merge.dart:135-175; planning/crew/2026-10-11-project-tree-airline/STATUS.md, Backlog cellLocation).
- Rời màn khi đang Run thì kết quả `passed` về sau bị bỏ (`if (!mounted) return`,
  mobile/lib/features/exercise/code_tab.dart:126) → mất tiến độ (SEAM M-3 trong STATUS.md:47).
- `nextExerciseAfter` chỉ xét file đầu tiên chứa bài, còn `isExerciseUnlocked` xét mọi file — bài dùng
  chung nhiều file có thể cho "Bài tiếp theo" khác phạm vi khoá (mobile/lib/domain/progression.dart:37-43; SEAM M-5).
- Viền lỗi cũ còn sau khi sửa ô; thiếu test timeout và test tap ngoài màn (STATUS.md:45, Backlog T-09).
- `activity()` gán state mới mỗi lần chạm nên rebuild cả 3 tab, chưa đo có giật không (STATUS.md:44, Backlog T-11).
- Thẻ theme ở Home vẫn ghi "x/y block" trong khi app gọi là "ô" (STATUS.md:46).
- Chưa chạy trên simulator bằng tay; e2e dùng widget test tạm với backend + Judge0 thật
  (planning/crew/2026-10-11-exercise-tabs-judge/STATUS.md:28-31).
- Sơ đồ: `classScope` bỏ sót `def` một dòng/nhiều dòng (0 bài dính), đếm cả `self.x` trong comment/string, chạy lại mỗi build; key hàng quan hệ trùng nếu hai quan hệ cùng cặp; test highlight chỉ kiểm key, chưa test kiểu dài/dark/375px riêng (planning/crew/2026-10-11-class-diagram/STATUS.md, Backlog).
- Backlog T-07 chưa có câu trả lời: ô đã xem lời giải bị ôn mỗi ngày mãi (STATUS.md:41).

- Đổi cỡ cửa sổ qua 900 giữa chừng dựng lại `CodeTab`: mất focus và kết quả Run đang hiện, draft còn (mobile/lib/features/exercise/exercise_screen.dart:292-298; planning/crew/2026-10-12-issue29-reskin/reviews/SEAM.md). Ghost text bị ẩn khi IME đang composing trên Android (chưa kiểm trên thiết bị thật).

## Nguồn

- Màn + 3 tab + idle/timeout: mobile/lib/features/exercise/exercise_screen.dart:31-304
- Tab Code: mobile/lib/features/exercise/code_tab.dart:23-300; kết quả: mobile/lib/features/exercise/run_result_view.dart:13-290
- Tab Challenge / Solution: mobile/lib/features/exercise/challenge_tab.dart:14, mobile/lib/features/exercise/solution_tab.dart:15-65
- Nội dung bài: backend/content/content.json → GET /content (xem docs/ARCHITECTURE.md, mục "Luồng nội dung"); đọc qua mobile/lib/data/content_providers.dart:11
- Ghép ô: mobile/lib/domain/merge.dart; khoá bài: mobile/lib/domain/progression.dart
- Client chấm: mobile/lib/data/judge_client.dart:57-149
- Sơ đồ class: mobile/lib/domain/class_scope.dart:24-55, mobile/lib/features/exercise/class_diagram.dart, challenge_tab.dart:36-105
- Quyết định: docs/DECISIONS.md (các mục của run 2026-10-11-exercise-tabs-judge)
- Run: planning/crew/2026-10-11-exercise-tabs-judge/PLAN.md, DEVIATIONS.md, reviews/SEAM.md
