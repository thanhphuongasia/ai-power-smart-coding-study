# Exercise autocomplete editor

> Ô soạn code Python cho màn Cell (làm bài) trên điện thoại: thanh gợi ý từ nằm ngay trên bàn
> phím thay cho popup kiểu desktop, cộng phím ký hiệu và hành vi tự đóng ngoặc/overtype. Dùng
> bởi `CellScreen` — người học chạm vào nó mỗi block.

## Là gì

Đây là phần được user ưu tiên làm trước và làm kỹ nhất trong toàn bộ phase 1 (PLAN.md gọi đây
là "phần rủi ro nhất, làm sớm"), vì gõ code Python trên bàn phím điện thoại rất dễ khiến người
học nản — thiếu ngoặc, thiếu thụt dòng, gõ sai tên biến. Module này gồm hai phần tách rời: một
hàm thuần Dart tính danh sách gợi ý (`completion_engine.dart`, không phụ thuộc Flutter, test
được không cần dựng widget), và một widget editor (`code_input.dart`) hiển thị thanh gợi ý +
phím ký hiệu, đồng thời tự đóng ngoặc/nháy và tự thụt dòng theo cú pháp Python.

## Dùng khi nào

`CellScreen` (mobile/lib/features/exercise/cell_screen.dart:248-257) dựng một `CodeInput` cho
mỗi block, truyền vào `knownIdentifiers` (biến đã xuất hiện ở các block trước, tính bằng
`knownIdentifiersFor`) và `vocab` (từ vựng riêng của block, khai sẵn trong seed). Không có nơi
nào khác trong app gọi tới engine hay widget này — nó gắn chặt với luồng làm bài, không dùng lại
cho màn khác.

## Cách hoạt động

Engine xếp hạng gợi ý theo ba nhóm, ưu tiên biến đã có trước, rồi tới từ vựng riêng của bài, rồi
mới tới keyword Python chung:

```dart
enum SuggestionKind { known, vocab, keyword }
```
(mobile/lib/features/exercise/completion_engine.dart:7)

| Nhóm | Nguồn | Ví dụ |
|---|---|---|
| `known` | biến/tham số đã dùng ở block trước trong CÙNG exercise | `text`, `size`, `chunks` |
| `vocab` | từ vựng khai riêng cho block trong seed | `range`, `len`, `append` |
| `keyword` | danh sách keyword/builtin Python cố định | `def`, `for`, `range`, `print` |

Chưa gõ ký tự nào thì engine đoán theo ngữ cảnh cuối dòng thay vì liệt kê tất cả — gõ xong
`for ` gợi ý ngay `i`, gõ xong `in ` gợi ý `range(`
(mobile/lib/features/exercise/completion_engine.dart:84-109).

Editor có ba hành vi tự động, viết đè `set value` của `CodeController`:

```dart
@override
set value(TextEditingValue newValue) {
  super.value = _overtype(newValue) ?? _deletePair(newValue) ?? newValue;
}
```
(mobile/lib/features/exercise/code_input.dart:375-378)

- **Auto-close**: gõ `(` tự chèn `)` với con trỏ ở giữa (qua `_PairModifier`, không phải trong
  `set value`).
- **Overtype**: gõ ký tự trùng với dấu đóng đã có sẵn ngay sau con trỏ (vd `len(|)` rồi gõ `)`)
  thì con trỏ nhảy qua thay vì chèn thêm dấu đóng thừa — xử lý trong `_overtype()`
  (mobile/lib/features/exercise/code_input.dart:389-431).
- **IME batch**: bàn phím điện thoại có thể commit nhiều ký tự cùng lúc (gõ số rồi swipe, hoặc
  gõ nhanh) — `_overtype()` xử lý cả trường hợp batch nhiều ký tự đi kèm dấu đóng, nhưng khi
  batch không khớp mẫu overtype đơn giản thì KHÔNG tự thêm dấu đóng, để tránh đoán sai ý người
  dùng (comment tại mobile/lib/features/exercise/code_input.dart:386).

## Ranh giới & đánh đổi

Overtype ban đầu định làm trong `CodeModifier` (theo PLAN.md), nhưng modifier trả về text không
đổi khiến package `flutter_code_editor` tự ném `RangeError` ở `_getEditResultNotBreakingReadOnly`
(code.dart:301, package bên thứ ba). Đổi hướng: logic overtype/xoá cặp chuyển vào override
`set value` của `_PythonCodeController` — một subclass tự viết, không đụng vào modifier gốc
(xem DEVIATIONS.md của run `2026-09-24-flutter-demo-core`, dòng "Plan: overtype qua
CodeModifier"). Đánh đổi: logic phức tạp hơn (phải tự so sánh `TextEditingValue` cũ/mới để suy
ra người dùng vừa gõ gì), nhưng tránh được crash của package.

Không dùng popup gợi ý có sẵn của `flutter_code_editor`
(`generateSuggestions()` bị override thành no-op,
mobile/lib/features/exercise/code_input.dart:372-373) — thanh gợi ý tự viết thay thế hoàn toàn,
vì popup kiểu desktop không hợp thao tác chạm trên điện thoại (PLAN.md, mục Autocomplete).

## Giới hạn đã biết

- **Biến lặp sinh ra trong CHÍNH block 2 dòng chưa được gợi ý.** `knownIdentifiersFor` chỉ quét
  `acceptedAnswers[0]` của các block TRƯỚC `blockIndex` (mobile/lib/features/exercise/
  session_controller.dart:283-290) — biến như `i` được gán ở dòng 1 của một block 2 dòng (vd
  `for i in ...:` rồi dòng 2 dùng lại `i`) không nằm trong `knownIdentifiers` của chính block đó,
  và cũng không có trong `vocab` nếu người viết seed quên thêm. Phát hiện và kiểm chứng bằng
  test tạm trong review mối nối (`reviews/SEAM.md` của run gốc, mục INV-02) — không chặn được
  việc chấm bài đúng/sai (INV-03 vẫn đúng), chỉ là gõ dòng 2 không có gợi ý cho biến đó, phải
  gõ tay. Backlog: "SEAM Minor" trong STATUS.md của run gốc — đề xuất cho engine quét cả text
  đang gõ trong block hiện tại, không chỉ block trước, chưa làm.
- Chưa kiểm hết mọi tổ hợp gõ (tap gợi ý + phím ký hiệu + gõ tay xen kẽ) cho toàn bộ 14 block
  trong seed — review mối nối chỉ kiểm đại diện một số dạng block (xem "Không kiểm được" trong
  `reviews/SEAM.md`).
- Chưa chạy thử trên bàn phím thật (iOS/Android) qua `flutter run` — hành vi IME batch được suy
  từ đọc code + test giả lập `TextEditingValue`, không phải quan sát bàn phím vật lý thật.

## Nguồn

- Engine gợi ý: mobile/lib/features/exercise/completion_engine.dart:1-170
- Editor + overtype/auto-close: mobile/lib/features/exercise/code_input.dart:350-478
- `knownIdentifiersFor`: mobile/lib/features/exercise/session_controller.dart:276-300
- Nơi gọi: mobile/lib/features/exercise/cell_screen.dart:227-257
- Deviation overtype: planning/crew/2026-09-24-flutter-demo-core/DEVIATIONS.md
- Review mối nối INV-02/INV-03: planning/crew/2026-09-24-flutter-demo-core/reviews/SEAM.md
