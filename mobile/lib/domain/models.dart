/// Domain models cho nội dung học: Theme → Topic → File → Exercise → Block.
///
/// Không đặt tên `CodeTheme`/`Theme` để tránh trùng với `flutter_code_editor`
/// và `material.dart`.
library;

// ---- Helper đọc JSON: mọi sai lệch đều thành FormatException có tên field.

/// Đọc field bắt buộc kiểu [T] từ [json]; thiếu hoặc sai kiểu → FormatException.
T jsonField<T>(Map<String, dynamic> json, String key, String where) {
  final v = json[key];
  if (v is T) return v;
  throw FormatException(
    '$where: field "$key" ${v == null ? 'bị thiếu' : 'sai kiểu (${v.runtimeType}, cần $T)'}',
  );
}

/// Đọc field bắt buộc là mảng chuỗi.
List<String> jsonStrings(Map<String, dynamic> json, String key, String where) {
  final list = jsonField<List<dynamic>>(json, key, where);
  return [
    for (final e in list)
      if (e is String)
        e
      else
        throw FormatException('$where: "$key" chứa phần tử không phải chuỗi'),
  ];
}

/// Đọc field bắt buộc là mảng object.
List<Map<String, dynamic>> jsonObjects(
  Map<String, dynamic> json,
  String key,
  String where,
) {
  final list = jsonField<List<dynamic>>(json, key, where);
  return [
    for (final e in list)
      if (e is Map<String, dynamic>)
        e
      else
        throw FormatException('$where: "$key" chứa phần tử không phải object'),
  ];
}

