/// Một dòng exercise: tên hàm, trạng thái (Đã xong / Đang dở / Mới / Khoá) và
/// số ô. Chạm để mở bài; bài khoá (INV-08) không điều hướng.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../exercise/session_controller.dart';
import '../exercise/session_providers.dart';

/// Trạng thái hiển thị: Khoá > Đã xong > Đang dở > Mới. Done = `passed`
/// (INV-06), đang dở = `ExerciseProgress.inProgress` (INV-09), khoá theo
/// [exerciseUnlockedProvider] (INV-08) — không tự viết lại điều kiện nào.
class ExerciseRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final total = exercise.blocks.length;
    final isDone = progress?.passed ?? false;
    final isStarted = progress?.inProgress ?? false;
    // Bài đã passed luôn coi là mở (vd seed pass trước bài trước nó).
    final isLocked =
        !isDone && !ref.watch(exerciseUnlockedProvider(exercise.id));

    final String statusText;
    final IconData statusIcon;
    final Color statusColor;
    if (isLocked) {
      statusText = 'Khoá';
      statusIcon = Icons.lock_outline;
      statusColor = context.palette.inkMuted;
    } else if (isDone) {
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

    final card = SurfaceCard(
      key: Key('exercise-${exercise.id}'),
      onTap: isLocked ? null : () => context.push('/exercise/${exercise.id}'),
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
                    '${exercise.qualifiedName}()',
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
                  '$total ô',
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
    if (!isLocked) return card;
    return Tooltip(message: 'Hoàn thành bài trước để mở', child: card);
  }
}
