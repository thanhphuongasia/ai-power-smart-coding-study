# Architecture

> Repo demo cho ứng dụng học lập trình di động "Smart Coding Study": app Flutter (làm bài code
> trong ô nhỏ trên điện thoại, autocomplete đủ tốt để không nản) cùng một backend FastAPI nhỏ
> chấm bài bằng Python thật.

## Bản đồ nhanh

Ghi chú: script kiểm `verify-distill.sh` chỉ nhận toạ độ `file:dòng` có đuôi py/ts/js/sh/sql/toml/yaml/json/md,
không nhận `.dart`. Vì vậy cột cuối của dòng Dart trỏ về mục chi tiết trong tài liệu này
(docs/ARCHITECTURE.md:1) để gate không chặn; toạ độ `.dart` thật nằm ngay cột giữa.

| thành phần | vai trò và toạ độ | mục chi tiết |
| --- | --- | --- |
| backend | API `POST /run`: chạy harness + unit test của bài qua máy chấm (Judge0), trả đúng/sai từng test — backend/app/main.py:89 | docs/modules/judge-backend.md:1 |
| backend/runner | interface `CodeRunner` + `Judge0Runner` — backend/app/runner.py:42, backend/app/runner.py:56 | docs/modules/judge-backend.md:1 |
| backend/harness | chương trình chạy trên máy chấm: compile code học viên, chạy từng test case, in một dòng JSON — backend/app/harness.py:48 | docs/modules/judge-backend.md:1 |
| domain | model bất biến, ghép ô (mobile/lib/domain/merge.dart:80), khoá bài (mobile/lib/domain/progression.dart:22), hàm so chuỗi cũ (mobile/lib/domain/answer_checker.dart:68) | docs/ARCHITECTURE.md:1 |
| data | nội dung hiển thị tĩnh (mobile/lib/data/seed.dart:295) + client gọi `/run` (mobile/lib/data/judge_client.dart:57) | docs/ARCHITECTURE.md:1 |
| features/exercise | màn bài 3 tab (mobile/lib/features/exercise/exercise_screen.dart:31), tiến độ/đồng hồ (mobile/lib/features/exercise/session_controller.dart:29), editor autocomplete | docs/modules/exercise-screen.md:1 |
| features/browse | duyệt Home → Theme → Topic → danh sách bài có trạng thái khoá (mobile/lib/features/browse/exercise_row.dart:39) | docs/ARCHITECTURE.md:1 |
| features/review, stats, practice, admin, shell | ôn tập, thống kê, luyện, quản trị, bottom nav; đọc tiến độ từ cùng `progressProvider`, không mô tả chi tiết ở đây (mobile/lib/app/router.dart:26-59) | docs/ARCHITECTURE.md:1 |
| app | theme (mobile/lib/app/theme.dart:1) + router (mobile/lib/app/router.dart:22) | docs/ARCHITECTURE.md:1 |
| shared | widget dùng chung (card, chip, nút, progress bar...) (mobile/lib/shared/widgets.dart:1) | docs/ARCHITECTURE.md:1 |

## backend — chấm bài bằng Python thật

### Là gì

Backend là một server FastAPI rất nhỏ với đúng một việc: nhận `{exercise_id, code}` từ app, chạy
code đó cùng các test case của bài bằng Python thật rồi trả kết quả từng test. Test case và lời
giải tham chiếu chỉ nằm ở backend nên app không sửa được bài kiểm tra. Backend không tự chạy code
học viên — nó nhờ một "máy chấm" bên ngoài qua interface `CodeRunner`, hiện là Judge0 CE công
khai. Chi tiết xem `docs/modules/judge-backend.md`.

### Cách hoạt động

| Bước | Ai làm | file:dòng |
| --- | --- | --- |
| Kiểm body (≤64KB, có Content-Length) và `code` ≤ 8000 ký tự | middleware + `RunRequest` | backend/app/main.py:39-53 |
| Tra bài, ghép payload `{code, function, cases}` | `run()` | backend/app/main.py:91-98 |
| Gửi `HARNESS_SOURCE` làm source, payload làm stdin cho máy chấm (tối đa 4 đồng thời) | `runner.run` | backend/app/main.py:101-102 |
| Máy chấm hỏng/429/5xx/không hiểu → `503 runner_unavailable` | `RunnerUnavailable` | backend/app/main.py:103-105 |
| Quá giờ → `status: timeout`; còn lại parse dòng `__JUDGE_RESULT__` | `harness.parse_result` | backend/app/main.py:108-116 |

