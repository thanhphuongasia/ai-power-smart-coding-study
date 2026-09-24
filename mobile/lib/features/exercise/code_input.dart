import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';

import 'completion_engine.dart';

const _mono = 'JetBrains Mono';
const _barHeight = 48.0;
const _keyHeight = 40.0;
const _tab = '    ';
const _borderRadius = 12.0;
const _placeholder = 'Nhập code';

/// Phím ký hiệu, theo thứ tự hay dùng. Tab tách riêng vì chèn 4 space.
const List<String> _symbols = ['(', ')', '[', ']', ':', '=', '.', ',', '"'];

/// Editor code cho điện thoại: editor ở trên, thanh gợi ý + hàng phím ký hiệu
/// ngay dưới (tức là nằm sát trên bàn phím ảo).
class CodeInput extends StatefulWidget {
  const CodeInput({
    super.key,
    required this.initialCode,
    required this.knownIdentifiers,
    required this.vocab,
    required this.onChanged,
    this.onActivity,
    this.focusNode,
  });

  final String initialCode;
  final List<String> knownIdentifiers;
  final List<String> vocab;
  final ValueChanged<String> onChanged;
  final VoidCallback? onActivity;
  final FocusNode? focusNode;

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  late final _PythonCodeController _controller;
  FocusNode? _ownFocus;
  late FocusNode _focus;
  late TextEditingValue _last;
  bool _silent = false;

  @override
  void initState() {
    super.initState();
    _controller = _PythonCodeController(text: widget.initialCode);
    _last = _controller.value;
    _controller.addListener(_onControllerChanged);
    // CodeField gắn focusNode trong initState của nó, nên chốt một lần ở đây.
    _focus = widget.focusNode ?? (_ownFocus = FocusNode());
  }

