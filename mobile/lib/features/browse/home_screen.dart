/// Màn Home: điểm vào chính — tiếp tục bài đang dở (nếu có) và danh sách
/// theme để chọn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/theme_mode.dart';
import '../../data/seed.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../exercise/session_controller.dart';
import '../exercise/session_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final inProgress = ref.watch(inProgressExerciseProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.s4),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Luyện tập hôm nay', style: AppText.display),
                ),
                IconButton(
                  key: const Key('admin-button'),
                  icon: const Icon(Icons.fact_check_outlined),
                  tooltip: 'Duyệt nội dung',
                  onPressed: () => context.push('/admin'),
                ),
                const ThemeModeButton(),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            if (inProgress != null) ...[
              _ContinueCard(exercise: inProgress, progress: progress),
              const SizedBox(height: AppSpace.s6),
            ],
            const SectionLabel('Chủ đề'),
            for (final theme in seedThemes) ...[
              _ThemeCard(theme: theme, progress: progress),
              const SizedBox(height: AppSpace.s4),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.exercise, required this.progress});

  final Exercise exercise;
  final Map<String, ExerciseProgress> progress;

  @override
  Widget build(BuildContext context) {
    final completed = progress[exercise.id]?.completedBlocks ?? 0;
    final total = exercise.blocks.length;

    return SurfaceCard(
      key: const Key('continue-card'),
      onTap: () => context.push('/exercise/${exercise.id}'),
      highlighted: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Tiếp tục'),
                  Text(exercise.title, style: AppText.title),
                  const SizedBox(height: AppSpace.s1),
                  Text(
                    'Tiếp tục Block ${completed + 1}/$total',
                    style: AppText.body,
                  ),
                  const SizedBox(height: AppSpace.s1),
                  Text(
                    'Đã xong $completed/$total',
                    style: AppText.body.copyWith(color: context.palette.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.s2),
                  ThinProgressBar(value: total == 0 ? 0 : completed / total),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.s4),
            Icon(Icons.arrow_forward, color: context.palette.ink),
          ],
        ),
      ),
    );
  }
}

/// Số block đã xong / tổng số block trong một tập exercise. Dùng chung cho
/// tiến độ theme (Home) và tiến độ topic (Theme detail) — cùng đơn vị "block"
/// để người dùng không nhầm với "n/m bài tập".
int completedBlocksIn(
  Iterable<Exercise> exercises,
  Map<String, ExerciseProgress> progress,
) {
  var done = 0;
  for (final exercise in exercises) {
    final completed = progress[exercise.id]?.completedBlocks ?? 0;
    done += completed.clamp(0, exercise.blocks.length);
  }
  return done;
}

int totalBlocksIn(Iterable<Exercise> exercises) =>
    exercises.fold<int>(0, (sum, exercise) => sum + exercise.blocks.length);

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.progress});

  final StudyTheme theme;
  final Map<String, ExerciseProgress> progress;

  @override
  Widget build(BuildContext context) {
    final exercises = [
      for (final topic in theme.topics)
        for (final file in topic.files) ...file.exercises,
    ];
    final total = totalBlocksIn(exercises);
    final done = completedBlocksIn(exercises, progress);

    return SurfaceCard(
      key: Key('theme-${theme.id}'),
      onTap: () => context.push('/theme/${theme.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(theme.name, style: AppText.title),
            const SizedBox(height: AppSpace.s1),
            Text(
              theme.description,
              style: AppText.body.copyWith(color: context.palette.inkMuted),
            ),
            const SizedBox(height: AppSpace.s2),
            Wrap(
              spacing: AppSpace.s2,
              runSpacing: AppSpace.s2,
              children: [for (final tag in theme.tags) TagChip(tag)],
            ),
            const SizedBox(height: AppSpace.s4),
            Row(
              children: [
                Expanded(
                  child: ThinProgressBar(value: total == 0 ? 0 : done / total),
                ),
                const SizedBox(width: AppSpace.s2),
                Text(
                  '$done/$total block',
                  style: AppText.caption.copyWith(color: context.palette.inkMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
