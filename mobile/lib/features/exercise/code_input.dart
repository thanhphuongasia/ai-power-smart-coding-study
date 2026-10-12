import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';

import '../../app/theme.dart';
import 'completion_engine.dart';

const _mono = 'JetBrains Mono';
const _barHeight = 48.0;
const _keyHeight = 40.0;
const _tab = '    ';
// Kiểu ô Jupyter/IDE: góc gần vuông, cột số dòng, chữ mono vừa đủ đọc.
const _borderRadius = 4.0;
const _placeholder = '# viết code ở đây';
const _fontSize = 15.0;
const _lineHeight = 1.45;
const _gutterWidth = 30.0;
// CodeField tự đệm trái 8px trước gutter (code_field.dart, không chỉnh được).
const _fieldLeftPad = 8.0;

/// Phím ký hiệu, theo thứ tự hay dùng. Tab tách riêng vì chèn 4 space.
const List<String> _symbols = ['(', ')', '[', ']', ':', '=', '.', ',', '"'];

/// Cầu nối giữa nhiều [CodeInput] (`showBars: false`) và MỘT [CodeToolbar]:
/// editor nào đang focus thì tự đăng ký làm "ô active", mất focus thì tự gỡ.
/// Truyền cùng một controller cho các [CodeInput] và cho [CodeToolbar].
/// Phải `dispose()` khi bỏ.
class CodeToolbarController extends ChangeNotifier {
  _CodeInputState? _active;
  bool _disposed = false;

  /// Có ô nào đang focus (thanh công cụ dùng được) hay không.
  bool get hasActive => _active != null;

  void _changed() => notifyListeners();

  void _attach(_CodeInputState s) {
    if (_active == s) return;
    _active = s;
    notifyListeners();
  }

