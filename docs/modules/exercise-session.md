# Exercise session (tiến trình, đồng hồ, idle/timeout)

> Theo dõi một bài đang làm: block nào đã xong/đang làm/khoá, đồng hồ đếm giờ, phát hiện ngồi
> im (idle) và tự thoát khi hết giờ. Dùng bởi `BlockListScreen` và `CellScreen`.

## Là gì

Đây là "bộ nhớ tạm thời" của một lượt làm bài — không phải dữ liệu bài học (đó là domain/seed),
mà là trạng thái người học đang ở đâu trong bài: đã qua bao nhiêu block, đang gõ dở gì, đã dùng
bao nhiêu hint, đồng hồ chạy bao lâu, có đang ngồi im quá lâu không. Sống bằng hai Riverpod
`Notifier` tách biệt: `ProgressController` (tiến trình, không tự huỷ) và `SessionController`
(đồng hồ/idle, tự huỷ khi rời màn hình, tách riêng theo từng `exerciseId`).

## Dùng khi nào

`CellScreen` gọi `sessionProvider(exerciseId).notifier.start()` khi màn hình được mount, và
`.activity()` mỗi khi người học gõ phím (qua `onActivity` của `CodeInput`,
mobile/lib/features/exercise/cell_screen.dart:255-256). `BlockListScreen` chỉ đọc
`progressProvider` để vẽ trạng thái từng block, không tự tính toán trạng thái (mọi suy luận đi
qua `blockStatusOf`).

## Cách hoạt động

```dart
enum SessionPhase { active, idle, timedOut }

const idleThreshold = Duration(minutes: 2);   // ngồi im bao lâu thì hỏi "vẫn đang làm?"
const idleCountdown = Duration(seconds: 60);  // đếm ngược khi đang idle
const maxSessionDuration = Duration(minutes: 15);
```
(mobile/lib/features/exercise/session_controller.dart:17-26)

`start()` không phải lúc nào cũng reset đồng hồ về 0 — nó **idempotent** theo nghĩa: gọi lại khi
timer vẫn đang chạy và chưa timeout thì chỉ coi như một lần "có hoạt động" (`activity()`), không
làm đồng hồ nhảy về `00:00`. Chỉ khi chưa có timer hoặc phiên đã `timedOut` mới thật sự khởi
động lại từ đầu:

```dart
void start() {
  if (_timer != null && _timer!.isActive && state.phase != SessionPhase.timedOut) {
    activity();
    return;
  }
  // ... reset elapsed = 0, phase = active, khởi động lại Timer.periodic
}
```
(mobile/lib/features/exercise/session_controller.dart:161-186)

| Trước (thiết kế ban đầu, T-04) | Sau (T-04b, sửa lỗi mối nối) |
|---|---|
| `start()` luôn reset đồng hồ về 0 | `start()` chỉ reset khi timer chưa chạy hoặc đã timedOut |
| Gọi `start()` từ `initState` của mỗi block khiến đồng hồ nhảy về 0 mỗi lần chuyển block | Đồng hồ chạy liên tục xuyên suốt các block trong cùng phiên |

## Ranh giới & đánh đổi

Lỗi ở cột "Trước" của bảng trên được phát hiện SAU khi T-04 (session) và T-06 (màn hình gọi
`start()` ở mỗi block) đã review PASS riêng lẻ — đúng kiểu lỗi mối nối: mỗi task đúng theo
contract của nó, nhưng ghép lại thì đồng hồ cả bài bị reset mỗi lần sang block mới. Sửa bằng
task T-04b hẹp phạm vi (STATUS.md của run gốc, dòng T-04b). Đây là lý do
`ProgressController` không `autoDispose` (phải sống qua việc `SessionController` — autoDispose
theo exercise — bị huỷ khi người học rời màn hình) trong khi `SessionController` thì có
`autoDispose` (không cần giữ đồng hồ chạy khi không ai xem màn hình đó).

Tăng tiến độ (`markBlockPassed`) chỉ chấp nhận khi `blockIndex` đúng bằng `completedBlocks`
hiện tại — cố tình chặn Run muộn (vd người học bấm Run ở block cũ sau khi đã qua block mới) làm
tiến độ tăng sai (mobile/lib/features/exercise/session_controller.dart:82-91).

## Giới hạn đã biết

- `run()` không kiểm `blockIndex` có nằm trong phạm vi `exercise.blocks` hay không trước khi
  index vào mảng — Backlog Minor "run() không bounds-check blockIndex" trong STATUS.md của run
  gốc, chưa sửa (mobile/lib/features/exercise/session_controller.dart:250 theo ghi chú backlog).
- Idle/timeout lưu draft trước khi tự thoát (INV-05 trong sổ bất biến của run) đã được kiểm bằng
  test tạm viết-chạy-xoá trong review mối nối, không phải test còn lại trong repo — xem
  `reviews/SEAM.md` mục INV-05 để biết cách đã kiểm và giới hạn của cách kiểm đó (không chạy
  trên simulator/device thật).
- Toàn bộ tiến độ/draft/hint sống trong bộ nhớ (Riverpod state), không ghi xuống đĩa — mất khi
  app bị kill. Phase 2 (issue #5) dự kiến thêm Hive.

## Nguồn

- `SessionController`, `start()`, `_tick()`: mobile/lib/features/exercise/session_controller.dart:135-260
- `ProgressController`, `markBlockPassed`: mobile/lib/features/exercise/session_controller.dart:56-127
- `blockStatusOf`: mobile/lib/features/exercise/session_controller.dart:276-280
- Providers (`sessionProvider`, `progressProvider`, `clockProvider`): mobile/lib/features/exercise/session_providers.dart
- Deviation T-04b: planning/crew/2026-09-24-flutter-demo-core/STATUS.md (dòng "T-04b start() idempotent")
- Review mối nối INV-01/INV-05: planning/crew/2026-09-24-flutter-demo-core/reviews/SEAM.md
