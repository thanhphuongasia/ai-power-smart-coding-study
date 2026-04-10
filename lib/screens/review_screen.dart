import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../models/learning_models.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({
    super.key,
    required this.appState,
    required this.onStartReviewTask,
  });

  final AppState appState;
  final ValueChanged<ReviewTask> onStartReviewTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reviewQueue = appState.reviewQueue;
    final weakest = appState.weakestSkills();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: <Widget>[
        Text('Review queue', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'These warmups are generated from missed checks, repeated hint usage, and low-confidence skills across projects and interview drills.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        if (reviewQueue.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'No urgent review tasks right now. Keep practicing and the coach will surface weak spots here.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          )
        else
          ...reviewQueue.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(task.title,
                                style: theme.textTheme.titleMedium),
                          ),
                          Chip(label: Text(task.laneLabel)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(task.description),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () => onStartReviewTask(task),
                        child: const Text('Start warmup'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Skill memory', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        ...weakest.map(
          (view) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                            child: Text(view.skill.title,
                                style: theme.textTheme.titleMedium)),
                        Text(
                          '${(view.record.masteryScore * 100).round()}%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(view.skill.description),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: view.record.masteryScore,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hint dependence ${(view.record.hintDependence * 100).round()}% · ${view.record.lastOutcome}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
