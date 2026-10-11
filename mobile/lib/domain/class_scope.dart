/// Phần sơ đồ lớp thuộc về một bài: lớp, method, và các attribute method đó
/// đụng tới (để tô sáng trên sơ đồ).
library;

import 'merge.dart';
import 'models.dart';

class ClassScope {
  const ClassScope({
    required this.className,
    required this.method,
    required this.attributes,
  });

  final String className;
  final String method;

  /// Tên các `self.<name>` không phải lời gọi method.
  final Set<String> attributes;
}

int _indentOf(String line) => line.length - line.trimLeft().length;

final RegExp _selfAttr = RegExp(r'\bself\.([A-Za-z_]\w*)(?!\w)(?!\s*\()');

/// null nếu [e] là hàm tự do (không có lớp).
ClassScope? classScope(Exercise e) {
  final className = e.className;
  if (className == null) return null;
  final merged = mergeCells(e, {
    for (final b in e.blocks) b.label: b.acceptedAnswers.first,
  });
  final lines = merged.code.replaceAll('\t', '    ').split('\n');
  final defRe = RegExp(
    '^\\s*(async\\s+)?def\\s+${RegExp.escape(e.functionName)}\\(',
  );
  final start = lines.indexWhere(defRe.hasMatch);
  final attrs = <String>{};
  if (start >= 0) {
    final defIndent = _indentOf(lines[start]);
    for (var i = start + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (_indentOf(line) <= defIndent) break;
      for (final m in _selfAttr.allMatches(line)) {
        attrs.add(m.group(1)!);
      }
    }
  }
  return ClassScope(
    className: className,
    method: e.functionName,
    attributes: attrs,
  );
}
