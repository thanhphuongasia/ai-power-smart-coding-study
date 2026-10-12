/// Trình soạn một bài tập dạng form. Sửa trên bản nháp trong màn này; chỉ khi
/// bấm "Áp dụng" mới ghi vào cây nội dung (AdminController.replaceExercise).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../domain/merge.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import 'admin_controller.dart';
import 'code_cell.dart';
import 'collapsible_section.dart';

/// Chuỗi "a, b, c" → ['a','b','c'] (bỏ phần tử rỗng).
List<String> _commaList(String text) => [
  for (final p in text.split(','))
    if (p.trim().isNotEmpty) p.trim(),
];

TextEditingController _ctl(Object? v) =>
    TextEditingController(text: v is String ? v : '');

HighlightingController _hl(Object? v, CodeLanguage language) =>
    HighlightingController(text: v is String ? v : '', language: language);

Json _asJson(Object? v) => v is Json ? v : <String, dynamic>{};

List<String> _strings(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is String) e,
];

/// Controllers của một ô (block). [extra] giữ nguyên field lạ của JSON gốc.
class _BlockForm {
  _BlockForm(Json b)
    : extra = Map<String, dynamic>.of(b),
      keyId = b['id'] is String ? b['id'] as String : '',
      label = _ctl(b['label']),
      title = _ctl(b['title']),
      prompt = _ctl(b['prompt']),
      indent = b['indent_level'] is int ? b['indent_level'] as int : 0,
      expectedOutput = _ctl(b['expected_output']),
      explanation = _ctl(b['explanation']),
      origVocab = _strings(b['vocab']),
      vocab = _ctl(_strings(b['vocab']).join(', ')) {
    initVocabText = vocab.text;
    final answers = _strings(b['accepted_answers']);
    this.answers.addAll(answers.map((a) => _hl(a, CodeLanguage.python)));
    final h = _strings(b['hints']);
    for (var i = 0; i < 3; i++) {
      hints.add(_ctl(i < h.length ? h[i] : ''));
    }
  }

  final Json extra;

  /// Id gốc, chỉ để làm Key ổn định cho widget (id gửi đi suy từ nhãn).
  final String keyId;
  final TextEditingController label;
  final TextEditingController title;
  final TextEditingController prompt;
  int indent;
  final answers = <TextEditingController>[];
  final TextEditingController expectedOutput;
  final TextEditingController explanation;
  final hints = <TextEditingController>[];
  final TextEditingController vocab;
  final List<String> origVocab;
  late final String initVocabText;

  /// Server bắt id == `<bài>-<nhãn thường>`.
  String idFor(String exerciseId) => '$exerciseId-${label.text.toLowerCase()}';

  /// Text chưa đổi → giữ nguyên danh sách gốc (phần tử có thể chứa dấu phẩy).
  List<String> get vocabList =>
      vocab.text == initVocabText ? origVocab : _commaList(vocab.text);

  void dispose() {
    for (final c in [
      label,
      title,
      prompt,
      expectedOutput,
      explanation,
      vocab,
      ...answers,
      ...hints,
    ]) {
      c.dispose();
    }
  }

  Json toJson(String exerciseId) => {
    ...extra,
    'id': idFor(exerciseId),
    'label': label.text,
    'title': title.text,
    'prompt': prompt.text,
    'indent_level': indent,
    'accepted_answers': [
      for (final a in answers)
        if (a.text.trim().isNotEmpty) a.text,
    ],
    'expected_output': expectedOutput.text,
    'explanation': explanation.text,
    'hints': [for (final h in hints) h.text],
    'vocab': vocabList,
  };
}

/// Toàn bộ controllers của form một bài.
class _Form {
  _Form(this.base)
    : title = _ctl(base['title']),
      function = _ctl(base['function_name']),
      className = _ctl(base['class_name']),
      origParams = _strings(base['params']),
      params = _ctl(_strings(base['params']).join(', ')),
      template = _hl(base['template'], CodeLanguage.python),
      statement = _ctl(_asJson(base['challenge'])['statement']),
      motivation = _ctl(_asJson(base['challenge'])['motivation']),
      small = _example(_asJson(_asJson(base['challenge'])['small'])),
      project = _example(_asJson(_asJson(base['challenge'])['project'])),
      solution = _hl(_asJson(base['judge'])['solution'], CodeLanguage.python),
      cases = HighlightingController(
        text: const JsonEncoder.withIndent(
          '  ',
        ).convert(_asJson(base['judge'])['cases'] ?? <Object>[]),
        language: CodeLanguage.json,
      ) {
    initParamsText = params.text;
    final raw = base['blocks'];
    if (raw is List) {
      for (final b in raw) {
        if (b is Json) blocks.add(_BlockForm(b));
      }
    }
  }