  void _detach(_CodeInputState s, {bool deferred = false}) {
    if (_active != s) return;
    _active = null;
    if (deferred) {
      // Đang dispose trong lúc unmount cây → không notify đồng bộ.
      Future.microtask(() {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Editor code cho điện thoại: editor ở trên, thanh gợi ý + hàng phím ký hiệu
/// ngay dưới (tức là nằm sát trên bàn phím ảo).
///
/// Nhiều ô trên một màn: đặt `showBars: false`, `keyPrefix` riêng cho từng ô,
/// cùng một [toolbar], rồi dựng một [CodeToolbar] ở đáy màn.
class CodeInput extends StatefulWidget {
  const CodeInput({
    super.key,
    required this.initialCode,
    required this.knownIdentifiers,
    required this.vocab,
    required this.onChanged,
    this.onActivity,
    this.focusNode,
    this.showBars = true,
    this.keyPrefix = 'code-input',
    this.toolbar,
    this.answers = const [],
    this.ghost = false,
  });

  final String initialCode;
  final List<String> knownIdentifiers;
  final List<String> vocab;
  final ValueChanged<String> onChanged;
  final VoidCallback? onActivity;
  final FocusNode? focusNode;

  /// `false` → không vẽ thanh gợi ý/phím ký hiệu riêng (dùng [CodeToolbar]).
  final bool showBars;

  /// Tiền tố key: `<prefix>-field`, `<prefix>-border`. Mặc định giữ key cũ.
  final String keyPrefix;

  /// Nơi ô này đăng ký khi được focus, để [CodeToolbar] chèn đúng ô.
  final CodeToolbarController? toolbar;

  /// Đáp án chấp nhận của ô, để dựng chữ mờ gợi ý (cần [ghost] = true).
  final List<String> answers;

  /// `true` → chữ mờ gợi ý phần còn lại của đáp án (Tab để nhận) + dải từ
  /// gợi ý luôn hiện. `false` (mặc định) → hành vi cũ y nguyên.
  final bool ghost;

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
    _controller.ghostProvider = () => _ghost;
    _controller.onGhostTab = _acceptGhost;
    _last = _controller.value;
    _controller.addListener(_onControllerChanged);
    // CodeField gắn focusNode trong initState của nó, nên chốt một lần ở đây.
    _focus = widget.focusNode ?? (_ownFocus = FocusNode());
    _focus.addListener(_onFocusChanged);
    if (_focus.hasFocus) widget.toolbar?._attach(this);
  }

  /// Phần còn lại của đáp án để vẽ mờ; rỗng khi tắt, đang chọn đoạn, con trỏ
  /// không ở cuối hay IME đang soạn dở. Chỉ đọc controller, không ghi (INV-04).
  String get _ghost {
    if (!widget.ghost || widget.answers.isEmpty) return '';
    final v = _controller.value;
    final sel = v.selection;
    if (sel.isValid && (!sel.isCollapsed || sel.end != v.text.length)) {
      return '';
    }
    if (v.composing.isValid && !v.composing.isCollapsed) return '';
    return ghostFor(v.text, widget.answers);
  }

  /// Chèn thật phần mờ vào cuối text → từ đây mới đổi text và gọi onChanged.
  void _acceptGhost() {
    final g = _ghost;
    if (g.isEmpty) return;
    HapticFeedback.selectionClick();
    final text = _controller.text;
    _controller.value = TextEditingValue(
      text: text + g,
      selection: TextSelection.collapsed(offset: text.length + g.length),
    );
    _keepKeyboard();
  }

  void _onFocusChanged() {
    final t = widget.toolbar;
    if (t == null) return;
    if (_focus.hasFocus) {
      t._attach(this);
    } else {
      t._detach(this);
    }
  }

  @override
  void didUpdateWidget(CodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.toolbar != oldWidget.toolbar) {
      oldWidget.toolbar?._detach(this, deferred: true);
      if (_focus.hasFocus) widget.toolbar?._attach(this);
    }
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
    widget.toolbar?._detach(this, deferred: true);
    _focus.removeListener(_onFocusChanged);
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
    // Text/con trỏ đổi → gợi ý của thanh dùng chung phải tính lại.
    if (_focus.hasFocus && widget.toolbar?._active == this) {
      widget.toolbar!._changed();
    }
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

  List<Suggestion> _suggestionsFor(
    List<String> knownIdentifiers,
    List<String> vocab,
  ) {
    final sel = _selection;
    if (!sel.isCollapsed) return const [];
    return suggest(
      textBeforeCursor: _controller.text.substring(0, sel.start),
      knownIdentifiers: knownIdentifiers,
      vocab: vocab,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Khối code luôn nền tối ở cả hai theme (INV-08) → chữ phụ lấy từ codeInk.
    final palette = context.palette;
    _controller.ghostColor = palette.codeInk.withValues(alpha: 0.4);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        final codeField = CodeTheme(
          data: CodeThemeData(styles: codeSyntaxStyles(palette)),
          child: CodeField(
            key: Key('${widget.keyPrefix}-field'),
            controller: _controller,
            focusNode: _focus,
            expands: bounded,
            minLines: bounded ? null : 2,
            gutterStyle: GutterStyle(
              // Gutter tự trừ 16+16px cho cột lỗi và cột gập dù đã tắt.
              width: _gutterWidth + 32,
              margin: 8,
              showErrors: false,
              showFoldingHandles: false,
              textStyle: TextStyle(
                color: palette.codeInk.withValues(alpha: 0.5),
              ),
            ),
            background: palette.codeSurface,
            cursorColor: palette.codeInk,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(
              fontFamily: _mono,
              fontSize: _fontSize,
              height: _lineHeight,
            ),
          ),
        );

        // Lớp hiển thị thuần tuý, không đụng controller (INV-04) — chỉ đọc
        // text để quyết định hiện/ẩn, không bao giờ ghi lại.
        final showPlaceholder = _controller.text.isEmpty && _ghost.isEmpty;
        final stacked = Stack(
          children: [
            codeField,
            if (showPlaceholder)
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _fieldLeftPad + _gutterWidth,
                    16,
                    8,
                    0,
                  ),
                  child: Text(
                    _placeholder,
                    style: TextStyle(
                      fontFamily: _mono,
                      fontSize: _fontSize,
                      height: _lineHeight,
                      fontStyle: FontStyle.italic,
                      color: palette.codeInk.withValues(alpha: 0.55),
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
              key: Key('${widget.keyPrefix}-border'),
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

        if (!widget.showBars) return field;

        return Column(
          mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bounded) Expanded(child: field) else field,
            _BarsPanel(
              suggestions: _suggestionsFor(
                widget.knownIdentifiers,
                widget.vocab,
              ),
              onSuggestion: _applySuggestion,
              onSymbol: _insertSymbol,
              showVocab: widget.ghost,
              vocab: vocabStrip(widget.vocab),
              ghostText: _ghost,
              onGhost: _acceptGhost,
            ),
          ],
        );
      },
    );
  }
}

/// Thanh gợi ý + hàng phím ký hiệu (+Tab) dùng chung cho nhiều [CodeInput]
/// (`showBars: false`, cùng [controller]). Chèn vào đúng ô đang focus, không
/// làm mất focus; không có ô nào focus thì các phím bị vô hiệu hoá.
class CodeToolbar extends StatelessWidget {
  const CodeToolbar({
    super.key,
    required this.controller,
    required this.knownIdentifiers,
    required this.vocab,
    this.ghost = false,
  });

  final CodeToolbarController controller;
  final List<String> knownIdentifiers;
  final List<String> vocab;

  /// `true` → thêm hàng từ gợi ý luôn hiện + chip nhận chữ mờ của ô active.
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = controller._active;
        return _BarsPanel(
          suggestions:
              active?._suggestionsFor(knownIdentifiers, vocab) ?? const [],
          onSuggestion: active?._applySuggestion,
          onSymbol: active?._insertSymbol,
          showVocab: ghost,
          vocab: vocabStrip(vocab),
          ghostText: active?._ghost ?? '',
          onGhost: active?._acceptGhost,
        );
      },
    );
  }
}

/// Hai hàng gợi ý + phím ký hiệu. Callback null → phím bị vô hiệu hoá.
class _BarsPanel extends StatelessWidget {
  const _BarsPanel({
    required this.suggestions,
    required this.onSuggestion,
    required this.onSymbol,
    this.showVocab = false,
    this.vocab = const [],
    this.ghostText = '',
    this.onGhost,
  });

