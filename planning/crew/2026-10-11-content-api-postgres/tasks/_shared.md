# Hợp đồng dùng chung (đọc kèm contract từng task)

## JSON `/content` và `content.json`
Xem PLAN.md mục "Hợp đồng `GET /content`". snake_case. `content.json` = cùng shape + mỗi exercise có
`"judge": {"solution": str, "cases": [...]}` (cases y hệt `backend/app/exercises.json` hiện tại).
Thứ tự mảng (themes, topics, files, exercise_ids, blocks) = thứ tự hiển thị — giữ đúng thứ tự trong seed.dart.

## Dart (T-03 tạo) — `mobile/lib/domain/content.dart`
```dart
class Content {
  const Content({required this.version, required this.themes});
  final String version;
  final List<StudyTheme> themes;
  factory Content.fromJson(Map<String, dynamic> json); // file.exercise_ids → cùng một instance Exercise cho bài dùng chung; id lạ → FormatException
  Map<String, dynamic> toJson();                        // đúng shape /content, KHÔNG có judge
  Exercise exerciseById(String id);                     // StateError nếu không có (giữ hành vi seed cũ)
  ({StudyTheme theme, Topic topic, CodeFile file}) locateExercise(String exerciseId);
  List<Exercise> uniqueExercises();
  List<({StudyTheme theme, Topic topic, CodeFile file})> locateFilesNamed(String fileName);
}
```
Mỗi model (`StudyTheme, Topic, CodeFile, Exercise, Block, Challenge, Example`) có `fromJson`/`toJson` theo đúng key snake_case.
`mobile/lib/data/content_providers.dart`: `final contentIndexProvider = Provider<Content>((ref) => …)` — T-03: mặc định
`Content(version: 'seed', themes: seedThemes)`; T-07 đổi sang đọc từ `contentProvider` (AsyncNotifier) đã nạp.

## Quy tắc đọc nội dung ở app (T-04, T-05)
- Widget/Provider: `ref.watch(contentIndexProvider)`.
- Hàm thuần (`progression.dart`): nhận `Content content` làm tham số đầu.
- `ProgressController.build()` KHÔNG được `ref.watch(contentIndexProvider)` (nội dung đổi sẽ dựng lại
  controller và XOÁ tiến độ — vi phạm INV-10). Dùng `ref.read` khi cần tra số ô.
