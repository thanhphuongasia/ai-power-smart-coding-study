/// Tab Code: notebook kiểu Jupyter — ô khoá "có sẵn" xen kẽ ô TODO, Run tất
/// cả → ghép ô → judge → kết quả (Out) → "Bài tiếp theo".
///
/// Ô TODO mở lần lượt: ô sau khoá tới khi ô trước khớp đáp án mẫu; ô khớp tự
/// thu gọn thành một dòng và ô kế mở ra. Chỉ một ô mở (accordion).
/// Ô mở chỉ là bản xem trước; chạm vào → [CellEditorPage] toàn màn hình.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;
import 'package:highlight/highlight.dart' as hl;

import '../../app/theme.dart';
import '../../data/content_providers.dart';
import '../../data/judge_client.dart';
import '../../domain/answer_checker.dart';
import '../../domain/merge.dart';
import '../../domain/models.dart';
import '../../domain/progression.dart';
import '../../shared/widgets.dart';
import 'cell_editor_page.dart';
import 'challenge_tab.dart' show LabelTag;
import 'run_result_view.dart';
import 'session_controller.dart';
import 'session_providers.dart';

class CodeTab extends ConsumerStatefulWidget {
  const CodeTab({super.key, required this.exercise});

  final Exercise exercise;

  @override
  ConsumerState<CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends ConsumerState<CodeTab>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final Map<String, String> _cells = {};

  late final List<TemplateSegment> _segments;

  /// Ô đang/đã mở gần nhất — nút Gợi ý nhắm vào ô này.
  late String _activeLabel;

  /// Ô đang mở editor; null = mọi ô thu gọn.
  String? _open;

  bool _running = false;
  int _runCount = 0;
  JudgeResult? _result;
  MergedCode? _merged;
  Set<String> _emptyLabels = {};

  @override
  bool get wantKeepAlive => true;

  Exercise get _exercise => widget.exercise;

  @override
  void initState() {
    super.initState();
    _segments = templateSegments(_exercise);
    final drafts = ref.read(progressProvider)[_exercise.id]?.drafts ?? const {};
    for (final b in _exercise.blocks) {
      _cells[b.label] = drafts[b.label] ?? '';
    }
    _open = _frontier();
    _activeLabel = _open ?? _exercise.blocks.first.label;
  }

  /// Ô khớp một đáp án mẫu (cùng chuẩn hoá với `_recheck`).
  bool _isDone(Block b) {
    final mine = normalizeCode(_cells[b.label] ?? '');
    return mine.isNotEmpty &&
        b.acceptedAnswers.any((a) => normalizeCode(a) == mine);
  }

  /// Bài đã từng passed → mở hết (cách viết khác đáp án mẫu vẫn sửa được).
  bool get _passedBefore =>
      ref.read(progressProvider)[_exercise.id]?.passed ?? false;

  /// Ô mở được khi mọi ô đứng trước đã xong.
  bool _unlocked(Block b) {
    if (_passedBefore) return true;
    for (final x in _exercise.blocks) {
      if (x.label == b.label) return true;
      if (!_isDone(x)) return false;
    }
    return true;
  }

  /// Ô chưa xong đầu tiên (chỗ người học đang làm); null = xong hết.
  String? _frontier() {
    for (final b in _exercise.blocks) {
      if (!_isDone(b)) return b.label;
    }
    return null;
  }

