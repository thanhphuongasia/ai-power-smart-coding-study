/// Màn Topic detail: nhóm exercise theo file, hiện trạng thái từng bài.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/seed.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../exercise/session_controller.dart';
import '../exercise/session_providers.dart';

class TopicDetailScreen extends ConsumerWidget {
  const TopicDetailScreen(this.topicId, {super.key});

  final String topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final located = _locateTopic(topicId);
    final theme = located.theme;
    final topic = located.topic;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: topic.name,
              subtitle: '${theme.name} › ${topic.name}',
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  for (final file in topic.files) ...[
                    Text(
                      file.name,
                      style: AppText.code.copyWith(color: AppColors.ink),
                    ),
                    const SizedBox(height: AppSpace.s2),
                    for (final exercise in file.exercises) ...[
                      _ExerciseRow(
                        exercise: exercise,
                        progress: progress[exercise.id],
                      ),
                      const SizedBox(height: AppSpace.s2),
                    ],
                    const SizedBox(height: AppSpace.s4),
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

({StudyTheme theme, Topic topic}) _locateTopic(String topicId) {
  for (final theme in seedThemes) {
    for (final topic in theme.topics) {
      if (topic.id == topicId) {
        return (theme: theme, topic: topic);
      }
    }
  }
  throw StateError('Không tìm thấy topic với id: $topicId');
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.progress});

  final Exercise exercise;
  final ExerciseProgress? progress;

  @override
  Widget build(BuildContext context) {
    final completed = progress?.completedBlocks ?? 0;
    final total = exercise.blocks.length;
    final isDone = total > 0 && completed >= total;
    final isStarted = completed > 0 && !isDone;

    final String statusText;
    final IconData statusIcon;
    final Color statusColor;
    if (isDone) {
      statusText = 'Đã xong';
      statusIcon = Icons.check_circle;
      statusColor = AppColors.primary;
    } else if (isStarted) {
      statusText = 'Đang dở';
      statusIcon = Icons.timelapse;
      statusColor = AppColors.ink;
    } else {
      statusText = 'Mới';
      statusIcon = Icons.circle_outlined;
      statusColor = AppColors.inkMuted;
    }

    return SurfaceCard(
      key: Key('exercise-${exercise.id}'),
      onTap: () => context.push('/exercise/${exercise.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Row(
          children: [
            Icon(statusIcon, size: 18, color: statusColor),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${exercise.functionName}()',
                    style: AppText.code.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: AppSpace.s1),
                  Text(
                    exercise.title,
                    style: AppText.body.copyWith(color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.s4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  statusText,
                  style: AppText.label.copyWith(color: statusColor),
                ),
                const SizedBox(height: AppSpace.s1),
                Text(
                  '$completed/$total block',
                  style: AppText.caption.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
