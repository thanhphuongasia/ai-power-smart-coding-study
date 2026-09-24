/// Màn File cross-cut: một file (vd chunker.py) được dùng ở nhiều theme —
/// liệt kê exercise theo từng theme. Exercise dùng chung là cùng một bài,
/// làm một lần thì tiến độ tính cho mọi theme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/seed.dart';
import '../../shared/widgets.dart';
import '../exercise/session_providers.dart';
import 'exercise_row.dart';

class FileCrossCutScreen extends ConsumerWidget {
  const FileCrossCutScreen(this.fileName, {super.key});

  final String fileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final progress = ref.watch(progressProvider);
    final usages = locateFilesNamed(fileName);
    final themeCount = usages.map((u) => u.theme.id).toSet().length;
    final exerciseIds = {
      for (final u in usages)
        for (final e in u.file.exercises) e.id,
    };
    final sharedIds = {
      for (final id in exerciseIds)
        if (usages
                .where((u) => u.file.exercises.any((e) => e.id == id))
                .length >
            1)
          id,
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: fileName,
              subtitle:
                  'Dùng trong $themeCount theme · ${exerciseIds.length} bài tập',
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  for (final u in usages) ...[
                    SectionLabel('${u.theme.name} › ${u.topic.name}'),
                    for (final exercise in u.file.exercises) ...[
                      ExerciseRow(
                        key: Key('crosscut-${u.file.id}-${exercise.id}'),
                        exercise: exercise,
                        progress: progress[exercise.id],
                        subtitle: sharedIds.contains(exercise.id)
                            ? '${exercise.title} · dùng chung'
                            : exercise.title,
                      ),
                      const SizedBox(height: AppSpace.s2),
                    ],
                    const SizedBox(height: AppSpace.s4),
                  ],
                  if (sharedIds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(AppSpace.s4),
                      decoration: BoxDecoration(
                        color: p.surfaceRaised,
                        border: Border.all(color: p.outline),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        'Bài "dùng chung" là cùng một bài tập: làm xong một '
                        'lần thì tiến độ được tính cho mọi theme dùng file này.',
                        style: AppText.body.copyWith(color: p.inkMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