  void _toggle(String label) {
    _activity();
    setState(() {
      _open = _open == label ? null : label;
      if (_open != null) _activeLabel = label;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Mở màn soạn code toàn màn hình cho ô [label]; đóng lại thì notebook
  /// hiện code mới (ô xong đã thu gọn, ô kế đã mở sẵn).
  Future<void> _openEditor(String label) async {
    _activity();
    setState(() => _activeLabel = label);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CellEditorPage(
          exercise: _exercise,
          label: label,
          codeOf: (l) => _cells[l] ?? '',
          onChanged: _onCellChanged,
          isDone: (l) => _isDone(_block(l)),
          nextAfter: _nextAfter,
          onActivity: _activity,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _activity() =>
      ref.read(sessionProvider(_exercise.id).notifier).activity();

  void _onCellChanged(String label, String code) {
    final block = _block(label);
    final wasDone = _isDone(block);
    _cells[label] = code;
    ref.read(progressProvider.notifier).saveDraft(_exercise.id, label, code);
    if (_emptyLabels.contains(label)) {
      setState(() => _emptyLabels = {..._emptyLabels}..remove(label));
    }
    final done = _isDone(block);
    if (done == wasDone) return;
    setState(() {}); // ✓ / khoá các ô sau đổi theo
    if (done && _open == label) _advanceFrom(label);
  }

  /// Ô chưa xong kế tiếp sau [label]; null = không còn.
  String? _nextAfter(String label) {
    final blocks = _exercise.blocks;
    final after = blocks.skip(blocks.indexWhere((b) => b.label == label) + 1);
    return after.where((b) => !_isDone(b)).firstOrNull?.label;
  }

  /// Ô vừa xong: thu gọn nó, mở ô chưa xong kế tiếp.
  void _advanceFrom(String label) {
    final next = _nextAfter(label);
    setState(() {
      _open = next;
      if (next != null) _activeLabel = next;
    });
  }

  Block _block(String label) =>
      _exercise.blocks.firstWhere((b) => b.label == label);

  Future<void> _run() async {
    if (_running) return;
    _activity();
    final empties = [
      for (final b in _exercise.blocks)
        if ((_cells[b.label] ?? '').trim().isEmpty) b.label,
    ];
    if (empties.isNotEmpty) {
      setState(() {
        _open = _frontier() ?? empties.first;
        _activeLabel = _open!;
        _emptyLabels = empties.toSet();
        _result = null;
        _merged = null;
      });
      _revealBottom();
      return;
    }
    final MergedCode merged;
    try {
      merged = mergeCells(_exercise, Map.of(_cells));
    } on ArgumentError {
      return; // Không xảy ra khi mọi ô đã có nội dung; không gọi judge.
    }
    setState(() {
      _running = true;
      _emptyLabels = {};
    });
    final result = await ref
        .read(judgeClientProvider)
        .run(_exercise.id, merged.code);
    if (!mounted) return;
    // Chỉ judge xác nhận passed mới tính là xong bài (INV-06).
    if (result.status == JudgeStatus.passed) {
      ref.read(progressProvider.notifier).markPassed(_exercise.id);
    }
    _activity();
    setState(() {
      _running = false;
      _runCount++;
      _result = result;
      _merged = merged;
    });
    _revealBottom();
  }

  /// Cuộn xuống cuối để thấy thông báo/kết quả vừa hiện.
  void _revealBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _hint() {
    _activity();
    final block = _block(_activeLabel);
    final used =
        ref.read(progressProvider)[_exercise.id]?.hintsUsed[block.label] ?? 0;
    if (used >= block.hints.length || used >= 3) return;
    ref.read(progressProvider.notifier).useHint(_exercise.id, block.label);
  }

  void _next() {
    final next = nextExerciseAfter(
      ref.read(contentIndexProvider),
      _exercise.id,
    );
    if (next != null) {
      context.pushReplacement('/exercise/${next.id}');
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  /// Ô có mặt trong lỗi: label của ô sai (INV-05) hoặc null.
  String? get _errorLabel {
    final r = _result;
    final m = _merged;
    if (r == null || m == null || r.status == JudgeStatus.passed) return null;
    return errorOrigin(m, r.error).label;
  }

  /// Fail/error mà không map được ô → gợi ý ô khác mọi đáp án chấp nhận.
  bool _recheck(Block b) {
    final r = _result;
    final m = _merged;
    if (r == null || m == null) return false;
    if (r.status != JudgeStatus.failed && r.status != JudgeStatus.error) {
      return false;
    }
    final o = errorOrigin(m, r.error);
    if (o.label != null || o.locked) return false;
    final mine = normalizeCode(_cells[b.label] ?? '');
    return !b.acceptedAnswers.any((a) => normalizeCode(a) == mine);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.palette;
    final progress = ref.watch(progressProvider.select((m) => m[_exercise.id]));
    final showPassed = _result?.status == JudgeStatus.passed;
    final labels = _exercise.blocks.map((b) => b.label).toList();
    var promptNo = 0;

    return Column(
      children: [
        Expanded(
          // Ít ô nên dựng hết một lượt (không lazy).
          child: SingleChildScrollView(
            key: const Key('code-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.all(AppSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final seg in _segments)
                  switch (seg) {
                    LockedSegment() => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.s4),
                      child: _LockedCell(
                        prompt: '[${++promptNo}]:',
                        code: seg.code,
                      ),
                    ),
                    TodoSegment() => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.s4),
                      child: _todoCell(context, seg.block, progress),
                    ),
                  },
                Text(
                  'Không cần thụt lề. Bấm Run, các ô tự ghép vào đúng chỗ '
                  'trong hàm rồi chạy test.',
                  key: const Key('indent-note'),
                  style: AppText.caption.copyWith(color: p.inkMuted),
                ),
                if (_emptyLabels.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.s2),
                  Text(
                    _emptyLabels.length == 1
                        ? 'Ô ${_emptyLabels.first} còn trống'
                        : 'Ô ${labels.where(_emptyLabels.contains).join(', ')} '
                              'còn trống',
                    key: const Key('empty-message'),
                    style: AppText.label.copyWith(color: p.danger),
                  ),
                ],
                if (_running)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpace.s4),
                    child: Center(
                      child: SizedBox(
                        key: Key('run-spinner'),
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_result != null && _merged != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.s4),
                    child: RunResultView(
                      result: _result!,
                      merged: _merged!,
                      runIndex: _runCount,
                      onRetry: _run,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(AppSpace.s2),
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            border: Border(
              top: BorderSide(color: p.outline.withValues(alpha: 0.4)),
            ),
          ),
          child: showPassed ? _passedBar() : _runBar(progress),
        ),
      ],
    );
  }

  Widget _passedBar() {
    final next = nextExerciseAfter(
      ref.read(contentIndexProvider),
      _exercise.id,
    );
    return Row(
      children: [
        GhostButton(
          key: const Key('edit-again'),
          label: 'Sửa lại',
          onPressed: () => setState(() {
            _result = null;
            _merged = null;
          }),
        ),
        const SizedBox(width: AppSpace.s2),
        Expanded(
          child: PrimaryButton(
            key: Key(next != null ? 'next-exercise' : 'back-to-list'),
            label: next != null ? 'Bài tiếp theo →' : 'Về danh sách',
            onPressed: _next,
          ),
        ),
      ],
    );
  }

  Widget _runBar(ExerciseProgress? progress) {
    final p = context.palette;
    final block = _block(_activeLabel);
    final used = progress?.hintsUsed[block.label] ?? 0;
    final canHint = used < 3 && used < block.hints.length;
    return Row(
      children: [
        ElevatedButton(
          key: const Key('hint-button'),
          onPressed: canHint ? _hint : null,
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text('Gợi ý ô ${block.label}'),
        ),
        const SizedBox(width: AppSpace.s2),
        Expanded(
          child: PrimaryButton(
            key: const Key('run-button'),
            label: 'Run tất cả',
            icon: Icons.play_arrow,
            onPressed: _running ? null : _run,
          ),
        ),
      ],
    );
  }

  Widget _todoCell(BuildContext context, Block b, ExerciseProgress? progress) {
    final label = b.label;
    final isError = _errorLabel == label;
    if (!isError && _open != label) {
      return _CollapsedCell(
        block: b,
        code: _cells[label] ?? '',
        done: _isDone(b),
        unlocked: _unlocked(b),
        lockedBy: _frontier(),
        onTap: () => _toggle(label),
      );
    }
    final p = context.palette;
    final isEmpty = _emptyLabels.contains(label);
    final used = progress?.hintsUsed[label] ?? 0;
    final where = cellWhere(_exercise, b);
    final prompt = _runCount > 0 ? '[$_runCount]:' : '[ ]:';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: Key('cell-$label-header'),
          onTap: () => _toggle(label),
          child: Padding(
            padding: const EdgeInsets.only(left: 52, bottom: AppSpace.s1),
            child: Row(
              children: [
                LabelTag(label),
                const SizedBox(width: AppSpace.s2),
                // Tiêu đề + "trong …" chiếm phần còn lại → icon nằm sát phải.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          b.title,
                          style: AppText.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (where.isNotEmpty) ...[
                        const SizedBox(width: AppSpace.s2),
                        Text(
                          where,
                          style: AppText.code.copyWith(
                            fontSize: 11,
                            color: p.inkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isDone(b))
                  Icon(Icons.check_circle, size: 16, color: p.primary),
                Icon(Icons.expand_less, size: 18, color: p.inkMuted),
              ],
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                prompt,
                style: AppText.code.copyWith(fontSize: 11, color: p.primary),
              ),
            ),
            Expanded(
              child: Container(
                key: Key('cell-$label-frame'),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6), // ôm ô code góc 4px
                  border: Border.all(
                    color: isError || isEmpty ? p.danger : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _CodePreview(
                  key: Key('cell-$label-field'),
                  code: _cells[label] ?? '',
                  onTap: () => _openEditor(label),
                ),
              ),
            ),
          ],
        ),
        if (isError)
          _note(
            'Lỗi ở ô $label: ${_result?.error?.message ?? ''}',
            Key('cell-$label-error'),
            p.danger,
          ),
        if (!isError && _recheck(b))
          _note(
            'Gợi ý: kiểm tra lại ô này (khác với đáp án mẫu).',
            Key('cell-$label-recheck'),
            p.inkMuted,
          ),
        for (var i = 0; i < used && i < b.hints.length; i++)
          _note(
            'Gợi ý ${i + 1}: ${b.hints[i]}',
            Key('hint-$label-$i'),
            p.accent,
          ),
      ],
    );
  }

  Widget _note(String text, Key key, Color color) => Padding(
    padding: const EdgeInsets.only(left: 52, top: AppSpace.s1),
    child: Text(
      text,
      key: key,
      style: AppText.caption.copyWith(color: color),
    ),
  );
}

/// Ô TODO đang thu gọn: đã xong (✓ + một dòng code, chạm để mở lại), hoặc
/// còn khoá (chờ ô trước xong).
class _CollapsedCell extends StatelessWidget {
  const _CollapsedCell({
    required this.block,
    required this.code,
    required this.done,
    required this.unlocked,
    required this.lockedBy,
    required this.onTap,
  });

  final Block block;
  final String code;
  final bool done;
  final bool unlocked;
  final String? lockedBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = block.label;
    final firstLine = code
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final subtitle = !unlocked
        ? 'Làm xong ô ${lockedBy ?? ''} để mở'
        : firstLine.isNotEmpty
        ? firstLine
        : 'Chạm để mở';
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Opacity(
        opacity: unlocked ? 1 : 0.5,
        child: InkWell(
          key: Key(unlocked ? 'cell-$label-collapsed' : 'cell-$label-locked'),
          onTap: unlocked ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.s2,
              vertical: AppSpace.s2,
            ),
            decoration: BoxDecoration(
              color: p.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: p.outline.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                LabelTag(label),
                const SizedBox(width: AppSpace.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        block.title,
                        style: AppText.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (unlocked && firstLine.isNotEmpty
                                    ? AppText.code.copyWith(fontSize: 12)
                                    : AppText.caption)
                                .copyWith(color: p.inkMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.s2),
                Icon(
                  !unlocked
                      ? Icons.lock_outline
                      : done
                      ? Icons.check_circle
                      : Icons.expand_more,
                  key: Key('cell-$label-status'),
                  size: 18,
                  color: done ? p.primary : p.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ô khoá: nền xám đậm hơn, chữ "có sẵn" + icon khoá, highlight Python.
class _LockedCell extends StatelessWidget {
  const _LockedCell({required this.prompt, required this.code});

  final String prompt;
  final String code;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = AppText.code.copyWith(color: p.ink);
    final styles = _codeStyles(p);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            prompt,
            style: AppText.code.copyWith(fontSize: 11, color: p.primary),
          ),
        ),
        Expanded(
          child: Container(
            key: const Key('locked-cell'),
            padding: const EdgeInsets.all(AppSpace.s2),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                p.ink.withValues(alpha: 0.08),
                p.surfaceRaised,
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 12, color: p.inkMuted),
                      const SizedBox(width: 4),
                      Text(
                        'có sẵn',
                        style: AppText.caption.copyWith(color: p.inkMuted),
                      ),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: base,
                    children: _spans(
                      hl.highlight.parse(code, language: 'python').nodes,
                      styles,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Map<String, TextStyle> _codeStyles(AppPalette p) => {
  'keyword': TextStyle(color: p.primary),
  'built_in': TextStyle(color: p.primary),
  'literal': TextStyle(color: p.primary),
  'number': TextStyle(color: p.primary),
  'string': TextStyle(color: p.inkMuted),
  'comment': TextStyle(color: p.outline, fontStyle: FontStyle.italic),
  'title': const TextStyle(fontWeight: FontWeight.w500),
};

/// Ô đang mở trong notebook: code (highlight + số dòng) chỉ để xem; chạm
/// → màn soạn code toàn màn hình.
class _CodePreview extends StatelessWidget {
  const _CodePreview({super.key, required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = AppText.code.copyWith(color: p.ink);
    final empty = code.trim().isEmpty;
    final lines = empty ? 1 : '\n'.allMatches(code).length + 1;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(p.ink.withValues(alpha: 0.04), p.surface),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: p.outline.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [for (var i = 1; i <= lines; i++) '$i'].join('\n'),
              textAlign: TextAlign.right,
              style: base.copyWith(color: p.inkMuted.withValues(alpha: 0.6)),
            ),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: empty
                  ? Text(
                      '# chạm để viết code',
                      style: base.copyWith(
                        color: p.inkMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : Text.rich(
                      TextSpan(
                        style: base,
                        children: _spans(
                          hl.highlight.parse(code, language: 'python').nodes,
                          _codeStyles(p),
                        ),
                      ),
                    ),
            ),
            Icon(Icons.open_in_full, size: 14, color: p.inkMuted),
          ],
        ),
      ),
    );
  }
}

List<InlineSpan> _spans(List<hl.Node>? nodes, Map<String, TextStyle> styles) {
  if (nodes == null) return const [];
  return [
    for (final n in nodes)
      TextSpan(
        text: n.value,
        style: n.className == null ? null : styles[n.className],
        children: _spans(n.children, styles),
      ),
  ];
}