  static Map<String, TextEditingController> _example(Json e) => {
    'caption': _ctl(e['caption']),
    'input': _hl(e['input'], CodeLanguage.python),
    'output': _hl(e['output'], CodeLanguage.python),
    'note': _ctl(e['note']),
  };

  final Json base;
  final TextEditingController title;
  final TextEditingController function;
  final TextEditingController className;
  final TextEditingController params;
  final List<String> origParams;
  late final String initParamsText;
  final TextEditingController template;
  final TextEditingController statement;
  final TextEditingController motivation;
  final Map<String, TextEditingController> small;
  final Map<String, TextEditingController> project;
  final TextEditingController solution;
  final TextEditingController cases;
  final blocks = <_BlockForm>[];

  String get exerciseId => base['id'] as String;

  void dispose() {
    for (final c in [
      title,
      function,
      className,
      params,
      template,
      statement,
      motivation,
      ...small.values,
      ...project.values,
      solution,
      cases,
    ]) {
      c.dispose();
    }
    for (final b in blocks) {
      b.dispose();
    }
  }

  /// null = JSON hợp lệ (mảng); ngược lại là thông báo lỗi.
  String? get casesError {
    try {
      final v = jsonDecode(cases.text);
      if (v is! List) return 'Phải là một mảng JSON: [ ... ]';
      return null;
    } on FormatException catch (e) {
      return 'JSON lỗi: ${e.message}';
    }
  }

  Json _example2(Map<String, TextEditingController> e) => {
    'caption': e['caption']!.text,
    'input': e['input']!.text,
    'output': e['output']!.text,
    // Rỗng = không có ghi chú.
    'note': e['note']!.text.isEmpty ? null : e['note']!.text,
  };

  /// Gộp form lên bản gốc (giữ field lạ). Cases lỗi → giữ cases gốc.
  Json toJson() {
    final judge = _asJson(base['judge']);
    final challenge = _asJson(base['challenge']);
    final parsed = casesError == null ? jsonDecode(cases.text) : null;
    return {
      ...base,
      'title': title.text,
      'function_name': function.text,
      'class_name': className.text.trim().isEmpty
          ? null
          : className.text.trim(),
      'params': params.text == initParamsText
          ? origParams
          : _commaList(params.text),
      'template': template.text,
      'challenge': {
        ...challenge,
        'statement': statement.text,
        'motivation': motivation.text,
        'small': _example2(small),
        'project': _example2(project),
      },
      'blocks': [for (final b in blocks) b.toJson(exerciseId)],
      'judge': {
        ...judge,
        'solution': solution.text,
        'cases': parsed ?? judge['cases'] ?? <Object>[],
      },
    };
  }

  /// Nhãn A–Z đầu tiên chưa dùng; null nếu hết.
  String? nextLabel() {
    final used = {for (final b in blocks) b.label.text};
    for (var c = 0x41; c <= 0x5A; c++) {
      final l = String.fromCharCode(c);
      if (!used.contains(l)) return l;
    }
    return null;
  }

  /// Server: tối đa 3 ô.
  static const maxBlocks = 3;
  bool get canAddBlock => blocks.length < maxBlocks && nextLabel() != null;

  /// Nhãn trống hoặc trùng → id sai/trùng, server từ chối.
  String? labelError(_BlockForm b) {
    final l = b.label.text;
    if (l.isEmpty) return 'Nhãn không được để trống';
    if (blocks.where((o) => o.label.text == l).length > 1) {
      return 'Nhãn "$l" bị trùng';
    }
    return null;
  }

  bool get hasLabelError => blocks.any((b) => labelError(b) != null);

