/// Ghép các ô TODO của học viên vào template khoá của bài.
library;

import 'models.dart';

class MergedCode {
  const MergedCode({required this.code, required this.lineOrigin});

  /// Code đầy đủ, nối bằng "\n", không newline cuối.
  final String code;

  /// Mỗi dòng của [code]: null = dòng khoá, 'A' = từ ô A.
  final List<String?> lineOrigin;
}

sealed class TemplateSegment {}

class LockedSegment extends TemplateSegment {
  LockedSegment(this.code);
  final String code;
}

class TodoSegment extends TemplateSegment {
  TodoSegment(this.block);
  final Block block;
}

final RegExp _markerPattern = RegExp(r'^(\s*)# TODO ([A-Z])\s*$');

/// Cắt template thành các đoạn khoá xen kẽ ô TODO, theo thứ tự xuất hiện.
/// Marker không có block tương ứng → [ArgumentError].
List<TemplateSegment> templateSegments(Exercise exercise) {
  final segments = <TemplateSegment>[];
  final locked = <String>[];
  for (final line in exercise.template.split('\n')) {
    final m = _markerPattern.firstMatch(line);
    if (m == null) {
      locked.add(line);
      continue;
    }
    if (locked.isNotEmpty) {
      segments.add(LockedSegment(locked.join('\n')));
      locked.clear();
    }
    final label = m.group(2)!;
    final block = exercise.blocks.where((b) => b.label == label).firstOrNull;
    if (block == null) {
      throw ArgumentError(
        'Template ${exercise.id} có marker $label nhưng '
        'không có block cùng nhãn',
      );
    }
    segments.add(TodoSegment(block));
  }
  if (locked.isNotEmpty) segments.add(LockedSegment(locked.join('\n')));
  return segments;
}

/// Chuẩn hoá một ô: tab → 4 space, bỏ dòng trống đầu/cuối, dedent chung.
List<String> _normalizeCell(String raw) {
  final lines = raw.replaceAll('\t', '    ').split('\n');
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  var common = -1;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (common < 0 || indent < common) common = indent;
  }
  if (common <= 0) return lines;
  return [
    for (final line in lines) line.trim().isEmpty ? '' : line.substring(common),
  ];
}

/// Ghép [cellsByLabel] vào template. Thiếu key của một ô → [ArgumentError].
MergedCode mergeCells(Exercise exercise, Map<String, String> cellsByLabel) {
  final code = <String>[];
  final origin = <String?>[];
  for (final line in exercise.template.split('\n')) {
    final m = _markerPattern.firstMatch(line);
    if (m == null) {
      code.add(line);
      origin.add(null);
      continue;
    }
    final label = m.group(2)!;
    final raw = cellsByLabel[label];
    if (raw == null) {
      throw ArgumentError('Thiếu nội dung ô $label');
    }
    final indent = m.group(1)!;
    for (final cellLine in _normalizeCell(raw)) {
      code.add(cellLine.isEmpty ? '' : '$indent$cellLine');
      origin.add(label);
    }
  }
  return MergedCode(code: code.join('\n'), lineOrigin: origin);
}

int _indentOf(String line) => line.length - line.trimLeft().length;

String _classifyHeader(String header, {required bool insideClass}) {
  final m = RegExp(
    r'^(async\s+def|def|class|for|while|if|elif|else|try|except|'
    r'finally|with)\b',
  ).firstMatch(header.trim());
  if (m == null) return '';
  switch (m.group(1)!) {
    case 'for':
      return 'trong vòng for';
    case 'while':
      return 'trong vòng while';
    case 'if' || 'elif' || 'else':
      return 'trong if';
    case 'try' || 'except' || 'finally':
      return 'trong try';
    case 'with':
      return 'trong with';
    case 'def' || 'async def':
      return insideClass ? 'trong method' : 'trong hàm';
    case 'class':
      return 'trong class';
  }
  return '';
}

/// Nhãn vị trí của ô [label] suy từ template: nhìn dòng cha gần nhất (thụt lề
/// nhỏ hơn). Cha là marker ô khác → dùng dòng đầu đáp án mẫu của ô đó.
/// Không xác định được → ''.
String cellLocation(Exercise exercise, String label) {
  final lines = exercise.template.replaceAll('\t', '    ').split('\n');
  final at = lines.indexWhere((l) {
    final m = _markerPattern.firstMatch(l);
    return m != null && m.group(2) == label;
  });
  if (at < 0) return '';
  final n = _indentOf(lines[at]);

  // Dòng không trống gần nhất phía trên có thụt lề < [indent], từ [from] lùi.
  int parentOf(int from, int indent) {
    for (var i = from - 1; i >= 0; i--) {
      if (lines[i].trim().isEmpty) continue;
      if (_indentOf(lines[i]) < indent) return i;
    }
    return -1;
  }

  final p = parentOf(at, n);
  if (p < 0) return '';
  var header = lines[p];
  var headerIdx = p;
  final pm = _markerPattern.firstMatch(header);
  if (pm != null) {
    final x = exercise.blocks.where((b) => b.label == pm.group(2)).firstOrNull;
    if (x == null || x.acceptedAnswers.isEmpty) return '';
    final first = x.acceptedAnswers.first
        .replaceAll('\t', '    ')
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    header = first;
    // def trong đáp án mẫu: không biết có nằm trong class, coi là hàm.
    headerIdx = -1;
  }
  var insideClass = false;
  if (headerIdx >= 0) {
    final c = parentOf(headerIdx, _indentOf(lines[headerIdx]));
    insideClass = c >= 0 && lines[c].trimLeft().startsWith('class ');
  }
  return _classifyHeader(header, insideClass: insideClass);
}