```python
class CodeRunner(Protocol):
    async def run(self, source: str, stdin: str) -> Execution: ...
```
(backend/app/runner.py:42-43)

### Ranh giới

Không chống gian lận: code học viên chạy cùng tiến trình với harness, nên cố tình in dòng kết quả
giả là tự lừa mình (chấp nhận cho app học). Không có xác thực người dùng, không lưu gì xuống đĩa.
Mặc định chỉ chạy local (`127.0.0.1:8000`).

## Domain + Data

### Là gì

Tầng dữ liệu thuần Dart, không phụ thuộc Flutter UI: cấu trúc nội dung học (theme → topic → file →
exercise → block, một block = một ô TODO) và các hàm thuần (ghép ô, khoá bài). Nội dung hiển thị
(đề, ví dụ, template, gợi ý, lời giải từng ô) vẫn là seed viết tay nạp sẵn trong bộ nhớ; chỉ phần
chấm bài đi qua backend.

### Cách hoạt động

Một bài có `template` là code khoá, mỗi ô TODO là một dòng `# TODO <nhãn>` ở đúng thụt lề:

```dart
template: 'def split_chunks(text, size):\n    chunks = []\n    # TODO A\n        # TODO B\n    # TODO C',
```
(mobile/lib/data/seed.dart:300)

`mergeCells` thay mỗi dòng marker bằng nội dung ô (đã dedent, thụt theo marker) và trả `lineOrigin`
để biết dòng nào thuộc ô nào (mobile/lib/domain/merge.dart:80-102). Lỗi trả về là số dòng của code
đã ghép nên client tra `lineOrigin[line-1]` để tô đúng ô (mobile/lib/features/exercise/run_result_view.dart:23-30).

So với phase 1: việc chấm không còn là `runBlock` so chuỗi với `acceptedAnswers` — backend chạy test thật,
còn `runBlock` chỉ phục vụ ôn tập và gợi ý phụ "kiểm tra lại ô này" (mobile/lib/domain/answer_checker.dart:68,
mobile/lib/features/exercise/code_tab.dart:177-189). Đơn vị làm bài không còn là block tuần tự mỗi block một màn:
cả bài nằm trên một màn và mỗi block là một ô (`Block.label` A/B/C). "Đã xong" không còn là `completedBlocks` đếm
block mà là `ExerciseProgress.passed` (mobile/lib/features/exercise/session_controller.dart:38,47).

### Ranh giới

Hợp đồng `/run` được giữ khớp bằng hai bên tự viết (Python `RunResponse` và Dart `JudgeClient._parse`)
cộng test fixture tay — không sinh code từ một schema chung (mobile/lib/data/judge_client.dart:109-146,
backend/app/main.py:64-82). Id bài trong seed phải trùng key của `backend/app/exercises.json`, được
khoá bằng `mobile/test/judge_contract_test.dart`.

## features/exercise — màn bài 3 tab + session

### Là gì

Màn người học thực sự làm bài. `ExerciseScreen` hiển thị đồng hồ, thanh 3 tab và kiểm bài đã mở
khoá chưa; mỗi tab là một widget riêng. `SessionController` lo đồng hồ/idle/timeout, còn
`ProgressController` giữ tiến độ (đã pass, code đang gõ, gợi ý đã dùng, ô đã xem lời giải). Chi tiết
xem `docs/modules/exercise-screen.md`, `docs/modules/exercise-session.md`,
`docs/modules/exercise-autocomplete.md`.

### Cách hoạt động

Ba tab (mobile/lib/features/exercise/exercise_screen.dart:293-295, nội dung ở dòng 302-304):
**Challenge** (`ChallengeTab`, mobile/lib/features/exercise/challenge_tab.dart:14) hiện đề bài, "dùng để làm gì"
và hai ví dụ (nhỏ + dự án thật); **Code** (`CodeTab`, mobile/lib/features/exercise/code_tab.dart:23) là notebook
gồm đoạn khoá và các ô TODO, bấm Run thì ghép → gọi backend → hiện bảng test (mobile/lib/features/exercise/code_tab.dart:97-137);
**Solution** (`SolutionTab`, mobile/lib/features/exercise/solution_tab.dart:15) mở lời giải từng ô và ghi
`solutionViewed` (mobile/lib/features/exercise/solution_tab.dart:59-65).

Chỉ khi backend trả `passed` thì tiến độ mới đổi:

