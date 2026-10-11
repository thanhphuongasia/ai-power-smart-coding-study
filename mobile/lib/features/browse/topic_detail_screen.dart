/// Màn Topic detail: nhóm exercise theo file, hiện trạng thái từng bài.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/content_providers.dart';
import '../../domain/content.dart';
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
    final content = ref.watch(contentIndexProvider);
    final located = content.locateTopic(topicId);
    if (located == null) {
      throw StateError('Không tìm thấy topic với id: $topicId');
    }
    final theme = located.theme;
    final topic = located.topic;
    final breadcrumb = [
      theme.name,
      for (final m in content.modulePath(topicId)) m.name,
    ].join(' › ');

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: topic.name,
              subtitle: breadcrumb,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  for (final module in topic.modules) ...[
                    _ModuleCard(module: module),
                    const SizedBox(height: AppSpace.s4),
                  ],
                  for (final file in topic.files) ...[
                    _FileHeader(file: file, content: content),
                    const SizedBox(height: AppSpace.s2),
                    for (var i = 0; i < file.exercises.length; i++) ...[
                      if (file.exercises[i].className != null &&
                          (i == 0 ||
                              file.exercises[i - 1].className !=
                                  file.exercises[i].className)) ...[
                        _ClassHeader(
                          fileId: file.id,
                          className: file.exercises[i].className!,
                        ),
                        const SizedBox(height: AppSpace.s2),
                      ],
                      ExerciseRow(
                        exercise: file.exercises[i],
                        progress: progress[file.exercises[i].id],
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

/// Tên file; nếu file còn được dùng ở theme khác thì hiện nhãn "Dùng ở N
/// theme" và chạm để mở màn File cross-cut.
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.file, required this.content});

  final CodeFile file;
  final Content content;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final themeCount = content
        .locateFilesNamed(file.name)
        .map((u) => u.theme.id)
        .toSet()
        .length;
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

/// Thẻ module con: tên, mô tả, số bài (gồm cả module lồng bên trong).
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final Topic module;

  @override
  Widget build(BuildContext context) {
    final count = [for (final f in module.allFiles) ...f.exercises].length;
    return SurfaceCard(
      key: Key('module-${module.id}'),
      onTap: () => context.push('/topic/${module.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(module.name, style: AppText.title),
            if (module.description.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s1),
              Text(
                module.description,
                style: AppText.body.copyWith(color: context.palette.inkMuted),
              ),
            ],
            const SizedBox(height: AppSpace.s2),
            Text(
              '$count bài tập',
              style: AppText.caption.copyWith(color: context.palette.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassHeader extends StatelessWidget {
  const _ClassHeader({required this.fileId, required this.className});

  final String fileId;
  final String className;

  @override
  Widget build(BuildContext context) {
    return Text(
      'class $className',
      key: Key('class-$fileId-$className'),
      style: AppText.label.copyWith(color: context.palette.inkMuted),
    );
  }
}