class StudyTheme {
  const StudyTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.tags,
    required this.topics,
    this.diagram = const ClassDiagram(classes: [], relations: []),
  });

  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final List<Topic> topics;

  /// Sơ đồ lớp viết tay của dự án; rỗng nếu theme chưa có.
  final ClassDiagram diagram;

  /// Mọi topic/module (kể cả lồng nhau), preorder: cha trước con.
  Iterable<Topic> get allTopics sync* {
    for (final t in topics) {
      yield t;
      yield* t.allModules;
    }
  }

  /// Mọi file trong theme (kể cả trong module con), preorder.
  Iterable<CodeFile> get allFiles sync* {
    for (final t in allTopics) {
      yield* t.files;
    }
  }

  /// [exercises]: bài đã dựng sẵn theo id (để bài dùng chung là một instance).
  factory StudyTheme.fromJson(
    Map<String, dynamic> json,
    Map<String, Exercise> exercises,
  ) {
    const w = 'theme';
    return StudyTheme(
      id: jsonField<String>(json, 'id', w),
      name: jsonField<String>(json, 'name', w),
      description: jsonField<String>(json, 'description', w),
      tags: jsonStrings(json, 'tags', w),
      topics: [
        for (final t in jsonObjects(json, 'topics', w))
          Topic.fromJson(t, exercises),
      ],
      diagram: ClassDiagram.fromJson(
        jsonField<Map<String, dynamic>>(json, 'diagram', w),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'tags': tags,
    'topics': [for (final t in topics) t.toJson()],
    'diagram': diagram.toJson(),
  };
}

class DiagramAttribute {
  const DiagramAttribute({
    required this.name,
    required this.type,
    required this.group,
  });

  final String name;
  final String type;

  /// 'core' hoặc 'support'.
  final String group;

  factory DiagramAttribute.fromJson(Map<String, dynamic> json) {
    const w = 'diagram attribute';
    final group = jsonField<String>(json, 'group', w);
    if (group != 'core' && group != 'support') {
      throw FormatException('$w: "group" không hợp lệ: "$group"');
    }
    return DiagramAttribute(
      name: jsonField<String>(json, 'name', w),
      type: jsonField<String>(json, 'type', w),
      group: group,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'group': group};
}

class DiagramClass {
  const DiagramClass({
    required this.name,
    required this.file,
    required this.attributes,
    required this.methods,
  });

  final String name;
  final String file;
  final List<DiagramAttribute> attributes;
  final List<String> methods;

  factory DiagramClass.fromJson(Map<String, dynamic> json) {
    const w = 'diagram class';
    return DiagramClass(
      name: jsonField<String>(json, 'name', w),
      file: jsonField<String>(json, 'file', w),
      attributes: [
        for (final a in jsonObjects(json, 'attributes', w))
          DiagramAttribute.fromJson(a),
      ],
      methods: jsonStrings(json, 'methods', w),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'file': file,
    'attributes': [for (final a in attributes) a.toJson()],
    'methods': methods,
  };
}

const _relationKinds = {
  'association',
  'aggregation',
  'composition',
  'dependency',
};

class DiagramRelation {
  const DiagramRelation({
    required this.from,
    required this.to,
    required this.kind,
    required this.label,
    required this.via,
  });

  final String from;
  final String to;

  /// association | aggregation | composition | dependency.
  final String kind;
  final String label;

  /// Method của [from] tác động lên [to].
  final List<String> via;

  factory DiagramRelation.fromJson(Map<String, dynamic> json) {
    const w = 'diagram relation';
    final kind = jsonField<String>(json, 'kind', w);
    if (!_relationKinds.contains(kind)) {
      throw FormatException('$w: "kind" không hợp lệ: "$kind"');
    }
    return DiagramRelation(
      from: jsonField<String>(json, 'from', w),
      to: jsonField<String>(json, 'to', w),
      kind: kind,
      label: jsonField<String>(json, 'label', w),
      via: jsonStrings(json, 'via', w),
    );
  }

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'kind': kind,
    'label': label,
    'via': via,
  };
}

class ClassDiagram {
  const ClassDiagram({required this.classes, required this.relations});

  final List<DiagramClass> classes;
  final List<DiagramRelation> relations;

  bool get isEmpty => classes.isEmpty && relations.isEmpty;

  DiagramClass? classNamed(String name) {
    for (final c in classes) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Quan hệ có [className] ở đầu hoặc cuối, giữ thứ tự nguồn.
  List<DiagramRelation> relationsOf(String className) => [
    for (final r in relations)
      if (r.from == className || r.to == className) r,
  ];

  factory ClassDiagram.fromJson(Map<String, dynamic> json) {
    const w = 'diagram';
    return ClassDiagram(
      classes: [
        for (final c in jsonObjects(json, 'classes', w))
          DiagramClass.fromJson(c),
      ],
      relations: [
        for (final r in jsonObjects(json, 'relations', w))
          DiagramRelation.fromJson(r),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'classes': [for (final c in classes) c.toJson()],
    'relations': [for (final r in relations) r.toJson()],
  };
}

class Topic {
  const Topic({
    required this.id,
    required this.name,
    required this.description,
    required this.files,
    this.modules = const [],
  });

  final String id;
  final String name;
  final String description;
  final List<CodeFile> files;

  /// Module con (đệ quy), có thể rỗng.
  final List<Topic> modules;

  /// File của topic này, rồi file của từng module con (preorder).
  Iterable<CodeFile> get allFiles sync* {
    yield* files;
    for (final m in modules) {
      yield* m.allFiles;
    }
  }

  /// Mọi module con ở mọi độ sâu, preorder (không gồm chính topic này).
  Iterable<Topic> get allModules sync* {
    for (final m in modules) {
      yield m;
      yield* m.allModules;
    }
  }

  factory Topic.fromJson(
    Map<String, dynamic> json,
    Map<String, Exercise> exercises,
  ) {
    const w = 'topic';
    return Topic(
      id: jsonField<String>(json, 'id', w),
      name: jsonField<String>(json, 'name', w),
      description: jsonField<String>(json, 'description', w),
      files: [
        for (final f in jsonObjects(json, 'files', w))
          CodeFile.fromJson(f, exercises),
      ],
      modules: [
        for (final m in jsonObjects(json, 'modules', w))
          Topic.fromJson(m, exercises),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'files': [for (final f in files) f.toJson()],
    'modules': [for (final m in modules) m.toJson()],
  };
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

  /// `exercise_ids` → tra trong [exercises]; id lạ → FormatException.
  factory CodeFile.fromJson(
    Map<String, dynamic> json,
    Map<String, Exercise> exercises,
  ) {
    const w = 'file';
    final fileId = jsonField<String>(json, 'id', w);
    return CodeFile(
      id: fileId,
      name: jsonField<String>(json, 'name', w),
      exercises: [
        for (final id in jsonStrings(json, 'exercise_ids', w))
          exercises[id] ??
              (throw FormatException(
                'file "$fileId" trỏ tới exercise không tồn tại: "$id"',
              )),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'exercise_ids': [for (final e in exercises) e.id],
  };
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

  factory Example.fromJson(Map<String, dynamic> json) {
    const w = 'example';
    final note = json['note'];
    if (note != null && note is! String) {
      throw const FormatException('example: field "note" sai kiểu');
    }
    return Example(
      caption: jsonField<String>(json, 'caption', w),
      input: jsonField<String>(json, 'input', w),
      output: jsonField<String>(json, 'output', w),
      note: note as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'caption': caption,
    'input': input,
    'output': output,
    'note': note,
  };
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

  factory Challenge.fromJson(Map<String, dynamic> json) {
    const w = 'challenge';
    return Challenge(
      statement: jsonField<String>(json, 'statement', w),
      motivation: jsonField<String>(json, 'motivation', w),
      small: Example.fromJson(
        jsonField<Map<String, dynamic>>(json, 'small', w),
      ),
      project: Example.fromJson(
        jsonField<Map<String, dynamic>>(json, 'project', w),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'statement': statement,
    'motivation': motivation,
    'small': small.toJson(),
    'project': project.toJson(),
  };
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
    this.className,
  });

  final String id;

  /// Vd: 'Text chunking'.
  final String title;

  /// Vd: 'split_chunks'.
  final String functionName;

  /// Lớp chứa method, vd 'FlightService'; null nếu là hàm tự do.
  final String? className;

  /// 'FlightService.book' nếu có lớp, ngược lại chỉ tên hàm.
  String get qualifiedName =>
      className != null ? '$className.$functionName' : functionName;

  /// Vd: ['text', 'size'].
  final List<String> params;
  final List<Block> blocks;

  /// Code khoá của hàm; mỗi ô TODO là một dòng `# TODO A` (thụt lề đúng chỗ).
  final String template;
  final Challenge challenge;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    const w = 'exercise';
    if (!json.containsKey('class_name')) {
      throw const FormatException('exercise: field "class_name" bị thiếu');
    }
    final className = json['class_name'];
    if (className != null && className is! String) {
      throw const FormatException('exercise: field "class_name" sai kiểu');
    }
    return Exercise(
      id: jsonField<String>(json, 'id', w),
      title: jsonField<String>(json, 'title', w),
      functionName: jsonField<String>(json, 'function_name', w),
      className: className as String?,
      params: jsonStrings(json, 'params', w),
      template: jsonField<String>(json, 'template', w),
      challenge: Challenge.fromJson(
        jsonField<Map<String, dynamic>>(json, 'challenge', w),
      ),
      blocks: [
        for (final b in jsonObjects(json, 'blocks', w)) Block.fromJson(b),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'function_name': functionName,
    'class_name': className,
    'params': params,
    'template': template,
    'challenge': challenge.toJson(),
    'blocks': [for (final b in blocks) b.toJson()],
  };
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

  factory Block.fromJson(Map<String, dynamic> json) {
    const w = 'block';
    return Block(
      id: jsonField<String>(json, 'id', w),
      label: jsonField<String>(json, 'label', w),
      title: jsonField<String>(json, 'title', w),
      prompt: jsonField<String>(json, 'prompt', w),
      indentLevel: jsonField<int>(json, 'indent_level', w),
      acceptedAnswers: jsonStrings(json, 'accepted_answers', w),
      expectedOutput: jsonField<String>(json, 'expected_output', w),
      explanation: jsonField<String>(json, 'explanation', w),
      hints: jsonStrings(json, 'hints', w),
      vocab: jsonStrings(json, 'vocab', w),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'title': title,
    'prompt': prompt,
    'indent_level': indentLevel,
    'accepted_answers': acceptedAnswers,
    'expected_output': expectedOutput,
    'explanation': explanation,
    'hints': hints,
    'vocab': vocab,
  };
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
