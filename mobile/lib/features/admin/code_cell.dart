import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

enum CodeLanguage { python, json }

enum CodeSpanKind { comment, string, keyword, todo, number, key }

/// Một đoạn đã nhận diện trong [start, end). Đoạn không có trong danh sách
/// là chữ thường (không tô màu).
class CodeSpan {
  const CodeSpan(this.start, this.end, this.kind);

  final int start;
  final int end;
  final CodeSpanKind kind;

  @override
  bool operator ==(Object other) =>
      other is CodeSpan &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);

  @override
  String toString() => 'CodeSpan($start, $end, ${kind.name})';
}

const _pythonKeywords = {
  'class', 'def', 'self', 'return', 'if', 'else', 'elif', 'for', 'in',
  'import', 'from', 'while', 'None', 'True', 'False',
};

const _jsonKeywords = {'true', 'false', 'null'};

final _todoComment = RegExp(r'^#\s*TODO\b');

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x5f;
bool _isIdentPart(int c) => _isIdentStart(c) || _isDigit(c);

/// Quét [text], trả các đoạn cần tô màu theo thứ tự, không chồng nhau.
/// Hàm thuần, không phụ thuộc Flutter — dễ test.
List<CodeSpan> tokenize(String text, CodeLanguage language) {
  final spans = <CodeSpan>[];
  final isPython = language == CodeLanguage.python;
  final keywords = isPython ? _pythonKeywords : _jsonKeywords;
  final n = text.length;
  var i = 0;

  int lineEnd(int from) {
    final nl = text.indexOf('\n', from);
    return nl == -1 ? n : nl;
  }

  while (i < n) {
    final c = text.codeUnitAt(i);
    if (isPython && c == 0x23) {
      // '#'
      final end = lineEnd(i);
      final kind = _todoComment.hasMatch(text.substring(i, end))
          ? CodeSpanKind.todo
          : CodeSpanKind.comment;
      spans.add(CodeSpan(i, end, kind));
      i = end;
    } else if (c == 0x22 || (isPython && c == 0x27)) {
      // chuỗi "..." hoặc '...' trên một dòng; thiếu dấu đóng thì tới hết dòng
      final eol = lineEnd(i);
      var j = i + 1;
      var closed = false;
      while (j < eol) {
        final d = text.codeUnitAt(j);
        if (d == 0x5c) {
          j += 2; // bỏ qua ký tự bị escape
          continue;
        }
        if (d == c) {
          closed = true;
          j++;
          break;
        }
        j++;
      }
      final end = closed ? j : eol;
      var kind = CodeSpanKind.string;
      if (!isPython && closed) {
        var k = end;
        while (k < n && (text[k] == ' ' || text[k] == '\t')) {
          k++;
        }
        if (k < n && text[k] == ':') kind = CodeSpanKind.key;
      }
      spans.add(CodeSpan(i, end, kind));
      i = end;
    } else if (_isIdentStart(c)) {
      var j = i + 1;
      while (j < n && _isIdentPart(text.codeUnitAt(j))) {
        j++;
      }
      if (keywords.contains(text.substring(i, j))) {
        spans.add(CodeSpan(i, j, CodeSpanKind.keyword));
      }
      i = j;
    } else if (_isDigit(c) ||
        (!isPython && c == 0x2d && i + 1 < n && _isDigit(text.codeUnitAt(i + 1)))) {
      var j = i + 1;
      while (j < n) {
        final d = text.codeUnitAt(j);
        final expSign = (d == 0x2b || d == 0x2d) &&
            (text[j - 1] == 'e' || text[j - 1] == 'E');
        if (_isDigit(d) || d == 0x2e || d == 0x65 || d == 0x45 || expSign) {
          j++;
        } else {
          break;
        }
      }
      spans.add(CodeSpan(i, j, CodeSpanKind.number));
      i = j;
    } else {
      i++;
    }
  }
  return spans;
}

/// Controller tô màu cú pháp. Chuỗi hiển thị giữ nguyên `text`
/// (`toPlainText() == text`), chỉ đổi style từng đoạn.
class HighlightingController extends TextEditingController {
  HighlightingController({super.text, required this.language});

  final CodeLanguage language;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Đang gõ IME (composing) thì để mặc định để gạch chân đúng chỗ.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final p = context.palette;
    final src = text;
    final children = <InlineSpan>[];
    var pos = 0;
    for (final s in tokenize(src, language)) {
      if (s.start > pos) {
        children.add(TextSpan(text: src.substring(pos, s.start)));
      }
      children.add(TextSpan(
        text: src.substring(s.start, s.end),
        style: _styleFor(s.kind, p),
      ));
      pos = s.end;
    }
    if (pos < src.length) {
      children.add(TextSpan(text: src.substring(pos)));
    }
    return TextSpan(style: style, children: children);
  }

  TextStyle _styleFor(CodeSpanKind kind, AppPalette p) {
    switch (kind) {
      case CodeSpanKind.comment:
        return TextStyle(color: p.inkMuted, fontStyle: FontStyle.italic);
      case CodeSpanKind.string:
        return TextStyle(color: p.accent);
      case CodeSpanKind.keyword:
      case CodeSpanKind.key:
        return TextStyle(color: p.primary);
      case CodeSpanKind.number:
        return TextStyle(color: p.accent);
      case CodeSpanKind.todo:
        return TextStyle(
          color: p.ink,
          backgroundColor: p.accent.withValues(alpha: 0.25),
          fontWeight: FontWeight.w600,
        );
    }
  }
}