  /// Cảnh báo luật server hay vướng (chỉ nhắc, không chặn; server quyết định).
  List<String> get warnings {
    final out = <String>[];
    final marks = <String, int>{};
    for (final line in template.text.split('\n')) {
      final m = RegExp(r'^(\s*)# TODO ([A-Z])\s*$').firstMatch(line);
      if (m != null) marks.putIfAbsent(m.group(2)!, () => m.group(1)!.length);
    }
    for (final b in blocks) {
      final l = b.label.text;
      final p = 'Ô $l';
      if (b.answers.any((a) => a.text.split('\n').length > 2)) {
        out.add('$p: mỗi đáp án tối đa 2 dòng');
      }
      if (b.vocabList.isEmpty) out.add('$p: từ gợi ý (vocab) đang trống');
      if (b.explanation.text.trim().isEmpty) {
        out.add('$p: giải thích đang trống');
      }
      final at = marks[l];
      if (at != null && at != 4 * b.indent) {
        out.add(
          '$p: marker thụt $at space, indent ${b.indent} cần ${4 * b.indent}',
        );
      }
    }
    return out;
  }

  void addBlock() {
    final label = nextLabel();
    if (label == null) return;
    blocks.add(
      _BlockForm({
        'id': '$exerciseId-${label.toLowerCase()}',
        'label': label,
        'title': '',
        'prompt': '',
        'indent_level': 2,
        'accepted_answers': <String>[''],
        'expected_output': '',
        'explanation': '',
        'hints': <String>['', '', ''],
        'vocab': <String>[],
      }),
    );
  }
}

/// Kết quả ghép thử: [ok] = khớp judge.solution; [message] mô tả lệch.
class _MergeResult {
  const _MergeResult.ok() : ok = true, message = null;
  const _MergeResult.mismatch(String this.message) : ok = false;
  final bool ok;
  final String? message;
}

/// Hiện rõ khoảng trắng cuối dòng: "abc··" (· = space, → = tab).
String _visible(String? line) {
  if (line == null) return '(hết)';
  final t = RegExp(r'[ \t]+$').firstMatch(line);
  if (t == null) return '"$line"';
  final tail = t.group(0)!.replaceAll(' ', '·').replaceAll('\t', '→');
  return '"${line.substring(0, t.start)}$tail"';
}

_MergeResult _previewMerge(Json json) {
  try {
    final exercise = Exercise.fromJson(json);
    final cells = {
      for (final b in exercise.blocks)
        b.label: b.acceptedAnswers.isEmpty ? '' : b.acceptedAnswers.first,
    };
    final merged = mergeCells(exercise, cells).code;
    final solution = (_asJson(json['judge'])['solution'] as String?) ?? '';
    // Server so từng ký tự, không trim: preview cũng vậy.
    if (merged == solution) return const _MergeResult.ok();
    final a = merged.split('\n');
    final b = solution.split('\n');
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : null;
      final y = i < b.length ? b[i] : null;
      if (x != y) {
        return _MergeResult.mismatch(
          'Lệch ở dòng ${i + 1}\n'
          'Ghép được: ${_visible(x)}\n'
          'Lời giải:  ${_visible(y)}',
        );
      }
    }
    return const _MergeResult.mismatch('Khác nhau');
  } on FormatException catch (e) {
    return _MergeResult.mismatch('Chưa ghép được: ${e.message}');
  } on ArgumentError catch (e) {
    return _MergeResult.mismatch('Chưa ghép được: ${e.message}');
  } catch (e) {
    // Preview không được làm đỏ màn hình (vd TypeError do dữ liệu dở dang).
    return _MergeResult.mismatch('Chưa ghép được: $e');
  }
}

class _UpperCaseLetter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text.toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    final one = t.isEmpty ? '' : t.substring(t.length - 1);
    return TextEditingValue(
      text: one,
      selection: TextSelection.collapsed(offset: one.length),
    );
  }
}

class ExerciseEditorScreen extends ConsumerStatefulWidget {
  const ExerciseEditorScreen({super.key, required this.exerciseId});
  final String exerciseId;

  @override
  ConsumerState<ExerciseEditorScreen> createState() => _State();
}

