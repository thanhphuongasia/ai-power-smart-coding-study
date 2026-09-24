/// Một dòng exercise: tên hàm, trạng thái (Đã xong / Đang dở / Mới) và số
/// block đã xong. Chạm để mở Block list.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../exercise/session_controller.dart';

class ExerciseRow extends StatelessWidget {
  const ExerciseRow({
    super.key,
    required this.exercise,
    required this.progress,
    this.subtitle,
  });

  final Exercise exercise;
  final ExerciseProgress? progress;

  /// Dòng phụ dưới tên hàm; mặc định là tiêu đề exercise.
  final String? subtitle;

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
      statusColor = context.palette.primary;
    } else if (isStarted) {
      statusText = 'Đang dở';
      statusIcon = Icons.timelapse;
      statusColor = context.palette.ink;
    } else {
      statusText = 'Mới';
      statusIcon = Icons.circle_outlined;
      statusColor = context.palette.inkMuted;
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
                    style: AppText.code.copyWith(color: context.palette.ink),
                  ),
                  const SizedBox(height: AppSpace.s1),
                  Text(
                    subtitle ?? exercise.title,
                    style: AppText.body.copyWith(
                      color: context.palette.inkMuted,
                    ),
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
                  style: AppText.caption.copyWith(
                    color: context.palette.inkMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
