/// Domain models cho nội dung học: Theme → Topic → File → Exercise → Block.
///
/// Không đặt tên `CodeTheme`/`Theme` để tránh trùng với `flutter_code_editor`
/// và `material.dart`.
library;

class StudyTheme {
  const StudyTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.tags,
    required this.topics,
  });

  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final List<Topic> topics;
}

class Topic {
  const Topic({
    required this.id,
    required this.name,
    required this.description,
    required this.files,
  });

  final String id;
  final String name;
  final String description;
  final List<CodeFile> files;
}

class CodeFile {
  const CodeFile({
    required this.id,
    required this.name,
    required this.exercises,
  });

  final String id;

  /// Vd: 'chunker.py'.
  final String name;
  final List<Exercise> exercises;
}

/// Một ví dụ minh hoạ trong tab Challenge: code gọi hàm + kết quả thật.
class Example {
  const Example({
    required this.caption,
    required this.input,
    required this.output,
    this.note,
  });

  final String caption;

  /// Code Python gọi hàm, vd `split_chunks("hello world", 4)`.
  final String input;

  /// Kết quả in ra khi chạy `input` (lấy bằng cách chạy python3 thật).
  final String output;
  final String? note;
}

/// Nội dung tab Challenge của một bài.
class Challenge {
  const Challenge({
    required this.statement,
    required this.motivation,
    required this.small,
    required this.project,
  });

  /// Đề bài, 1–2 câu.
  final String statement;

  /// Vì sao cần hàm này ngoài đời thật.
  final String motivation;

  /// Ví dụ nhỏ, dễ nhẩm.
  final Example small;

  /// Ví dụ trong bối cảnh dự án thật.
  final Example project;
}

const Challenge emptyChallenge = Challenge(
  statement: '',
  motivation: '',
  small: Example(caption: '', input: '', output: ''),
  project: Example(caption: '', input: '', output: ''),
);

class Exercise {
  const Exercise({
    required this.id,
    required this.title,
    required this.functionName,
    required this.params,
    required this.blocks,
    this.template = '',
    this.challenge = emptyChallenge,
  });

  final String id;

  /// Vd: 'Text chunking'.
  final String title;

  /// Vd: 'split_chunks'.
  final String functionName;

  /// Vd: ['text', 'size'].
  final List<String> params;
  final List<Block> blocks;

  /// Code khoá của hàm; mỗi ô TODO là một dòng `# TODO A` (thụt lề đúng chỗ).
  final String template;
  final Challenge challenge;
}

class Block {
  const Block({
    required this.id,
    required this.title,
    required this.prompt,
    required this.indentLevel,
    required this.acceptedAnswers,
    required this.expectedOutput,
    required this.hints,
    required this.vocab,
    this.label = '',
    this.explanation = '',
  });

  final String id;
  final String title;
  final String prompt;

  /// Nhãn ô trong template: 'A', 'B', 'C'.
  final String label;

  /// 1–2 câu giải thích lời giải (tab Solution).
  final String explanation;

  /// Số lần thụt 4 space của block trong hàm: def=0, thân hàm=1, thân for=2.
  final int indentLevel;

  /// Viết KHÔNG kèm thụt nền; dòng 2 trong block có thể thụt thêm 4 so với
  /// dòng 1.
  final List<String> acceptedAnswers;

  /// Hiện khi Run đúng.
  final String expectedOutput;

  /// Đúng 3, mờ → rõ.
  final List<String> hints;

  /// Từ gợi ý riêng cho block, vd ['range', 'len', 'append'].
  final List<String> vocab;
}

/// Loại nội dung do Claude (qua MCP) sinh ra, chờ admin duyệt.
enum ContentKind { exercise, theme }

enum ApprovalStatus { pending, approved, rejected }

class PendingContent {
  const PendingContent({
    required this.id,
    required this.kind,
    required this.title,
    required this.target,
    required this.description,
    required this.tags,
    required this.size,
    this.hintPreview,
    this.status = ApprovalStatus.pending,
  });

  final String id;
  final ContentKind kind;
  final String title;

  /// Theme đích (với exercise) hoặc 'Theme mới'.
  final String target;
  final String description;
  final List<String> tags;

  /// Vd: '5 block' hoặc '6 bài tập'.
  final String size;

  /// Hint mức 1 để admin kiểm tra độ "mờ" trước khi duyệt.
  final String? hintPreview;
  final ApprovalStatus status;

  PendingContent copyWith({ApprovalStatus? status}) {
    return PendingContent(
      id: id,
      kind: kind,
      title: title,
      target: target,
      description: description,
      tags: tags,
      size: size,
      hintPreview: hintPreview,
      status: status ?? this.status,
    );
  }
}
