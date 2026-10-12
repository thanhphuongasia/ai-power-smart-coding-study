/// Màn soạn code toàn màn hình cho ô TODO: chỉ tên ô, editor và thanh phím —
/// header, tab, ô khác, nút Run đều ẩn để bàn phím còn chỗ cho code.
/// Ô khớp đáp án → chuyển luôn sang ô kế ngay trên màn này; hết ô → đóng.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/merge.dart';
import '../../domain/models.dart';
import 'challenge_tab.dart' show LabelTag;
import 'code_input.dart';
import 'session_controller.dart';
import 'session_providers.dart';

/// Vị trí ô trong hàm, hiện cạnh tiêu đề ô.
String cellWhere(Exercise e, Block b) => cellLocation(e, b.label);

/// Route toàn màn hình: Scaffold + [CellEditorBody]. Xong hết ô → pop.
class CellEditorPage extends StatelessWidget {
  const CellEditorPage({
    super.key,
    required this.exercise,
    required this.label,
    required this.codeOf,
    required this.onChanged,
    required this.isDone,
    required this.nextAfter,
    required this.onActivity,
  });

  final Exercise exercise;
  final String label;
  final String Function(String label) codeOf;
  final void Function(String label, String code) onChanged;
  final bool Function(String label) isDone;

  /// Ô chưa xong kế tiếp sau [label]; null = không còn ô nào.
  final String? Function(String label) nextAfter;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.surfaceRaised,
      body: SafeArea(
        child: CellEditorBody(
          exercise: exercise,
          label: label,
          codeOf: codeOf,
          onChanged: onChanged,
          isDone: isDone,
          nextAfter: nextAfter,
          onActivity: onActivity,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// Phần ruột của editor một ô (không Scaffold): dùng chung cho route
/// [CellEditorPage] và cho editor inline trong notebook (INV-06: chấm/lưu đều
/// qua callback của [CodeTab], không có logic thứ hai ở đây).
///
/// Chế độ route (`inline: false`): đầy đủ header + thanh phím; ô khớp đáp án →
/// tự sang ô kế, hết ô → [onClose].
/// Chế độ inline: chỉ editor (header, gợi ý, thanh phím do notebook lo); ô khớp
/// thì notebook tự mở ô kế (body này bị thay bằng body của ô kế).
class CellEditorBody extends ConsumerStatefulWidget {
  const CellEditorBody({
    super.key,
    required this.exercise,
    required this.label,
    required this.codeOf,
    required this.onChanged,
    required this.isDone,
    required this.nextAfter,
    required this.onActivity,
    this.onClose,
    this.inline = false,
    this.toolbar,
  });

  final Exercise exercise;
  final String label;
  final String Function(String label) codeOf;
  final void Function(String label, String code) onChanged;
  final bool Function(String label) isDone;
  final String? Function(String label) nextAfter;
  final VoidCallback onActivity;

  /// Đóng editor (route: pop). Null → nút "Xong" ẩn.
  final VoidCallback? onClose;
  final bool inline;

  /// Thanh phím dùng chung do bên ngoài giữ (inline). Null → tự tạo và tự vẽ
  /// [CodeToolbar] ở đáy.
  final CodeToolbarController? toolbar;

  @override
  ConsumerState<CellEditorBody> createState() => _CellEditorBodyState();
}

class _CellEditorBodyState extends ConsumerState<CellEditorBody> {
  CodeToolbarController? _ownToolbar;
  CodeToolbarController get _toolbar =>
      widget.toolbar ?? (_ownToolbar ??= CodeToolbarController());
  // Mỗi ô một node: editor ô mới dựng lên lúc node ô cũ còn focus thì sẽ
  // đăng ký vào thanh phím giữa lúc build.
  final Map<String, FocusNode> _nodes = {};
  late String _label = widget.label;

  /// Ô vừa khớp đáp án, để báo "✓ Ô A đúng" khi đã sang ô kế.
  String? _doneLabel;

  @override
  void initState() {
    super.initState();
    _focusSoon();
  }

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    _ownToolbar?.dispose();
    super.dispose();
  }

  FocusNode _node(String label) =>
      _nodes.putIfAbsent(label, () => FocusNode(debugLabel: 'editor-$label'));

  void _focusSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _node(_label).requestFocus();
  });

  Block get _block =>
      widget.exercise.blocks.firstWhere((b) => b.label == _label);

  void _changed(String code) {
    widget.onChanged(_label, code);
    if (widget.inline || !widget.isDone(_label)) return;
    final next = widget.nextAfter(_label);
    if (next == null) {
      widget.onClose?.call();
      return;
    }
    setState(() {
      _doneLabel = _label;
      _label = next;
    });
    _focusSoon();
  }

  void _hint() {
    widget.onActivity();
    ref.read(progressProvider.notifier).useHint(widget.exercise.id, _label);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final block = _block;
    final index = widget.exercise.blocks.indexOf(block);
    final known = knownIdentifiersFor(widget.exercise, index);
    final used = ref.watch(
      progressProvider.select(
        (m) => m[widget.exercise.id]?.hintsUsed[_label] ?? 0,
      ),
    );
    final canHint = used < 3 && used < block.hints.length;
    final where = cellWhere(widget.exercise, block);
    final inline = widget.inline;

    final input = CodeInput(
      key: ValueKey(_label),
      keyPrefix: 'editor',
      showBars: false,
      toolbar: _toolbar,
      focusNode: _node(_label),
      initialCode: widget.codeOf(_label),
      knownIdentifiers: known,
      vocab: block.vocab,
      answers: block.acceptedAnswers,
      ghost: true,
      onChanged: _changed,
      onActivity: widget.onActivity,
    );

    if (inline) return input;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.s4,
            AppSpace.s2,
            AppSpace.s2,
            AppSpace.s2,
          ),
          child: Row(
            children: [
              LabelTag(_label),
              const SizedBox(width: AppSpace.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.title,
                      key: const Key('editor-title'),
                      style: AppText.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (where.isNotEmpty)
                      Text(
                        where,
                        style: AppText.code.copyWith(
                          fontSize: 11,
                          color: p.inkMuted,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('editor-hint'),
                tooltip: 'Gợi ý ô $_label',
                onPressed: canHint ? _hint : null,
                icon: Icon(Icons.lightbulb_outline, color: p.accent),
              ),
              if (widget.onClose != null)
                TextButton(
                  key: const Key('editor-done'),
                  onPressed: widget.onClose,
                  child: const Text('Xong'),
                ),
            ],
          ),
        ),
        if (_doneLabel != null)
          _line(
            '✓ Ô $_doneLabel đúng — tiếp ô $_label',
            const Key('editor-advanced'),
            p.primary,
          ),
        for (var i = 0; i < used && i < block.hints.length; i++)
          _line(
            'Gợi ý ${i + 1}: ${block.hints[i]}',
            Key('editor-hint-$i'),
            p.accent,
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.s2,
              AppSpace.s1,
              AppSpace.s2,
              AppSpace.s2,
            ),
            child: input,
          ),
        ),
        CodeToolbar(
          controller: _toolbar,
          knownIdentifiers: known,
          vocab: block.vocab,
          ghost: true,
        ),
      ],
    );
  }

  Widget _line(String text, Key key, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.s4,
      0,
      AppSpace.s4,
      AppSpace.s1,
    ),
    child: Text(
      text,
      key: key,
      style: AppText.caption.copyWith(color: color),
    ),
  );
}
