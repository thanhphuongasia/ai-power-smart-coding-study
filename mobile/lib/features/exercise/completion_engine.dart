/// Gợi ý từ cho editor Python trên điện thoại.
///
/// Thuần Dart, không phụ thuộc Flutter hay models: nhận text trước con trỏ,
/// trả danh sách gợi ý đã xếp hạng để thanh gợi ý hiển thị.
library;

enum SuggestionKind { known, vocab, keyword }

class Suggestion {
  final String label;
  final String insertText;
  final SuggestionKind kind;

  const Suggestion({
    required this.label,
    required this.insertText,
    required this.kind,
  });

  @override
  bool operator ==(Object other) =>
      other is Suggestion &&
      other.label == label &&
      other.insertText == insertText &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(label, insertText, kind);

  @override
  String toString() => 'Suggestion($label, $insertText, ${kind.name})';
}

/// Keyword + builtin Python người học cần trong các block ngắn.
const List<String> _keywords = [
  'def', 'return', 'for', 'in', 'if', 'elif', 'else', 'while', 'range',
  'len', 'append', 'print', 'True', 'False', 'None', 'and', 'or', 'not',
];

/// Gọi hàm → chèn kèm `(`; widget tự thêm `)` và đặt con trỏ ở giữa.
const Set<String> _callables = {'range', 'len', 'print', 'append'};

/// Keyword luôn có gì đó đứng sau → chèn kèm dấu cách để gõ tiếp ngay.
const Set<String> _spaceAfter = {
  'def', 'return', 'for', 'in', 'if', 'elif', 'while', 'and', 'or', 'not',
};

final RegExp _wordBeforeCursor = RegExp(r'[A-Za-z0-9_]+$');
final RegExp _endsWithFor = RegExp(r'(^|[^A-Za-z0-9_])for $');
final RegExp _endsWithForVar = RegExp(r'(^|[^A-Za-z0-9_])for [A-Za-z_]\w* $');
final RegExp _endsWithIn = RegExp(r'(^|[^A-Za-z0-9_])in $');

String _insertTextFor(String label) {
  if (_callables.contains(label)) return '$label(';
  if (_spaceAfter.contains(label)) return '$label ';
  if (label == 'else') return 'else:';
  return label;
}

List<Suggestion> suggest({
  required String textBeforeCursor,
  required List<String> knownIdentifiers,
  required List<String> vocab,
  int limit = 8,
}) {
  if (limit <= 0) return const [];

  final lineStart = textBeforeCursor.lastIndexOf('\n') + 1;
  final line = textBeforeCursor.substring(lineStart);

  // Trong chuỗi đang mở ('abc|) thì gợi ý tên biến chỉ gây nhiễu.
  if (_insideString(line)) return const [];

  final word = _wordBeforeCursor.firstMatch(line)?.group(0) ?? '';

  final result = word.isEmpty
      ? _contextual(line, knownIdentifiers, vocab)
      : _byPrefix(word, knownIdentifiers, vocab);

  return result.length > limit ? result.sublist(0, limit) : result;
}

/// Chưa gõ chữ nào: đoán bước tiếp theo từ phần đầu dòng.
List<Suggestion> _contextual(
  String line,
  List<String> known,
  List<String> vocab,
) {
  final out = _Collector();

  if (_endsWithFor.hasMatch(line)) {
    out.add('i', SuggestionKind.known);
    out.addAll(known, SuggestionKind.known);
  } else if (_endsWithForVar.hasMatch(line)) {
    out.add('in', SuggestionKind.keyword);
  } else if (_endsWithIn.hasMatch(line)) {
    out.add('range', SuggestionKind.keyword);
    out.addAll(known, SuggestionKind.known);
  } else if (line.trim().isEmpty) {
    out.addAll(known, SuggestionKind.known);
    out.addAll(const ['for', 'return', 'if'], SuggestionKind.keyword);
  } else if (line.endsWith('.')) {
    // Sau dấu chấm là method: vocab của block (vd `append`) có ích hơn tên biến.
    out.addAll(vocab, SuggestionKind.vocab);
  } else {
    // Sau `(`, `, `, `[`, `= `, `+ `... thường là tên biến đã có.
    out.addAll(known, SuggestionKind.known);
    out.addAll(vocab, SuggestionKind.vocab);
  }
  return out.items;
}

/// Đang gõ dở một từ: lọc theo tiền tố, known > vocab > keyword.
List<Suggestion> _byPrefix(
  String word,
  List<String> known,
  List<String> vocab,
) {
  final lower = word.toLowerCase();
  bool matches(String c) =>
      c != word && c.toLowerCase().startsWith(lower);

  final groups = <SuggestionKind, List<String>>{
    SuggestionKind.known: known,
    SuggestionKind.vocab: vocab,
    SuggestionKind.keyword: _keywords,
  };

  final out = _Collector();
  for (final entry in groups.entries) {
    final hits = entry.value.where(matches).toList();
    final order = {for (var i = hits.length - 1; i >= 0; i--) hits[i]: i};
    hits.sort((a, b) {
      final aCase = a.startsWith(word) ? 0 : 1;
      final bCase = b.startsWith(word) ? 0 : 1;
      if (aCase != bCase) return aCase - bCase;
      if (a.length != b.length) return a.length - b.length;
      return order[a]! - order[b]!; // List.sort không ổn định → giữ thứ tự gốc.
    });
    out.addAll(hits, entry.key);
  }
  return out.items;
}

/// Đếm nháy chưa đóng trên dòng hiện tại (bỏ qua ký tự đã escape).
bool _insideString(String line) {
  String? open;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (open != null) {
      if (c == r'\') {
        i++;
      } else if (c == open) {
        open = null;
      }
    } else if (c == '"' || c == "'") {
      open = c;
    } else if (c == '#') {
      return true; // comment: cũng không gợi ý
    }
  }
  return open != null;
}

class _Collector {
  final items = <Suggestion>[];
  final _seen = <String>{};

  void add(String label, SuggestionKind kind) {
    if (label.isEmpty || !_seen.add(label)) return;
    items.add(Suggestion(
      label: label,
      insertText: _insertTextFor(label),
      kind: kind,
    ));
  }

  void addAll(Iterable<String> labels, SuggestionKind kind) {
    for (final l in labels) {
      add(l, kind);
    }
  }
}
