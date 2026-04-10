import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../models/learning_models.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.appState,
    required this.onOpenLane,
    required this.onOpenReview,
  });

  final AppState appState;
  final ValueChanged<LearningTrackType> onOpenLane;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = appState.dashboardStats;
    final weaknesses = appState.weakestSkills().take(3).toList();

    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Pocket Coding Coach',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Project slices for real apps, data structure drills, and LeetCode practice in one mobile-first loop.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                _HeroCard(stats: stats, onOpenReview: onOpenReview),
                const SizedBox(height: 20),
                Text('Jump back in', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: LearningTrackType.values
                      .map(
                        (type) => _LaneCard(
                          type: type,
                          onTap: () => onOpenLane(type),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                Text('Weaknesses to revisit',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList.separated(
            itemBuilder: (context, index) {
              final weakness = weaknesses[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              weakness.skill.title,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Text(
                            '${(weakness.record.masteryScore * 100).round()}%',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(weakness.skill.description),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(999),
                        value: weakness.record.masteryScore,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        weakness.record.lastOutcome,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: weaknesses.length,
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.stats,
    required this.onOpenReview,
  });

  final DashboardStats stats;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFF17313E),
            Color(0xFF285969),
            Color(0xFFDA6B2D)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Today\'s coaching snapshot',
              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              'Keep projects as your main lane, then plug syntax or algorithm gaps through targeted drills.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                _StatTile(
                    label: 'Projects done',
                    value: '${stats.completedProjects}'),
                const SizedBox(width: 12),
                _StatTile(
                    label: 'DS + Algo', value: '${stats.completedDsAlgo}'),
                const SizedBox(width: 12),
                _StatTile(
                  label: 'Avg mastery',
                  value: '${(stats.averageMastery * 100).round()}%',
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: onOpenReview,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.colorScheme.primary,
              ),
              child: Text('Review ${stats.reviewQueueCount} weak spots'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              value,
              style:
                  theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaneCard extends StatelessWidget {
  const _LaneCard({
    required this.type,
    required this.onTap,
  });

  final LearningTrackType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(type.icon, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 14),
                Text(type.label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  switch (type) {
                    LearningTrackType.project =>
                      'Feature-slice practice from real app ideas like DMS and Todo Pro.',
                    LearningTrackType.dataStructure =>
                      'Micro-drills for class design, operations, and complexity reasoning.',
                    LearningTrackType.leetcode =>
                      'Guided interview problems with hints, reflection, and pattern memory.',
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
