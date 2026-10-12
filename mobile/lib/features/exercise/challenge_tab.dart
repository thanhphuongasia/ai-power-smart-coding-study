/// Tab Challenge: đề bài, "Dùng để làm gì?", ví dụ nhỏ / dự án thật và danh
/// sách ô cần viết.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/content_providers.dart';
import '../../domain/class_scope.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import 'class_diagram.dart';

/// Index tab Code trong TabBar của ExerciseScreen.
const int kCodeTabIndex = 1;

class ChallengeTab extends ConsumerStatefulWidget {
  const ChallengeTab({
    super.key,
    required this.exercise,
    this.showGoCode = true,
  });

  final Exercise exercise;

  /// `false` ở bố cục chia đôi (không có tab Code để nhảy tới): ẩn nút
  /// `start-coding` — editor đã nằm sẵn ở cột phải.
  final bool showGoCode;

  @override
  ConsumerState<ChallengeTab> createState() => _ChallengeTabState();
}

class _ChallengeTabState extends ConsumerState<ChallengeTab> {
  bool _project = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final challenge = widget.exercise.challenge;
    final blocks = widget.exercise.blocks;
    final example = _project ? challenge.project : challenge.small;
    final scope = classScope(widget.exercise);
    final diagram = scope == null
        ? null
        : ref
              .watch(contentIndexProvider)
              .locateExercise(widget.exercise.id)
              .theme
              .diagram;
    final showDiagram =
        scope != null && diagram!.classNamed(scope.className) != null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const Key('challenge-scroll'),
            padding: const EdgeInsets.all(AppSpace.s4),
            children: [
              const SectionLabel('ĐỀ BÀI'),
              const SizedBox(height: AppSpace.s2),
              Text(challenge.statement, style: AppText.body),
              const SizedBox(height: AppSpace.s4),
              Container(
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
                        Icon(Icons.track_changes, size: 18, color: p.primary),
                        const SizedBox(width: AppSpace.s2),
                        Text('Dùng để làm gì?', style: AppText.label),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s2),
                    Text(
                      challenge.motivation,
                      key: const Key('challenge-motivation'),
                      style: AppText.body.copyWith(color: p.inkMuted),
                    ),
                    const SizedBox(height: AppSpace.s4),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        key: const Key('example-switch'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, label: Text('Ví dụ nhỏ')),
                          ButtonSegment(value: true, label: Text('Dự án thật')),
                        ],
                        selected: {_project},
                        onSelectionChanged: (s) =>
                            setState(() => _project = s.first),
                      ),
                    ),
                    const SizedBox(height: AppSpace.s2),
                    _ExampleBox(example: example),
                  ],
                ),
              ),
              if (showDiagram) ...[
                const SizedBox(height: AppSpace.s4),
                const SectionLabel('SƠ ĐỒ CLASS'),
                ClassDiagramView(diagram: diagram, scope: scope),
              ],
              const SizedBox(height: AppSpace.s6),
              SectionLabel('BẠN CẦN VIẾT ${blocks.length} Ô'),
              const SizedBox(height: AppSpace.s2),
              for (final b in blocks)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s2),
                  child: Row(
                    children: [
                      LabelTag(b.label),
                      const SizedBox(width: AppSpace.s2),
                      Expanded(child: Text(b.title, style: AppText.body)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (widget.showGoCode)
          Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                key: const Key('start-coding'),
                label: 'Bắt đầu code →',
                onPressed: () =>
                    DefaultTabController.of(context).animateTo(kCodeTabIndex),
              ),
            ),
          ),
      ],
    );
  }
}

/// Thẻ nhãn ô (A/B/C): nền accent, chữ mono.
class LabelTag extends StatelessWidget {
  const LabelTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: 2),
      decoration: BoxDecoration(
        color: p.accent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(label, style: AppText.code.copyWith(color: p.onAccent)),
    );
  }
}

class _ExampleBox extends StatelessWidget {
  const _ExampleBox({required this.example});

  final Example example;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('example-box'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s2),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (example.caption.isNotEmpty)
            Text(
              example.caption,
              style: AppText.caption.copyWith(color: p.inkMuted),
            ),
          if (example.caption.isNotEmpty) const SizedBox(height: AppSpace.s1),
          Text(example.input, style: AppText.code.copyWith(color: p.ink)),
          const SizedBox(height: AppSpace.s1),
          Text(
            '→ ${example.output}',
            style: AppText.code.copyWith(color: p.primary),
          ),
          if (example.note != null) ...[
            const SizedBox(height: AppSpace.s1),
            Text(
              example.note!,
              style: AppText.caption.copyWith(color: p.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
