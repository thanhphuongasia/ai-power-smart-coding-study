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

class Exercise {
  const Exercise({
    required this.id,
    required this.title,
    required this.functionName,
    required this.params,
    required this.blocks,
  });

  final String id;

  /// Vd: 'Text chunking'.
  final String title;

  /// Vd: 'split_chunks'.
  final String functionName;

  /// Vd: ['text', 'size'].
  final List<String> params;
  final List<Block> blocks;
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
  });

  final String id;
  final String title;
  final String prompt;

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
