# Hợp đồng giao diện giữa các task

Mọi task phải khớp đúng tên/chữ ký dưới đây. Đổi chữ ký = báo orchestrator, không tự đổi.
Package name: `smart_coding_study` → import `package:smart_coding_study/...`.

## lib/domain/models.dart (T-01)
Không đặt tên `CodeTheme`/`Theme` (trùng flutter_code_editor / material). Class immutable, constructor `const`.

```dart
class StudyTheme { final String id, name, description; final List<String> tags; final List<Topic> topics; }
class Topic      { final String id, name, description; final List<CodeFile> files; }
class CodeFile   { final String id, name; /* 'chunker.py' */ final List<Exercise> exercises; }
class Exercise   { final String id, title; /* 'Text chunking' */ final String functionName; /* 'split_chunks' */
                   final List<String> params; /* ['text','size'] */ final List<Block> blocks; }
class Block      { final String id, title, prompt;
                   final int indentLevel;              // số lần thụt 4 space của block trong hàm: def=0, thân hàm=1, thân for=2
                   final List<String> acceptedAnswers; // viết KHÔNG kèm thụt nền; dòng 2 trong block có thể thụt thêm 4 so với dòng 1
                   final String expectedOutput;        // hiện khi Run đúng
                   final List<String> hints;           // đúng 3, mờ → rõ
                   final List<String> vocab; }         // từ gợi ý riêng cho block, vd ['range','len','append']
```

## lib/data/seed.dart (T-01)
```dart
final List<StudyTheme> seedThemes;
final Map<String, int> seedCompletedBlocks;   // exerciseId → số block đã xong lúc mở app
Exercise exerciseById(String id);             // throw StateError nếu không có
({StudyTheme theme, Topic topic, CodeFile file}) locateExercise(String exerciseId);
```
ID bắt buộc (test và e2e dùng): theme `rag`, topic `rag-chunking`, file `rag-chunker-py`,
exercise `split-chunks` (5 block, 2 block đã xong = đang dở), `overlap-chunks` (chưa làm), một exercise đã xong hẳn.

## lib/domain/answer_checker.dart (T-01)
```dart
class RunResult { final bool passed; final String output; const RunResult({required this.passed, required this.output}); }
String normalizeCode(String code);
RunResult runBlock(String code, Block block); // passed → output = block.expectedOutput; sai → thông báo tiếng Việt
```

## lib/app/theme.dart (T-02)
```dart
abstract final class AppColors { static const Color surface, surfaceRaised, outline, ink, inkMuted,
                                  primary, onPrimary, accent, onAccent, danger; }
abstract final class AppSpace  { static const double s1 = 4, s2 = 8, s4 = 16, s6 = 24; }
abstract final class AppRadius { static const double sm = 6, md = 12, pill = 999; }
abstract final class AppText   { static const TextStyle display, title, body, label, caption, code; }
const String kSansFamily = 'IBM Plex Sans', kMonoFamily = 'JetBrains Mono';
ThemeData buildAppTheme();
```
ColorScheme của `buildAppTheme()` PHẢI map: `surface`=surface, `surfaceContainer`=surfaceRaised, `outline`=outline,
`onSurface`=ink, `onSurfaceVariant`=inkMuted, `primary`/`onPrimary`=primary/onPrimary,
`tertiary`/`onTertiary`=accent/onAccent (chỉ dùng cho hint), `error`=danger. Widget ở features dùng `AppColors`
hoặc `Theme.of(context).colorScheme` — KHÔNG `Color(0x...)` trong `lib/features/**`.

## lib/shared/widgets.dart (T-02)
`SurfaceCard({required Widget child, VoidCallback? onTap, bool highlighted = false})` ·
`TagChip(String label)` · `ResultBadge({required bool passed})` (luôn có chữ + icon) ·
`TimerPill(Duration elapsed, {bool warning = false})` (mm:ss, font mono) ·
`ThinProgressBar({required double value, Color? color})` ·
`ScreenHeader({required String title, String? subtitle, Widget? trailing, VoidCallback? onBack})` ·
`SectionLabel(String text)` · `PrimaryButton({required String label, VoidCallback? onPressed, IconData? icon})` ·
`GhostButton({required String label, VoidCallback? onPressed})` · `HintButton({required int used, int max = 3, VoidCallback? onPressed})` (màu accent).

## lib/features/exercise/completion_engine.dart (T-03)
```dart
enum SuggestionKind { known, vocab, keyword }
class Suggestion { final String label; final String insertText; final SuggestionKind kind; }
List<Suggestion> suggest({required String textBeforeCursor, required List<String> knownIdentifiers,
                          required List<String> vocab, int limit = 8});
```
Không import models (nhận kiểu thuần).

## lib/features/exercise/code_input.dart (T-03)
```dart
class CodeInput extends StatefulWidget {
  const CodeInput({super.key, required String initialCode, required List<String> knownIdentifiers,
    required List<String> vocab, required ValueChanged<String> onChanged, VoidCallback? onActivity, FocusNode? focusNode});
}
```
Key cho test: chip gợi ý `Key('suggestion-<label>')`, phím ký hiệu `Key('symbol-<char>')` (Tab: `Key('symbol-tab')`),
editor `Key('code-input-field')`.

## lib/features/exercise/session_controller.dart + session_providers.dart (T-04)
```dart
enum BlockStatus { done, active, locked }
enum SessionPhase { active, idle, timedOut }
class ExerciseProgress { final int completedBlocks; final Map<String, String> drafts; final Map<String, int> hintsUsed; }
class ProgressController extends Notifier<Map<String, ExerciseProgress>> {   // build() từ seedCompletedBlocks
  void markBlockPassed(String exerciseId, int blockIndex);  // chỉ tăng khi blockIndex == completedBlocks
  void saveDraft(String exerciseId, String blockId, String code);
  int useHint(String exerciseId, String blockId);           // trả số hint đã dùng sau khi tăng, tối đa 3
}
class SessionState { final Duration elapsed; final SessionPhase phase; final int idleCountdownSeconds; }
class SessionController extends Notifier<SessionState> {   // family theo exerciseId: SessionController(this.exerciseId)
  void start(); void activity(); void resume(); void stop();
  RunResult run(int blockIndex, String code);               // gọi runBlock; pass → progress.markBlockPassed
}
BlockStatus blockStatusOf(ExerciseProgress p, int index);
List<String> knownIdentifiersFor(Exercise exercise, int blockIndex); // params + tên được gán/lặp ở acceptedAnswers[0] các block trước
const idleThreshold = Duration(minutes: 2), idleCountdown = Duration(seconds: 60), maxSessionDuration = Duration(minutes: 15);
```
Providers (session_providers.dart): `clockProvider` (Provider<DateTime Function()>), `progressProvider`,
`sessionProvider` (`NotifierProvider.autoDispose.family<SessionController, SessionState, String>(SessionController.new)`),
`inProgressExerciseProvider` (Provider<Exercise?>: exercise đầu tiên có 0 < completed < số block).
Riverpod 3.4.3: family = class có constructor nhận arg + `build()` không tham số. Không dùng `StateProvider`/`FamilyNotifier` (legacy/đã bỏ).

## Routes (T-06)
`/` Home · `/theme/:themeId` · `/topic/:topicId` · `/exercise/:exerciseId` (Block list) · `/exercise/:exerciseId/block/:index` (Cell).
T-05 điều hướng bằng `context.push('/theme/rag')` v.v. — chuỗi path đúng như trên.