  final List<Suggestion> suggestions;
  final ValueChanged<Suggestion>? onSuggestion;
  final ValueChanged<String>? onSymbol;

  /// Hàng từ gợi ý luôn hiện (chỉ khi ghost bật).
  final bool showVocab;
  final List<Suggestion> vocab;
  final String ghostText;
  final VoidCallback? onGhost;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSuggestion = this.onSuggestion;
    final onSymbol = this.onSymbol;
    final palette = context.palette;
    // Ghost có thể bắt đầu bằng '\n' (đáp án nhiều dòng, vừa gõ xong dòng 1)
    // → nhãn lấy dòng KHÔNG rỗng đầu tiên.
    final ghostLabel = ghostText
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    // Chạm vào 2 hàng này được tính là "bên trong" ô nhập → không mất
    // focus, bàn phím không sụp.
    return TextFieldTapRegion(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border(top: BorderSide(color: scheme.outline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showVocab)
              _Bar(
                children: [
                  if (ghostText.isNotEmpty)
                    _Key(
                      key: const Key('ghost-accept'),
                      label: '⇥ $ghostLabel',
                      color: palette.primary,
                      borderColor: palette.primary,
                      onTap: onGhost,
                    ),
                  for (final s in vocab)
                    _Key(
                      key: Key('vocab-${s.label}'),
                      label: s.insertText.endsWith('(')
                          ? '${s.label}()'
                          : s.label,
                      color: palette.ink,
                      borderColor: palette.outline,
                      onTap: onSuggestion == null
                          ? null
                          : () => onSuggestion(s),
                    ),
                ],
              ),
            _Bar(
              children: [
                for (final (i, s) in suggestions.indexed)
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
                    onTap: onSuggestion == null ? null : () => onSuggestion(s),
                  ),
              ],
            ),
            _Bar(
              children: [
                for (final c in _symbols)
                  _Key(
                    key: Key('symbol-$c'),
                    label: c,
                    color: scheme.onSurface,
                    borderColor: scheme.outline,
                    minWidth: 44,
                    onTap: onSymbol == null ? null : () => onSymbol(c),
                  ),
                _Key(
                  key: const Key('symbol-tab'),
                  label: 'Tab',
                  color: scheme.onSurfaceVariant,
                  borderColor: scheme.outline,
                  minWidth: 56,
                  onTap: onSymbol == null ? null : () => onSymbol(_tab),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

bool _isWordChar(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 48 && u <= 57) || // 0-9
      (u >= 65 && u <= 90) || // A-Z
      (u >= 97 && u <= 122) || // a-z
      u == 95; // _
}

// Màu tô cú pháp chọn cho nền TỐI của khối code (codeSurface), không đổi theo
// theme sáng/tối của app (INV-08).
const _synKeyword = Color(0xFF8AB4FF);
const _synNumber = Color(0xFFF2B866);
const _synString = Color(0xFF9BD6A8);
const _synComment = Color(0xFF7D879E);

/// Bảng tô cú pháp dùng chung cho editor và các khối code xem-chỉ-đọc.
Map<String, TextStyle> codeSyntaxStyles(AppPalette p) => {
  'root': TextStyle(color: p.codeInk, backgroundColor: p.codeSurface),
  'keyword': const TextStyle(color: _synKeyword),
  'built_in': const TextStyle(color: _synKeyword),
  'literal': const TextStyle(color: _synKeyword),
  'number': const TextStyle(color: _synNumber),
  'string': const TextStyle(color: _synString),
  'comment': const TextStyle(color: _synComment, fontStyle: FontStyle.italic),
  'title': TextStyle(color: p.codeInk, fontWeight: FontWeight.w500),
  'params': TextStyle(color: p.codeInk),
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
  final VoidCallback? onTap;
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
            constraints: BoxConstraints(
              minWidth: minWidth,
              minHeight: _keyHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: _mono,
                    fontSize: 16,
                    color: onTap == null ? color.withValues(alpha: 0.4) : color,
                  ),
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

  /// Chữ mờ gợi ý: chỉ nối thêm vào TextSpan hiển thị, KHÔNG nằm trong
  /// `text` (INV-04).
  String Function()? ghostProvider;
  VoidCallback? onGhostTab;
  Color? ghostColor;

  /// CodeField chuyển phím vào đây trước cả Shortcuts: Tab khi chữ mờ đang
  /// hiện → nhận gợi ý thay vì chèn 4 space.
  @override
  KeyEventResult onKey(KeyEvent event) {
    final kb = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        !kb.isShiftPressed &&
        !kb.isControlPressed &&
        !kb.isAltPressed &&
        !kb.isMetaPressed &&
        (ghostProvider?.call() ?? '').isNotEmpty) {
      onGhostTab?.call();
      return KeyEventResult.handled;
    }
    return super.onKey(event);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    final base = super.buildTextSpan(
      context: context,
      style: style,
      withComposing: withComposing,
    );
    final g = ghostProvider?.call() ?? '';
    if (g.isEmpty) return base;
    return TextSpan(
      style: style,
      children: [
        base,
        TextSpan(
          text: g,
          style: TextStyle(color: ghostColor, fontStyle: FontStyle.normal),
        ),
      ],
    );
  }

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
        !(s.endsWith(old.text.substring(p, p + k)) && _closesOutside(s, k))) {
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
    return replace(
      text,
      sel.start,
      sel.end,
      '$open$close',
    ).copyWith(selection: TextSelection.collapsed(offset: sel.start + 1));
  }
}
