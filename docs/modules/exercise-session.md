# Exercise session (tiến độ, đồng hồ, idle/timeout)

> Theo dõi một bài đang làm: đã pass chưa, code đang gõ dở ở từng ô, gợi ý/lời giải đã dùng, đồng
> hồ đếm giờ, phát hiện ngồi im (idle) và tự thoát khi hết giờ. Dùng bởi `ExerciseScreen` và các tab.

## Là gì

Đây là "bộ nhớ tạm thời" của một lượt làm bài — không phải dữ liệu bài học (đó là domain/seed), mà là
trạng thái người học đang ở đâu: bài đã được backend chấm pass chưa, mỗi ô đang gõ dở gì, đã dùng bao
nhiêu gợi ý, đã mở lời giải ô nào, đồng hồ chạy bao lâu, có đang ngồi im quá lâu không. Sống bằng hai
Riverpod `Notifier` tách biệt: `ProgressController` (tiến độ, không tự huỷ) và `SessionController`
(đồng hồ/idle, tự huỷ khi rời màn hình, tách riêng theo từng `exerciseId`).

## Dùng khi nào

`ExerciseScreen` gọi `sessionProvider(exerciseId).notifier.start()` sau frame đầu tiên
(mobile/lib/features/exercise/exercise_screen.dart:121-124) và `.activity()` mỗi lần chạm màn
(mobile/lib/features/exercise/exercise_screen.dart:228-233); tab Solution gọi `activity()` khi mở lời giải
(mobile/lib/features/exercise/solution_tab.dart:64). Tab Code ghi `saveDraft`, `useHint`, `markPassed` vào
`progressProvider`. Các màn khác (Home, ExerciseRow, Stats, Review, Practice) chỉ đọc `progressProvider`.

## Cách hoạt động

"Đã xong" có đúng một nguồn là `ExerciseProgress.passed`; các giá trị khác suy ra từ nó hoặc từ draft:

```dart
int get completedBlocks => passed ? totalBlocks : 0;

bool get inProgress =>
    !passed && drafts.values.any((code) => code.trim().isNotEmpty);
```
(mobile/lib/features/exercise/session_controller.dart:47-51)

| Trường của `ExerciseProgress` | Nghĩa | Ghi bởi (session_controller.dart) |
|---|---|---|
| `passed` | backend trả `passed` | `markPassed`, dòng 93-98 (idempotent) |
| `drafts` (key = nhãn ô A/B/C) | code đang gõ dở | `saveDraft`, dòng 101 |
| `hintsUsed` (tối đa 3 mỗi ô) | số gợi ý đã mở | `useHint` |
| `solutionViewed` (tập nhãn ô) | ô đã xem lời giải, không tính điểm | `viewSolution`, dòng 125-135 |

Đồng hồ và idle:

```dart
enum SessionPhase { active, idle, timedOut }

const idleThreshold = Duration(minutes: 2);   // ngồi im bao lâu thì hỏi "vẫn đang làm?"
const idleCountdown = Duration(seconds: 60);  // đếm ngược khi đang idle
const maxSessionDuration = Duration(minutes: 15);
```
(mobile/lib/features/exercise/session_controller.dart:15-24)

`start()` **idempotent**: gọi lại khi timer đang chạy và chưa timeout thì chỉ coi như một lần
`activity()`, không làm đồng hồ nhảy về `00:00`. Chỉ khi chưa có timer hoặc phiên đã `timedOut` mới
khởi động lại từ đầu:

```dart
void start() {
  // Nếu timer đang chạy và chưa timedOut → chỉ đánh dấu activity
  if (_timer != null &&
      _timer!.isActive &&
      state.phase != SessionPhase.timedOut) {
    activity();
    return;
  }
  // ... reset elapsed = 0, phase = active, khởi động lại Timer.periodic
}
```
(mobile/lib/features/exercise/session_controller.dart:184-205)

| Trước (thiết kế ban đầu) | Sau (sửa lỗi mối nối) |
|---|---|
| `start()` luôn reset đồng hồ về 0 | `start()` chỉ reset khi timer chưa chạy hoặc đã timedOut |
| Gọi `start()` từ `initState` của mỗi block khiến đồng hồ nhảy về 0 khi chuyển block | Đồng hồ chạy liên tục trong cùng phiên |

## Ranh giới & đánh đổi

`ProgressController` không `autoDispose` vì phải sống qua việc `SessionController` (autoDispose theo
exercise) bị huỷ khi người học rời màn hình; `SessionController` có `autoDispose` vì không cần giữ đồng
hồ chạy khi không ai xem màn đó (mobile/lib/features/exercise/session_providers.dart:16-26).

Màn bài hiện là MỘT màn cho cả bài, nên `start()` chỉ gọi một lần mỗi lần mở màn; tính idempotent vẫn
giữ vì `go_router` có thể dựng lại màn khi chuyển sang bài kế tiếp. Mọi chạm trên màn đều reset idle,
kể cả chỉ đọc đề ở tab Challenge (mobile/lib/features/exercise/exercise_screen.dart:228-233) — trước đó
đọc đề lâu bị coi là ngồi im.

Cơ chế cũ "chỉ block đang active mới được tăng tiến độ" (`markBlockPassed`, `blockStatusOf`) đã bị bỏ:
bài pass hay chưa do backend quyết định, app không tự suy từ từng block.

## Giới hạn đã biết

- Tiến độ/draft/hint/lời giải được nạp từ server khi đăng nhập và đẩy lại khi đổi (draft gom 800 ms, hint và xem lời giải
  đẩy ngay); lỗi mạng giữ local và đẩy lại ở lần đổi kế, không flush khi app vào nền (xem `docs/modules/auth-progress.md`).
  Không còn tiến độ demo trong app (`demo_seed.dart` đã xoá).
- `ExerciseProgress(passed: true)` dựng tay mà không đặt `totalBlocks` thì `completedBlocks` = 0
  (planning/crew/2026-10-11-exercise-tabs-judge/STATUS.md:40, Backlog T-06).
- Draft có nhãn lạ (không thuộc ô nào của bài) vẫn được đếm là "đã viết", và Practice xếp bài khoá có
  draft vào "Đang dở" (STATUS.md:42, Backlog T-07b).
- Idle/timeout lưu draft trước khi thoát đã được kiểm bằng test tạm trong review mối nối của run
  phase 1, không phải test còn lại trong repo (planning/crew/2026-09-24-flutter-demo-core/reviews/SEAM.md,
  INV-05); chưa chạy trên simulator/thiết bị thật.

## Nguồn

- `ExerciseProgress`, `ProgressController`: mobile/lib/features/exercise/session_controller.dart:26-135
- `SessionController`, `start()`, `_tick()`, `activity()`: mobile/lib/features/exercise/session_controller.dart:138-270
- Providers (`sessionProvider`, `progressProvider`, `clockProvider`, `inProgressExerciseProvider`, `exerciseUnlockedProvider`): mobile/lib/features/exercise/session_providers.dart
- Idle/timeout trên màn: mobile/lib/features/exercise/exercise_screen.dart:133-219
- Sửa idempotent (phase 1): planning/crew/2026-09-24-flutter-demo-core/STATUS.md (dòng "T-04b")
- Đổi mô hình tiến độ + idle khi đọc đề: planning/crew/2026-10-11-exercise-tabs-judge/PLAN.md (INV-06/09), DEVIATIONS.md (T-11)
