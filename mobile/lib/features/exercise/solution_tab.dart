/// Tab Solution: mở lời giải từng ô một. Mở ô nào thì ô đó mất điểm (INV-07)
/// — ghi qua `ProgressController.viewSolution`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight/highlight.dart' show Node, highlight;

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import 'challenge_tab.dart';
import 'code_input.dart' show codeSyntaxStyles;
import 'session_providers.dart';

class SolutionTab extends ConsumerWidget {
  const SolutionTab({
    super.key,
    required this.exercise,
    this.showGoCode = true,
  });

  final Exercise exercise;

  /// `false` ở bố cục chia đôi: ẩn nút `back-to-code` (không có tab Code).
  final bool showGoCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final viewed = ref.watch(
      progressProvider.select(
        (m) => m[exercise.id]?.solutionViewed ?? const <String>{},
      ),
    );

    return ListView(
      key: const Key('solution-scroll'),
      padding: const EdgeInsets.all(AppSpace.s4),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.s2),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: p.ink),
              const SizedBox(width: AppSpace.s2),
              const Expanded(
                child: Text(
                  'Mở từng ô một. Ô nào đã xem lời giải sẽ không tính điểm, '
                  'bạn vẫn phải tự gõ lại ở tab Code.',
                  key: Key('solution-warning'),
                  style: AppText.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s4),
        for (final block in exercise.blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s4),
            child: _SolutionCard(
              block: block,
              revealed: viewed.contains(block.label),
              onReveal: () {
                ref
                    .read(progressProvider.notifier)
                    .viewSolution(exercise.id, block.label);
                ref.read(sessionProvider(exercise.id).notifier).activity();
              },
            ),
          ),
        if (showGoCode)
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              key: const Key('back-to-code'),
              label: 'Quay lại tab Code để gõ',
              onPressed: () =>
                  DefaultTabController.of(context).animateTo(kCodeTabIndex),
            ),
          ),
      ],
    );
  }
}

class _SolutionCard extends StatelessWidget {
  const _SolutionCard({
    required this.block,
    required this.revealed,
    required this.onReveal,
  });

  final Block block;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: Key('solution-card-${block.label}'),
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        border: Border.all(color: p.outline.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LabelTag(block.label),
              const SizedBox(width: AppSpace.s2),
              Expanded(child: Text(block.title, style: AppText.label)),
            ],
          ),
          const SizedBox(height: AppSpace.s2),
          if (!revealed)
            _DashedButton(
              key: Key('reveal-${block.label}'),
              label: 'Hiện lời giải ô ${block.label}',
              onTap: onReveal,
            )
          else ...[
            _CodeBlock(
              key: Key('solution-code-${block.label}'),
              code: block.acceptedAnswers.first,
            ),
            if (block.explanation.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s2),
              Text(
                block.explanation,
                key: Key('solution-explanation-${block.label}'),
                style: AppText.body.copyWith(color: p.inkMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DashedButton extends StatelessWidget {
  const _DashedButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: CustomPaint(
        painter: _DashedBorderPainter(p.outline),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s2 + 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility_outlined, size: 18, color: p.inkMuted),
              const SizedBox(width: AppSpace.s2),
              Flexible(
                child: Text(
                  label,
                  style: AppText.label.copyWith(color: p.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppRadius.md),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// Code Python chỉ đọc (không chọn/chép), tô màu cùng bảng token với editor.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final styles = codeSyntaxStyles(p);
    final base = AppText.code.copyWith(color: p.codeInk);
    final nodes = highlight.parse(code, language: 'python').nodes ?? const [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s2),
      decoration: BoxDecoration(
        color: p.codeSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(style: base, children: _spans(nodes, styles)),
          softWrap: false,
        ),
      ),
    );
  }

  List<TextSpan> _spans(List<Node> nodes, Map<String, TextStyle> styles) {
    return [
      for (final n in nodes)
        TextSpan(
          text: n.value,
          style: n.className == null ? null : styles[n.className],
          children: n.children == null ? null : _spans(n.children!, styles),
        ),
    ];
  }
}
