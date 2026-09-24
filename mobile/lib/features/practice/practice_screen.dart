/// Tab Luyện: mọi bài tập, chia theo Đang dở / Chưa làm / Đã xong.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/theme_mode.dart';
import '../../data/seed.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../browse/exercise_row.dart';
import '../exercise/session_providers.dart';

class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final started = <Exercise>[];
    final fresh = <Exercise>[];
    final done = <Exercise>[];
    for (final exercise in uniqueExercises()) {
      final completed = progress[exercise.id]?.completedBlocks ?? 0;
      if (completed >= exercise.blocks.length) {
        done.add(exercise);
      } else if (completed > 0) {
        started.add(exercise);
      } else {
        fresh.add(exercise);
      }
    }

    Iterable<Widget> section(String label, List<Exercise> items) sync* {
      if (items.isEmpty) return;
      yield SectionLabel('$label · ${items.length}');
      for (final exercise in items) {
        final at = locateExercise(exercise.id);
        yield ExerciseRow(
          key: Key('practice-${exercise.id}'),
          exercise: exercise,
          progress: progress[exercise.id],
          subtitle: '${at.theme.name} › ${at.file.name}',
        );
        yield const SizedBox(height: AppSpace.s2);
      }
      yield const SizedBox(height: AppSpace.s4);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(
              title: 'Luyện tập',
              subtitle: 'Mọi bài tập theo trạng thái',
              trailing: ThemeModeButton(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  ...section('Đang dở', started),
                  ...section('Chưa làm', fresh),
                  ...section('Đã xong', done),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
