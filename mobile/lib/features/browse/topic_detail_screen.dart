/// Màn Topic detail: nhóm exercise theo file, hiện trạng thái từng bài.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/seed.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../exercise/session_providers.dart';
import 'exercise_row.dart';

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
                    _FileHeader(file: file),
                    const SizedBox(height: AppSpace.s2),
                    for (final exercise in file.exercises) ...[
                      ExerciseRow(
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

/// Tên file; nếu file còn được dùng ở theme khác thì hiện nhãn "Dùng ở N
/// theme" và chạm để mở màn File cross-cut.
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.file});

  final CodeFile file;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final themeCount =
        locateFilesNamed(file.name).map((u) => u.theme.id).toSet().length;
    final name = Text(file.name, style: AppText.code.copyWith(color: p.ink));
    if (themeCount < 2) return name;

    return InkWell(
      key: Key('file-${file.id}'),
      onTap: () => context.push('/file/${Uri.encodeComponent(file.name)}'),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
        child: Row(
          children: [
            Expanded(child: name),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.s2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: p.primary),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Dùng ở $themeCount theme',
                style: AppText.caption.copyWith(color: p.primary),
              ),
            ),
            const SizedBox(width: AppSpace.s1),
            Icon(Icons.chevron_right, size: 18, color: p.inkMuted),
          ],
        ),
      ),
    );
  }
}
