# Hợp đồng dùng chung giữa các task (đọc kèm contract từng task)

## Lời giải tham chiếu 5 bài (khớp từng ký tự; nối bằng "\n", KHÔNG có newline cuối, thụt 4 space)

split-chunks (function `split_chunks`):
```python
def split_chunks(text, size):
    chunks = []
    for i in range(0, len(text), size):
        chunks.append(text[i:i + size])
    return chunks
```
overlap-chunks (`overlap_chunks`):
```python
def overlap_chunks(text, size, overlap):
    chunks = []
    for i in range(0, len(text), size - overlap):
        chunks.append(text[i:i + size])
    return chunks
```
clean-text (`clean_text`):
```python
def clean_text(text):
    return text.strip()
```
save-document (`save_document`):
```python
def save_document(store, document):
    store.append(document)
```
like-post (`like_post`):
```python
def like_post(post):
    post["likes"] += 1
```

## Chia ô (template mobile) — dòng `# TODO X` thay cho code ô X
- split-chunks / overlap-chunks: khoá `def ...` + `    chunks = []`; ô A = dòng `for` (indent 1), ô B = `chunks.append(...)` (indent 2), ô C = `return chunks` (indent 1).
- clean-text, save-document, like-post: khoá dòng `def`; ô A = dòng thân hàm (indent 1).

## Hợp đồng HTTP `/run`
Xem PLAN.md mục "Hợp đồng `/run`". Không đổi tên field.

## Dart model (T-03 tạo, các task sau dùng)
```dart
class Example { final String caption; final String input; final String output; final String? note; }
class Challenge { final String statement; final String motivation; final Example small; final Example project; }
// Exercise THÊM: final String template; final Challenge challenge;
// Block THÊM: final String label;  // 'A','B','C'
//            final String explanation; // 1–2 câu giải thích lời giải (tab Solution)
// Giữ nguyên mọi field cũ (acceptedAnswers.first = lời giải ô).
```
`mobile/lib/domain/merge.dart`:
```dart
class MergedCode { final String code; final List<String?> lineOrigin; } // null = dòng khoá, 'A' = từ ô A
sealed class TemplateSegment {}            // để vẽ notebook
class LockedSegment extends TemplateSegment { final String code; }
class TodoSegment extends TemplateSegment { final Block block; }
List<TemplateSegment> templateSegments(Exercise exercise);
MergedCode mergeCells(Exercise exercise, Map<String, String> cellsByLabel);
// Ô: đổi tab→4 space, bỏ dòng trống đầu/cuối, dedent chung, rồi thêm thụt lề của dòng `# TODO X`.
```

## JudgeClient (T-04 tạo) — `mobile/lib/data/judge_client.dart`
```dart
enum JudgeStatus { passed, failed, error, timeout, unavailable }
class JudgeError { final String kind; final int? line; final String message; }
class JudgeTest { final String call; final String expected; final String? actual; final bool passed; }
class JudgeResult { final JudgeStatus status; final JudgeError? error; final List<JudgeTest> tests; final String stdout; final int durationMs; final String? unavailableReason; }
class JudgeClient { JudgeClient({http.Client? httpClient, Uri? baseUrl}); Future<JudgeResult> run(String exerciseId, String code); }
final judgeClientProvider = Provider<JudgeClient>((ref) => JudgeClient());
// baseUrl mặc định: Uri.parse(const String.fromEnvironment('JUDGE_URL', defaultValue: 'http://127.0.0.1:8000'))
```

## Progress (T-06 tạo)
- `ExerciseProgress`: `bool passed`, `Map<String,String> drafts` (key = block label), `Map<String,int> hintsUsed` (key = block label), `Set<String> solutionViewed` (block label). `completedBlocks` chỉ là suy ra từ `passed`.
- `ProgressController`: `markPassed(exerciseId)`, `saveDraft(exerciseId, label, code)`, `useHint(exerciseId, label)` (≤3), `viewSolution(exerciseId, label)`.
- "Đang làm dở" = `!passed && drafts có ít nhất 1 giá trị không rỗng`.
- `mobile/lib/domain/progression.dart`: `bool isExerciseUnlocked(String id, Set<String> passed)`, `Exercise? nextExerciseAfter(String id)` — theo thứ tự `CodeFile.exercises`, bài dùng chung mở nếu mở ở bất kỳ file nào.