int _lineCount(String text) => text.isEmpty ? 1 : text.split('\n').length;

/// Ô code kiểu Jupyter: gutter số dòng, thanh công cụ, footer "N dòng".
///
/// [key] được gắn vào chính `TextField` (không phải CodeCell) để test cũ
/// `find.byKey` + `enterText` / đọc `TextField.controller` vẫn chạy.
/// Muốn tô màu, truyền [HighlightingController]; controller thường vẫn
/// hoạt động nhưng không có màu.
class CodeCell extends StatefulWidget {
  const CodeCell({
    Key? key,
    required this.controller,
    required this.language,
    this.label,
    this.errorText,
    this.readOnly = false,
    this.onChanged,
    this.minLines = 3,
  })  : fieldKey = key,
        super(key: null);

  final Key? fieldKey;
  final TextEditingController controller;
  final CodeLanguage language;
  final String? label;
  final String? errorText;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final int minLines;

  @override
  State<CodeCell> createState() => _CodeCellState();
}

class _CodeCellState extends State<CodeCell> {
  static const double _gutterWidth = 40;
  static const double _charWidth = 8.6; // JetBrains Mono 14px
  static const double _maxEditorHeight = 340;

  bool _collapsed = false;
  bool _focused = false;
  String? _copiedText;

  String get _langLabel =>
      widget.language == CodeLanguage.python ? 'python' : 'json';

  Future<void> _copy() async {
    final text = widget.controller.text;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copiedText = text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final err = widget.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s1),
            child: Text(
              widget.label!,
              style: AppText.label.copyWith(color: p.inkMuted),
            ),
          ),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: err != null
                    ? p.danger
                    : (_focused ? p.primary : p.outline),
              ),
            ),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toolbar(p),
                  if (!_collapsed) _editor(p),
                  if (!_collapsed) _footer(p),
                ],
              ),
            ),
          ),
        ),
        if (err != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s1),
            child: Text(err, style: AppText.caption.copyWith(color: p.danger)),
          ),
      ],
    );
  }

  Widget _toolbar(AppPalette p) {
    final copied = _copiedText == widget.controller.text;
    final btnStyle = TextButton.styleFrom(
      foregroundColor: p.inkMuted,
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2),
      textStyle: AppText.caption,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s2,
        vertical: AppSpace.s1,
      ),
      decoration: BoxDecoration(
        border: _collapsed
            ? null
            : Border(bottom: BorderSide(color: p.outline.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              border: Border.all(color: p.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _langLabel,
              key: const Key('code-cell-lang'),
              style: AppText.caption.copyWith(
                fontFamily: kMonoFamily,
                color: p.inkMuted,
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            key: const Key('code-cell-copy'),
            style: btnStyle,
            onPressed: _copy,
            child: Text(copied ? 'Đã chép' : 'Chép'),
          ),
          TextButton(
            key: const Key('code-cell-fold'),
            style: btnStyle,
            onPressed: () => setState(() => _collapsed = !_collapsed),
            child: Text(_collapsed ? 'Mở rộng' : 'Thu gọn'),
          ),
        ],
      ),
    );
  }

  Widget _editor(AppPalette p) {
    final text = widget.controller.text;
    final lines = _lineCount(text);
    final shown = lines < widget.minLines ? widget.minLines : lines;
    // Gutter cao bằng editor: dòng thừa (do minLines) để trống.
    final gutterText = [
      for (var i = 1; i <= shown; i++) i <= lines ? '$i' : ' ',
    ].join('\n');
    var longest = 0;
    for (final l in text.split('\n')) {
      if (l.length > longest) longest = l.length;
    }
    final codeStyle = AppText.code.copyWith(color: p.ink);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxEditorHeight),
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const Key('code-cell-gutter'),
              width: _gutterWidth,
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              decoration: BoxDecoration(
                color: p.surfaceRaised,
                border: Border(right: BorderSide(color: p.outline.withValues(alpha: 0.5))),
              ),
              child: Text(
                gutterText,
                textAlign: TextAlign.right,
                style: codeStyle.copyWith(color: p.inkMuted),
              ),
            ),
            Expanded(
              // Không xuống dòng tự động: mỗi dòng code = một dòng số, cuộn ngang.
              child: LayoutBuilder(
                builder: (context, c) {
                  final want = longest * _charWidth + 28;
                  final width = want > c.maxWidth ? want : c.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: TextField(
                        key: widget.fieldKey,
                        controller: widget.controller,
                        readOnly: widget.readOnly,
                        onChanged: widget.onChanged,
                        minLines: widget.minLines,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: codeStyle,
                        cursorColor: p.ink,
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(AppPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpace.s1),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.outline.withValues(alpha: 0.5))),
      ),
      child: Text(
        '${_lineCount(widget.controller.text)} dòng',
        key: const Key('code-cell-count'),
        style: AppText.caption.copyWith(
          fontFamily: kMonoFamily,
          color: p.inkMuted,
        ),
      ),
    );
  }
}
