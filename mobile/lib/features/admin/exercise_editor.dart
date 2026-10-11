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

/// Chuỗi "a, b, c" → ['a','b','c'] (bỏ phần tử rỗng).
List<String> _commaList(String text) => [
  for (final p in text.split(','))
    if (p.trim().isNotEmpty) p.trim(),
];

TextEditingController _ctl(Object? v) =>
    TextEditingController(text: v is String ? v : '');

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
    this.answers.addAll(answers.map(_ctl));
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
      template = _ctl(base['template']),
      statement = _ctl(_asJson(base['challenge'])['statement']),
      motivation = _ctl(_asJson(base['challenge'])['motivation']),
      small = _example(_asJson(_asJson(base['challenge'])['small'])),
      project = _example(_asJson(_asJson(base['challenge'])['project'])),
      solution = _ctl(_asJson(base['judge'])['solution']),
      cases = TextEditingController(
        text: const JsonEncoder.withIndent(
          '  ',
        ).convert(_asJson(base['judge'])['cases'] ?? <Object>[]),
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
    'input': _ctl(e['input']),
    'output': _ctl(e['output']),
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
    bool mono = false,
    String? errorText,
    String? helper,
    List<TextInputFormatter>? formatters,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.s2),
    child: TextField(
      key: Key(key),
      controller: c,
      minLines: maxLines == 1 ? 1 : maxLines,
      maxLines: maxLines == 1 ? 1 : null,
      style: mono ? AppText.code : AppText.body,
      inputFormatters: formatters,
      onChanged: (_) => _changed(),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: errorText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
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
      _text(
        '$prefix-input',
        e['input']!,
        'Input (code gọi)',
        maxLines: 2,
        mono: true,
      ),
      _text('$prefix-output', e['output']!, 'Output', maxLines: 2, mono: true),
      _text('$prefix-note', e['note']!, 'Ghi chú (trống = không có)'),
    ],
  );

  Widget _blockCard(_BlockForm b) {
    final l = b.label.text;
    final p = context.palette;
    return Padding(
      key: ObjectKey(b),
      padding: const EdgeInsets.only(bottom: AppSpace.s4),
      child: SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 72,
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
                  const SizedBox(width: AppSpace.s4),
                  Expanded(
                    child: Text(
                      b.idFor(_form!.exerciseId),
                      style: AppText.caption.copyWith(color: p.inkMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _text(
                        'block-$l-answer-$i',
                        b.answers[i],
                        i == 0 ? 'Đáp án chuẩn' : 'Đáp án ${i + 1}',
                        maxLines: 2,
                        mono: true,
                      ),
                    ),
                    IconButton(
                      key: Key('block-$l-answer-$i-remove'),
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Xoá đáp án',
                      onPressed: () {
                        b.answers.removeAt(i).dispose();
                        _changed();
                      },
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
                    b.answers.add(TextEditingController());
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
            child: SingleChildScrollView(
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
                  const SectionLabel('Cơ bản'),
                  _text('ex-title', f.title, 'Tiêu đề'),
                  _text('ex-function', f.function, 'Tên hàm (function_name)'),
                  _text(
                    'ex-class',
                    f.className,
                    'Tên class (trống = hàm tự do)',
                  ),
                  _text('ex-params', f.params, 'Tham số (cách nhau dấu phẩy)'),
                  const SectionLabel('Template (ô TODO: "# TODO A")'),
                  _text(
                    'ex-template',
                    f.template,
                    'Template',
                    maxLines: 8,
                    mono: true,
                  ),
                  const SectionLabel('Challenge'),
                  _text('ex-statement', f.statement, 'Đề bài', maxLines: 3),
                  _text('ex-motivation', f.motivation, 'Động lực', maxLines: 3),
                  _example('ex-small', 'Ví dụ nhỏ', f.small),
                  _example('ex-project', 'Ví dụ dự án', f.project),
                  const SectionLabel('Các ô (blocks)'),
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
                  const SectionLabel('Judge'),
                  _text(
                    'ex-solution',
                    f.solution,
                    'Lời giải (solution)',
                    maxLines: 8,
                    mono: true,
                  ),
                  _text(
                    'ex-cases',
                    f.cases,
                    'Cases (mảng JSON)',
                    maxLines: 8,
                    mono: true,
                  ),
                  if (casesError != null)
                    Text(
                      casesError,
                      key: const Key('ex-cases-error'),
                      style: AppText.caption.copyWith(color: p.danger),
                    ),
                  const SectionLabel('Ghép thử (đáp án chuẩn của mọi ô)'),
                  _preview(f),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
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