  @override
  void didUpdateWidget(CodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent tái dùng widget cho block khác mà không đổi key → nạp code mới.
    // Nếu parent chỉ trả lại đúng bản nháp đang gõ thì text trùng, không reset.
    if (widget.initialCode != oldWidget.initialCode &&
        widget.initialCode != _controller.fullText) {
      _silent = true;
      _controller.fullText = widget.initialCode;
      _last = _controller.value;
      _silent = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final v = _controller.value;
    // Controller còn notify khi phân tích/tìm kiếm xong: bỏ qua nếu không đổi gì.
    final textChanged = v.text != _last.text;
    if (!textChanged && v.selection == _last.selection) return;
    _last = v;
    if (_silent) return;
    if (textChanged) widget.onChanged(v.text);
    widget.onActivity?.call();
    setState(() {});
  }

  /// Vị trí con trỏ hợp lệ; editor chưa từng focus thì coi như ở cuối.
  TextSelection get _selection {
    final sel = _controller.selection;
    return sel.isValid
        ? sel
        : TextSelection.collapsed(offset: _controller.text.length);
  }

  void _keepKeyboard() {
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _insertSymbol(String s) {
    HapticFeedback.selectionClick();
    final sel = _selection;
    if (!_controller.selection.isValid) _controller.selection = sel;
    // Chèn đúng 1 ký tự tại con trỏ → modifier (tự đóng ngoặc, overtype)
    // chạy y như gõ tay.
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(sel.start, sel.end, s),
      selection: TextSelection.collapsed(offset: sel.start + s.length),
    );
    _keepKeyboard();
  }

  void _applySuggestion(Suggestion s) {
    HapticFeedback.selectionClick();
    final text = _controller.text;
    final sel = _selection;

    var start = sel.start;
    var end = sel.end;
    if (sel.isCollapsed) {
      while (start > 0 && _isWordChar(text[start - 1])) {
        start--;
      }
      // Chỉ nuốt phần đuôi của từ khi đang gõ dở từ đó; chưa gõ gì (gợi ý
      // ngữ cảnh) mà con trỏ đứng trước một từ thì chỉ chèn, không ghi đè.
      if (start < sel.start) {
        while (end < text.length && _isWordChar(text[end])) {
          end++;
        }
      }
    }

    final next = end < text.length ? text[end] : '';
    var insert = s.insertText;
    int caret;
    if (insert.endsWith('(')) {
      if (next == '(') {
        // `ran|(0, 5)` → dùng lại `(` sẵn có thay vì ra `range()(0, 5)`.
        insert = insert.substring(0, insert.length - 1);
        caret = start + insert.length + 1;
      } else {
        insert = '$insert)';
        caret = start + insert.length - 1;
      }
    } else if (insert.endsWith(' ') && next == ' ') {
      insert = insert.substring(0, insert.length - 1);
      caret = start + insert.length + 1;
    } else {
      caret = start + insert.length;
    }

    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: caret),
    );
    _keepKeyboard();
  }

  List<Suggestion> _currentSuggestions() {
    final sel = _selection;
    if (!sel.isCollapsed) return const [];
    return suggest(
      textBeforeCursor: _controller.text.substring(0, sel.start),
      knownIdentifiers: widget.knownIdentifiers,
      vocab: widget.vocab,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, constraints) {
      final bounded = constraints.maxHeight.isFinite;
      final codeField = CodeTheme(
        data: CodeThemeData(styles: _codeStyles(scheme)),
        child: CodeField(
          key: const Key('code-input-field'),
          controller: _controller,
          focusNode: _focus,
          expands: bounded,
          minLines: bounded ? null : 3,
          gutterStyle: GutterStyle.none,
          background: scheme.surfaceContainer,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle:
              const TextStyle(fontFamily: _mono, fontSize: 16, height: 1.5),
        ),
      );

      // Lớp hiển thị thuần tuý, không đụng controller (INV-04) — chỉ đọc
      // text để quyết định hiện/ẩn, không bao giờ ghi lại.
      final showPlaceholder = _controller.text.isEmpty;
      final stacked = Stack(
        children: [
          codeField,
          if (showPlaceholder)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                child: Text(
                  _placeholder,
                  style: TextStyle(
                    fontFamily: _mono,
                    fontSize: 16,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      );

      // Viền phản ứng theo focus; Container tự bù padding bằng đúng độ dày
      // viền (1↔2px) nên kích thước tổng thể không đổi khi focus/blur.
      final field = AnimatedBuilder(
        animation: _focus,
        child: stacked,
        builder: (context, child) {
          final focused = _focus.hasFocus;
          return Container(
            key: const Key('code-input-border'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(
                color: focused ? scheme.primary : scheme.outline,
                width: focused ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(_borderRadius),
            ),
            child: child,
          );
        },
      );

      return Column(
        mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bounded) Expanded(child: field) else field,
          // Chạm vào 2 hàng này được tính là "bên trong" ô nhập → không mất
          // focus, bàn phím không sụp.
          TextFieldTapRegion(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                border: Border(top: BorderSide(color: scheme.outline)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Bar(children: [
                    for (final (i, s) in _currentSuggestions().indexed)
                      _Key(
                        key: Key('suggestion-${s.label}'),
                        label: s.insertText.endsWith('(')
                            ? '${s.label}()'
                            : s.label,
                        color: switch (s.kind) {
                          SuggestionKind.known => scheme.primary,
                          SuggestionKind.vocab => scheme.onSurface,
                          SuggestionKind.keyword => scheme.onSurfaceVariant,
                        },
                        borderColor: i == 0 ? scheme.primary : scheme.outline,
                        onTap: () => _applySuggestion(s),
                      ),
                  ]),
                  _Bar(children: [
                    for (final c in _symbols)
                      _Key(
                        key: Key('symbol-$c'),
                        label: c,
                        color: scheme.onSurface,
                        borderColor: scheme.outline,
                        minWidth: 44,
                        onTap: () => _insertSymbol(c),
                      ),
                    _Key(
                      key: const Key('symbol-tab'),
                      label: 'Tab',
                      color: scheme.onSurfaceVariant,
                      borderColor: scheme.outline,
                      minWidth: 56,
                      onTap: () => _insertSymbol(_tab),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

bool _isWordChar(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 48 && u <= 57) || // 0-9
      (u >= 65 && u <= 90) || // A-Z
      (u >= 97 && u <= 122) || // a-z
      u == 95; // _
}

Map<String, TextStyle> _codeStyles(ColorScheme scheme) => {
      'root': TextStyle(
        color: scheme.onSurface,
        backgroundColor: scheme.surfaceContainer,
      ),
      'keyword': TextStyle(color: scheme.primary),
      'built_in': TextStyle(color: scheme.primary),
      'literal': TextStyle(color: scheme.primary),
      'number': TextStyle(color: scheme.primary),
      'string': TextStyle(color: scheme.onSurfaceVariant),
      'comment': TextStyle(color: scheme.outline, fontStyle: FontStyle.italic),
      'title': TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500),
      'params': TextStyle(color: scheme.onSurface),
    };

class _Bar extends StatelessWidget {
  const _Bar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Luôn giữ chiều cao kể cả khi rỗng → editor không nhảy khi gợi ý đổi.
    return SizedBox(
      height: _barHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        children: children,
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.label,
    required this.color,
    required this.borderColor,
    required this.onTap,
    this.minWidth = 0,
  });

  final String label;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: borderColor),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        child: InkWell(
          // Không cướp focus của editor → bàn phím ảo ở yên.
          canRequestFocus: false,
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minWidth: minWidth, minHeight: _keyHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style:
                      TextStyle(fontFamily: _mono, fontSize: 16, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// CodeController cho Python: tab 4 space, tự đóng ngoặc, overtype, không
/// popup gợi ý desktop (thanh gợi ý của [CodeInput] thay thế).
class _PythonCodeController extends CodeController {
  _PythonCodeController({required String text})
      : super(
          text: text,
          language: python,
          params: const EditorParams(tabSpaces: 4),
          modifiers: const [
            IndentModifier(),
            TabModifier(),
            _PairModifier('(', ')'),
            _PairModifier('[', ']'),
            _PairModifier('{', '}'),
            _PairModifier('"', '"'),
            _PairModifier("'", "'"),
          ],
        );

  static const _pairs = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};
  static const _closers = {')', ']', '}', '"', "'"};

  @override
  Future<void> generateSuggestions() async {}

  @override
  set value(TextEditingValue newValue) {
    super.value = _overtype(newValue) ?? _deletePair(newValue) ?? newValue;
  }

  /// Chèn đoạn `s` tại con trỏ, ngay trước chuỗi dấu đóng sẵn có `R`
  /// (`f(x[|])` → `R = "])"`). Lấy `k` lớn nhất sao cho `k` ký tự cuối của `s`
  /// trùng `k` ký tự đầu của `R` và đều đóng cặp mở TRƯỚC `s` → bỏ `k` ký tự
  /// đó khỏi `s`, con trỏ nhảy qua `k` dấu đóng sẵn có. Gõ 1 ký tự
  /// (`len(|)` + `)`) và bàn phím điện thoại commit nhiều ký tự một lần
  /// (`len(|)` + `0)`, `f(x[|])` + `0])`) đi chung đường này.
  /// Batch nhiều ký tự thì KHÔNG tự thêm dấu đóng (tránh đoán sai ý IME).
  /// Làm ở đây chứ không trong CodeModifier: modifier trả về text không đổi
  /// làm `_getEditResultNotBreakingReadOnly` văng RangeError (đã thử).
  TextEditingValue? _overtype(TextEditingValue next) {
    final old = value;
    final p = old.selection.start;
    final d = next.text.length - old.text.length;
    if (!old.selection.isValid ||
        !old.selection.isCollapsed ||
        p >= old.text.length ||
        d < 1 ||
        next.selection != TextSelection.collapsed(offset: p + d) ||
        !next.text.startsWith(old.text.substring(0, p)) ||
        !next.text.endsWith(old.text.substring(p))) {
      return null;
    }
    final s = next.text.substring(p, p + d);
    var r = 0; // độ dài chuỗi dấu đóng liên tiếp R ngay sau con trỏ cũ
    while (p + r < old.text.length && _closers.contains(old.text[p + r])) {
      r++;
    }
    var k = r < d ? r : d;
    while (k > 0 &&
        !(s.endsWith(old.text.substring(p, p + k)) &&
            _closesOutside(s, k))) {
      k--;
    }
    if (k == 0) return null;
    // Bỏ `k` ký tự [q, q + k) của next; composing (nếu có) co lại tương ứng.
    final q = p + d - k;
    final len = next.text.length - k;
    int shift(int o) {
      final n = o <= q ? o : (o - k < q ? q : o - k);
      return n > len ? len : n;
    }

    final comp = next.composing;
    final composing = comp.isValid && !comp.isCollapsed
        ? TextRange(start: shift(comp.start), end: shift(comp.end))
        : TextRange.empty;
    return TextEditingValue(
      text: next.text.replaceRange(q, q + k, ''),
      selection: TextSelection.collapsed(offset: p + d),
      composing: composing.isCollapsed ? TextRange.empty : composing,
    );
  }

  /// Mỗi ký tự trong [k] ký tự cuối của [s] đều đóng một cặp mở TRƯỚC [s]
  /// (không phải cặp mở trong [s]). Xét theo thứ tự, mỗi ký tự so với phần
  /// [s] đứng trước nó (kể cả các dấu đóng đuôi trước đó). Nháy: số nháy đó
  /// tính tới và gồm chính nó là lẻ. Ngoặc: đếm riêng từng loại, phần trước
  /// nó không còn ngoặc cùng loại mở chưa đóng.
  static bool _closesOutside(String s, int k) {
    final depth = <String, int>{};
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final isQuote = ch == '"' || ch == "'";
      if (i >= s.length - k) {
        if (isQuote ? (depth[ch] ?? 0).isOdd : (depth[ch] ?? 0) > 0) {
          return false;
        }
      }
      if (isQuote) {
        depth[ch] = (depth[ch] ?? 0) + 1;
      } else if (_pairs.containsKey(ch)) {
        depth[_pairs[ch]!] = (depth[_pairs[ch]!] ?? 0) + 1;
      } else if (_closers.contains(ch)) {
        depth[ch] = (depth[ch] ?? 0) - 1;
      }
    }
    return true;
  }

  /// Backspace giữa cặp rỗng `(|)` → xoá cả cặp, không để sót `)`.
  TextEditingValue? _deletePair(TextEditingValue next) {
    final old = value;
    final p = old.selection.start;
    if (!old.selection.isValid ||
        !old.selection.isCollapsed ||
        p <= 0 ||
        p >= old.text.length ||
        next.text.length != old.text.length - 1 ||
        next.selection != TextSelection.collapsed(offset: p - 1) ||
        _pairs[old.text[p - 1]] != old.text[p] ||
        next.text != old.text.replaceRange(p - 1, p, '')) {
      return null;
    }
    return TextEditingValue(
      text: old.text.replaceRange(p - 1, p + 1, ''),
      selection: TextSelection.collapsed(offset: p - 1),
    );
  }
}

/// Gõ ký tự mở → chèn cả cặp, con trỏ ở giữa. Không chèn cặp khi ngay sau
/// con trỏ là chữ/số (`|text` → `(text`), hay khi nháy đứng sau chữ (`abc"`
/// là đang đóng chuỗi).
class _PairModifier extends CodeModifier {
  const _PairModifier(this.open, this.close) : super(open);

  final String open;
  final String close;

  @override
  TextEditingValue? updateString(
    String text,
    TextSelection sel,
    EditorParams params,
  ) {
    if (sel.end < text.length && _isWordChar(text[sel.end])) return null;
    if (open == close && sel.start > 0 && _isWordChar(text[sel.start - 1])) {
      return null;
    }
    return replace(text, sel.start, sel.end, '$open$close').copyWith(
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }
}
