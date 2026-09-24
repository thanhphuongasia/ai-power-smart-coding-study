/// Màn Theme detail: mô tả theme + danh sách topic bên trong.
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
import 'home_screen.dart' show completedBlocksIn, totalBlocksIn;

class ThemeDetailScreen extends ConsumerWidget {
  const ThemeDetailScreen(this.themeId, {super.key});

  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final theme = seedThemes.firstWhere(
      (t) => t.id == themeId,
      orElse: () => throw StateError('Không tìm thấy theme với id: $themeId'),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: theme.name,
              subtitle: theme.description,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  Wrap(
                    spacing: AppSpace.s2,
                    runSpacing: AppSpace.s2,
                    children: [for (final tag in theme.tags) TagChip(tag)],
                  ),
                  const SizedBox(height: AppSpace.s6),
                  const SectionLabel('Chủ đề nhỏ'),
                  for (final topic in theme.topics) ...[
                    _TopicCard(topic: topic, progress: progress),
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

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.progress});

  final Topic topic;
  final Map<String, ExerciseProgress> progress;

  @override
  Widget build(BuildContext context) {
    final exercises = [for (final file in topic.files) ...file.exercises];
    final totalBlocks = totalBlocksIn(exercises);
    final doneBlocks = completedBlocksIn(exercises, progress);

    return SurfaceCard(
      key: Key('topic-${topic.id}'),
      onTap: () => context.push('/topic/${topic.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(topic.name, style: AppText.title),
            const SizedBox(height: AppSpace.s1),
            Text(
              topic.description,
              style: AppText.body.copyWith(color: context.palette.inkMuted),
            ),
            const SizedBox(height: AppSpace.s2),
            Text(
              '${exercises.length} bài tập',
              style: AppText.caption.copyWith(color: context.palette.inkMuted),
            ),
            const SizedBox(height: AppSpace.s2),
            ThinProgressBar(
              value: totalBlocks == 0 ? 0 : doneBlocks / totalBlocks,
            ),
          ],
        ),
      ),
    );
  }
}
