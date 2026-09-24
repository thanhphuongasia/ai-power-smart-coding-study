/// Màn Block list: stepper B1..Bn theo tiến trình, banner "làm dở" và danh
/// sách block (đã xong hiện code, đang làm hiện đề, khoá thì mờ).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../app/theme.dart';
import '../../data/seed.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import 'session_controller.dart';
import 'session_providers.dart';

class BlockListScreen extends ConsumerWidget {
  const BlockListScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = exerciseById(exerciseId);
    final located = locateExercise(exerciseId);
    final progressMap = ref.watch(progressProvider);
    final progress = progressMap[exerciseId] ??
        const ExerciseProgress(completedBlocks: 0, drafts: {}, hintsUsed: {});
    // Chỉ để hiện đồng hồ nếu phiên đã được bắt đầu ở màn Cell — Block list
    // không tự start(), chỉ đọc trạng thái hiện có.
    final session = ref.watch(sessionProvider(exerciseId));

    final total = exercise.blocks.length;
    final completed = progress.completedBlocks;
    final hasDraftInProgress = completed > 0 && completed < total;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: exercise.title,
              subtitle:
                  '${located.theme.name} › ${located.topic.name} › ${located.file.name}',
              trailing: TimerPill(session.elapsed),
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  _Stepper(exercise: exercise, progress: progress),
                  const SizedBox(height: AppSpace.s6),
                  if (hasDraftInProgress) ...[
                    _ContinueBanner(
                      exerciseId: exerciseId,
                      blockIndex: completed,
                    ),
                    const SizedBox(height: AppSpace.s4),
                  ],
                  const SectionLabel('Các block'),
                  for (var i = 0; i < total; i++) ...[
                    _BlockCard(
                      exerciseId: exerciseId,
                      index: i,
                      block: exercise.blocks[i],
                      status: blockStatusOf(progress, i),
                    ),
                    const SizedBox(height: AppSpace.s2),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.exercise, required this.progress});

  final Exercise exercise;
  final ExerciseProgress progress;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.s2,
      runSpacing: AppSpace.s2,
      children: [
        for (var i = 0; i < exercise.blocks.length; i++)
          _StepChip(index: i, status: blockStatusOf(progress, i)),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.index, required this.status});

  final int index;
  final BlockStatus status;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    switch (status) {
      case BlockStatus.done:
        icon = Icons.check_circle;
        color = AppColors.primary;
      case BlockStatus.active:
        icon = Icons.play_circle_fill;
        color = AppColors.ink;
      case BlockStatus.locked:
        icon = Icons.lock;
        color = AppColors.inkMuted;
    }

    return Container(
      key: Key('step-$index'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s2,
        vertical: AppSpace.s1,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: status == BlockStatus.active ? AppColors.primary : color,
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpace.s1),
          Text('B${index + 1}', style: AppText.label.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _ContinueBanner extends StatelessWidget {
  const _ContinueBanner({required this.exerciseId, required this.blockIndex});

  final String exerciseId;
  final int blockIndex;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      highlighted: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Bạn đang làm dở Block ${blockIndex + 1}',
                style: AppText.body.copyWith(color: AppColors.ink),
              ),
            ),
            const SizedBox(width: AppSpace.s4),
            PrimaryButton(
              key: const Key('block-list-continue-button'),
              label: 'Tiếp tục',
              icon: Icons.arrow_forward,
              onPressed: () =>
                  context.push('/exercise/$exerciseId/block/$blockIndex'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.exerciseId,
    required this.index,
    required this.block,
    required this.status,
  });

  final String exerciseId;
  final int index;
  final Block block;
  final BlockStatus status;

  @override
  Widget build(BuildContext context) {
    final tappable = status != BlockStatus.locked;

    Widget content;
    switch (status) {
      case BlockStatus.done:
        final code = block.acceptedAnswers.isNotEmpty
            ? block.acceptedAnswers.first
            : '';
        final indented = code
            .split('\n')
            .map((line) => '${' ' * (block.indentLevel * 4)}$line')
            .join('\n');
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, size: 16, color: AppColors.primary),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: Text(
                indented,
                style: AppText.code.copyWith(color: AppColors.inkMuted),
              ),
            ),
          ],
        );
      case BlockStatus.active:
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.play_circle_fill, size: 16, color: AppColors.ink),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: Text(
                block.prompt,
                style: AppText.body.copyWith(color: AppColors.ink),
              ),
            ),
          ],
        );
      case BlockStatus.locked:
        content = Row(
          children: [
            const Icon(Icons.lock, size: 16, color: AppColors.inkMuted),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: Text(
                'Mở khoá sau Block $index',
                style: AppText.body.copyWith(color: AppColors.inkMuted),
              ),
            ),
          ],
        );
    }

    final card = SurfaceCard(
      key: Key('block-card-$index'),
      highlighted: status == BlockStatus.active,
      onTap: tappable
          ? () => context.push('/exercise/$exerciseId/block/$index')
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Row(
          children: [
            Text('B${index + 1}', style: AppText.label.copyWith(color: AppColors.inkMuted)),
            const SizedBox(width: AppSpace.s2),
            Expanded(child: content),
          ],
        ),
      ),
    );

    return status == BlockStatus.locked
        ? Opacity(opacity: 0.5, child: card)
        : card;
  }
}