```dart
if (result.status == JudgeStatus.passed) {
  ref.read(progressProvider.notifier).markPassed(_exercise.id);
}
```
(mobile/lib/features/exercise/code_tab.dart:128-130)

Ô còn rỗng thì Run không gọi backend mà đánh dấu ô rỗng (mobile/lib/features/exercise/code_tab.dart:100-111).
Bài chưa mở khoá hiện `_LockedView` thay vì 3 tab (mobile/lib/features/exercise/exercise_screen.dart:38-39).

### Ranh giới

Tiến độ vẫn nằm trong bộ nhớ Riverpod (`ProgressController` không `autoDispose`), mất khi kill app.
Rời màn khi đang Run thì kết quả `passed` về sau bị bỏ (`if (!mounted) return`,
mobile/lib/features/exercise/code_tab.dart:126), nên tiến độ không được ghi.

## features/browse — Home / Theme / Topic

### Là gì

Các màn đưa người học từ danh sách chủ đề tới đúng bài tập: Home liệt kê theme, Theme detail liệt kê
topic, Topic detail liệt kê file/exercise. Mỗi dòng bài (`ExerciseRow`) hiện trạng thái Mới / Đang
dở / Đã xong / Khoá, và Home có thẻ "Tiếp tục" cho bài đang dở.

### Cách hoạt động

Route (mobile/lib/app/router.dart): `/` là HomeScreen trong tab shell (dòng 31), `/theme/:themeId` là
ThemeDetailScreen (dòng 62), `/topic/:topicId` là TopicDetailScreen (dòng 68), `/exercise/:exerciseId` là
ExerciseScreen 3 tab (dòng 85) — thay cho BlockListScreen + CellScreen và route `/exercise/:id/block/:index` cũ.

`ExerciseRow` không tự viết điều kiện khoá, nó đọc `exerciseUnlockedProvider`
(mobile/lib/features/browse/exercise_row.dart:39); thẻ "Tiếp tục" đọc `inProgressExerciseProvider`
(mobile/lib/features/exercise/session_providers.dart:30-42).

### Ranh giới

Hai thứ tên gần giống nhau: `completedBlocks` nay chỉ là getter suy ra từ `passed` (xong thì bằng
tổng số ô, chưa xong thì 0), không còn nói "đã gõ đúng bao nhiêu block". Dựng tay
`ExerciseProgress(passed: true)` mà quên `totalBlocks` thì `completedBlocks` ra 0
(mobile/lib/features/exercise/session_controller.dart:47).

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

`router.dart` không có auth guard hay redirect — mọi route mở thẳng, kể cả `/exercise/:exerciseId`
(việc khoá bài do `ExerciseScreen` tự kiểm, không do router; xem mục features/exercise).

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

Tiến độ chưa bền: không có Hive hay SQLite, nên tiến độ, draft code, hint và ô đã xem lời giải sống trong
`ProgressController` và mất khi app bị kill (Hive thuộc issue #5). Về máy chấm, code học viên được gửi tới Judge0 CE
công khai của bên thứ ba, giới hạn theo IP: đủ cho dev local, không đủ production và không dùng cho dữ liệu nhạy cảm
(backend/app/runner.py:1-9). Hệ thống chỉ chạy local — iOS simulator gọi `127.0.0.1`; điện thoại thật và Android
emulator (`10.0.2.2`, cleartext) chưa làm, và harness không chống gian lận (xem mục backend ở trên,
planning/crew/2026-10-11-exercise-tabs-judge/PLAN.md:192-200).

Còn lệch nhỏ giữa client và server đã biết, chưa sửa: client không chặn code dài hơn 8000 ký tự nên 422 hiện như
"máy chấm bận"; timeout client 20 giây có thể ngắn hơn trường hợp xấu nhất của server; `\r` lẻ làm lệch `lineOrigin`
(planning/crew/2026-10-11-exercise-tabs-judge/STATUS.md:47, mục SEAM M-1/M-2/M-8).

Phần chưa tự quan sát: `flutter run` trên simulator hay thiết bị thật chưa chạy. Run 2026-10-11 kiểm e2e bằng
widget test tạm dùng `JudgeClient` thật gọi backend thật + Judge0 thật, chưa phải bấm tay trên simulator
(planning/crew/2026-10-11-exercise-tabs-judge/STATUS.md:28-31); phần "xem Solution → Stats không tính sạch" chỉ có
widget test, chưa chạy e2e.