class _State extends ConsumerState<ExerciseEditorScreen> {
  _Form? _form;
  String? _applyError;

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _applyError = null);

  void _apply() {
    final f = _form!;
    if (f.casesError != null || f.hasLabelError) return;
    final ok = ref
        .read(adminProvider.notifier)
        .replaceExercise(widget.exerciseId, f.toJson());
    if (!ok) {
      setState(() => _applyError = 'Không áp dụng được bài này.');
      return;
    }
    context.pop();
  }

  Widget _text(
    String key,
    TextEditingController c,
    String label, {
    int maxLines = 1,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.s2),
    child: TextField(
      key: Key(key),
      controller: c,
      minLines: 1,
      maxLines: maxLines == 1 ? 1 : null,
      style: AppText.body,
      inputFormatters: formatters,
      onChanged: (_) => _changed(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  /// Ô code (gutter, tô màu). [key] nằm trên chính TextField.
  Widget _codeCell(
    String key,
    TextEditingController c,
    String label,
    CodeLanguage language, {
    int minLines = 3,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.s2),
    child: CodeCell(
      key: Key(key),
      controller: c,
      language: language,
      label: label,
      minLines: minLines,
      onChanged: (_) => _changed(),
    ),
  );

  Widget _example(
    String prefix,
    String title,
    Map<String, TextEditingController> e,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionLabel(title),
      _text('$prefix-caption', e['caption']!, 'Mô tả'),
      _codeCell(
        '$prefix-input',
        e['input']!,
        'Input (code gọi)',
        CodeLanguage.python,
        minLines: 2,
      ),
      _codeCell(
        '$prefix-output',
        e['output']!,
        'Output',
        CodeLanguage.python,
        minLines: 2,
      ),
      _text('$prefix-note', e['note']!, 'Ghi chú (trống = không có)'),
    ],
  );

  Widget _blockCard(_BlockForm b) {
    final l = b.label.text;
    final p = context.palette;
    return Padding(
      key: ObjectKey(b),
      padding: const EdgeInsets.only(bottom: AppSpace.s4),
      child: CollapsibleCard(
        badge: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            shape: BoxShape.circle,
            border: Border.all(color: p.outline),
          ),
          child: Text(l, style: AppText.label.copyWith(color: p.ink)),
        ),
        title: b.title.text.isEmpty ? 'Ô $l' : b.title.text,
        subtitle: b.idFor(_form!.exerciseId),
        actions: [
          IconButton(
            key: Key('block-$l-remove'),
            icon: Icon(Icons.delete_outline, color: p.danger),
            tooltip: 'Xoá ô $l',
            onPressed: () {
              b.dispose();
              _form!.blocks.remove(b);
              _changed();
            },
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 72,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s2),
                  child: TextField(
                    key: ValueKey('label-${b.keyId}'),
                    controller: b.label,
                    inputFormatters: [_UpperCaseLetter()],
                    onChanged: (_) => _changed(),
                    decoration: const InputDecoration(
                      labelText: 'Nhãn',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ),
            if (_form!.labelError(b) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s2),
                child: Text(
                  _form!.labelError(b)!,
                  key: Key('label-error-${b.keyId}'),
                  style: AppText.caption.copyWith(color: p.danger),
                ),
              ),
            _text('block-$l-title', b.title, 'Tiêu đề'),
            _text('block-$l-prompt', b.prompt, 'Đề (prompt)', maxLines: 2),
            Row(
              children: [
                Expanded(
                  child: Text('Thụt lề (indent_level)', style: AppText.body),
                ),
                const SizedBox(width: AppSpace.s4),
                DropdownButton<int>(
                  key: Key('block-$l-indent'),
                  value: b.indent.clamp(0, 4),
                  items: [
                    for (var i = 0; i <= 4; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    b.indent = v;
                    _changed();
                  },
                ),
              ],
            ),
            const SectionLabel('Đáp án chấp nhận (ô đầu = đáp án chuẩn)'),
            for (var i = 0; i < b.answers.length; i++)
              Column(
                key: ValueKey(b.answers[i]),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _codeCell(
                    'block-$l-answer-$i',
                    b.answers[i],
                    i == 0 ? 'Đáp án chuẩn' : 'Đáp án ${i + 1}',
                    CodeLanguage.python,
                    minLines: 2,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: Key('block-$l-answer-$i-remove'),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Xoá đáp án'),
                      onPressed: () {
                        b.answers.removeAt(i).dispose();
                        _changed();
                      },
                    ),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('block-$l-answer-add'),
                icon: const Icon(Icons.add),
                label: const Text('Thêm đáp án'),
                onPressed: () {
                  b.answers.add(
                    HighlightingController(language: CodeLanguage.python),
                  );
                  _changed();
                },
              ),
            ),
            _text('block-$l-expected', b.expectedOutput, 'Output mong đợi'),
            _text(
              'block-$l-explanation',
              b.explanation,
              'Giải thích',
              maxLines: 2,
            ),
            for (var i = 0; i < 3; i++)
              _text('block-$l-hint-$i', b.hints[i], 'Gợi ý ${i + 1}'),
            _text('block-$l-vocab', b.vocab, 'Từ gợi ý (cách nhau dấu phẩy)'),
          ],
        ),
      ),
    );
  }

  Widget _preview(_Form f) {
    final p = context.palette;
    final r = _previewMerge(f.toJson());
    final warnings = f.warnings;
    final color = r.ok ? p.accent : p.danger;
    final box = Container(
      key: const Key('merge-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: r.ok
          ? Text(
              'Khớp lời giải',
              key: const Key('merge-ok'),
              style: AppText.label.copyWith(color: color),
            )
          : Column(
              key: const Key('merge-mismatch'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Không khớp lời giải',
                  style: AppText.label.copyWith(color: color),
                ),
                const SizedBox(height: AppSpace.s2),
                Text(r.message!, style: AppText.code),
              ],
            ),
    );
    if (warnings.isEmpty) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        box,
        const SizedBox(height: AppSpace.s2),
        Column(
          key: const Key('merge-warnings'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in warnings)
              Text(
                'Cảnh báo — $w',
                style: AppText.caption.copyWith(
                  color: context.palette.inkMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // --- Layout -------------------------------------------------------------

  static const _wideBreakpoint = 1100.0;
  static const _mediumBreakpoint = 700.0;
  static const _panelWidth = 360.0;
  static const _tocWidth = 200.0;

  /// Neo cuộn của từng mục (mục lục ở layout rộng).
  final _sectionKeys = <String, GlobalKey>{
    'basic': GlobalKey(),
    'template': GlobalKey(),
    'challenge': GlobalKey(),
    'blocks': GlobalKey(),
    'judge': GlobalKey(),
  };

  static const _sectionTitles = <String, String>{
    'basic': 'Cơ bản',
    'template': 'Template',
    'challenge': 'Challenge',
    'blocks': 'Các ô (blocks)',
    'judge': 'Judge',
  };

  void _jumpTo(String id) {
    final ctx = _sectionKeys[id]!.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  String _firstLine(String s) {
    final t = s.trim().split('\n').first;
    return t.length > 60 ? '${t.substring(0, 60)}…' : t;
  }

  /// Các mục của form; mọi mục mở mặc định (test và người dùng đều thấy ngay).
  List<Widget> _sections(_Form f, String? casesError) {
    final warn = f.warnings.isNotEmpty;
    final labelErrors = [
      for (final b in f.blocks)
        if (f.labelError(b) != null) f.labelError(b)!,
    ];
    Widget section(
      String id,
      Widget child, {
      String? summary,
      SectionStatus status = SectionStatus.ok,
    }) => CollapsibleSection(
      key: _sectionKeys[id],
      title: _sectionTitles[id]!,
      summary: summary,
      status: status,
      child: child,
    );

    return [
      section(
        'basic',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text('ex-title', f.title, 'Tiêu đề'),
            _text('ex-function', f.function, 'Tên hàm (function_name)'),
            _text('ex-class', f.className, 'Tên class (trống = hàm tự do)'),
            _text('ex-params', f.params, 'Tham số (cách nhau dấu phẩy)'),
          ],
        ),
        summary: f.title.text,
      ),
      section(
        'template',
        _codeCell(
          'ex-template',
          f.template,
          'Template (ô TODO: "# TODO A")',
          CodeLanguage.python,
          minLines: 8,
        ),
        summary: '${f.template.text.split('\n').length} dòng',
      ),
      section(
        'challenge',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text('ex-statement', f.statement, 'Đề bài', maxLines: 3),
            _text('ex-motivation', f.motivation, 'Động lực', maxLines: 3),
            _example('ex-small', 'Ví dụ nhỏ', f.small),
            _example('ex-project', 'Ví dụ dự án', f.project),
          ],
        ),
        summary: _firstLine(f.statement.text),
      ),
      section(
        'blocks',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in f.blocks) _blockCard(b),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                key: const Key('block-add'),
                label: 'Thêm ô',
                onPressed: !f.canAddBlock
                    ? null
                    : () {
                        f.addBlock();
                        _changed();
                      },
              ),
            ),
          ],
        ),
        summary: labelErrors.isNotEmpty
            ? labelErrors.first
            : '${f.blocks.length} ô',
        status: f.hasLabelError
            ? SectionStatus.error
            : (warn ? SectionStatus.warn : SectionStatus.ok),
      ),
      section(
        'judge',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _codeCell(
              'ex-solution',
              f.solution,
              'Lời giải (solution)',
              CodeLanguage.python,
              minLines: 8,
            ),
            _codeCell(
              'ex-cases',
              f.cases,
              'Cases (mảng JSON)',
              CodeLanguage.json,
              minLines: 8,
            ),
            if (casesError != null)
              Text(
                casesError,
                key: const Key('ex-cases-error'),
                style: AppText.caption.copyWith(color: context.palette.danger),
              ),
          ],
        ),
        summary:
            casesError ?? 'solution ${f.solution.text.split('\n').length} dòng',
        status: casesError != null ? SectionStatus.error : SectionStatus.ok,
      ),
    ];
  }

  Widget _toc() {
    final p = context.palette;
    return SizedBox(
      width: _tocWidth,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Mục lục'),
            for (final e in _sectionTitles.entries)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: Key('toc-${e.key}'),
                  style: TextButton.styleFrom(foregroundColor: p.ink),
                  onPressed: () => _jumpTo(e.key),
                  child: Text(e.value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _previewPanel(_Form f) {
    final p = context.palette;
    return Container(
      width: _panelWidth,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: p.outline)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Ghép thử (đáp án chuẩn của mọi ô)'),
            _preview(f),
          ],
        ),
      ),
    );
  }

  /// Một bộ Huỷ/Áp dụng duy nhất cho mọi layout (INV-04).
  Widget _actionBar(_Form f, String? casesError) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.outline)),
      ),
      padding: const EdgeInsets.all(AppSpace.s4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_applyError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s2),
                  child: Text(
                    _applyError!,
                    style: AppText.caption.copyWith(color: p.danger),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      key: const Key('exercise-cancel'),
                      label: 'Huỷ',
                      onPressed: () => context.pop(),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s4),
                  Expanded(
                    child: PrimaryButton(
                      key: const Key('exercise-apply'),
                      label: 'Áp dụng',
                      onPressed: casesError == null && !f.hasLabelError
                          ? _apply
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(adminProvider);
    final p = context.palette;
    final raw = s.exercises[widget.exerciseId];

    Widget body;
    if (s.status == AdminStatus.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (raw is! Json || raw['id'] is! String) {
      body = const Center(child: Text('Không tìm thấy bài tập.'));
    } else {
      // Chỉ dựng form một lần; sửa tiếp theo nằm trong controllers.
      final f = _form ??= _Form(Map<String, dynamic>.of(raw));
      final casesError = f.casesError;
      body = Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= _wideBreakpoint;
                final medium = c.maxWidth >= _mediumBreakpoint;
                // Chỉ MỘT nhánh chạy → _preview dựng đúng một chỗ (INV-03).
                final sections = _sections(f, casesError);
                Widget form(List<Widget> tail) => SingleChildScrollView(
                  key: const Key('exercise-editor'),
                  padding: const EdgeInsets.all(AppSpace.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.dirty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.s4),
                          child: Text(
                            'Nội dung đã sửa, chưa lưu lên server '
                            '(lưu ở màn Soạn nội dung).',
                            key: const Key('exercise-dirty'),
                            style: AppText.caption.copyWith(color: p.inkMuted),
                          ),
                        ),
                      for (final w in sections) ...[
                        w,
                        const SizedBox(height: AppSpace.s4),
                      ],
                      ...tail,
                    ],
                  ),
                );
                if (medium) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide) _toc(),
                      Expanded(child: form(const [])),
                      _previewPanel(f),
                    ],
                  );
                }
                return form([
                  const SectionLabel('Ghép thử (đáp án chuẩn của mọi ô)'),
                  _preview(f),
                ]);
              },
            ),
          ),
          _actionBar(f, casesError),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: widget.exerciseId,
              subtitle: 'Soạn bài tập',
              onBack: () => context.pop(),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
