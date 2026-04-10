import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../models/learning_models.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.appState,
    required this.initialType,
    required this.onStartSession,
  });

  final AppState appState;
  final LearningTrackType initialType;
  final void Function({
    required LearningTrack track,
    required LearningModule module,
    required Milestone milestone,
    required PracticeMode mode,
  }) onStartSession;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late LearningTrackType _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialType != widget.initialType) {
      _selectedType = widget.initialType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracks = widget.appState.tracksForType(_selectedType);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Practice library', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Switch between project slices, DS drills, and LeetCode sets. Every lane feeds the same skill memory engine.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: LearningTrackType.values.map((type) {
                  return ChoiceChip(
                    label: Text(type.label),
                    selected: _selectedType == type,
                    avatar: Icon(type.icon, size: 18),
                    onSelected: (_) => setState(() => _selectedType = type),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _TrackCard(
                track: track,
                completion: widget.appState.completionForTrack(track),
                isCompleted: widget.appState.isMilestoneCompleted,
                onStart: widget.onStartSession,
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemCount: tracks.length,
          ),
        ),
      ],
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.completion,
    required this.isCompleted,
    required this.onStart,
  });

  final LearningTrack track;
  final double completion;
  final bool Function(String milestoneId) isCompleted;
  final void Function({
    required LearningTrack track,
    required LearningModule module,
    required Milestone milestone,
    required PracticeMode mode,
  }) onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(track.title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(track.summary),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(track.difficultyLabel),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: track.focusAreas
                  .map((area) => Chip(label: Text(area)))
                  .toList(),
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              minHeight: 10,
              value: completion,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Text('${(completion * 100).round()}% complete'),
            const SizedBox(height: 14),
            ...track.modules.map(
              (module) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(module.title, style: theme.textTheme.titleMedium),
                  subtitle: Text(
                      '${module.summary} · ${module.estimatedMinutes} min'),
                  children: module.milestones.map((milestone) {
                    final supportedModes = milestone.supportedModes;
                    return Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(milestone.title,
                                    style: theme.textTheme.titleMedium),
                              ),
                              if (isCompleted(milestone.id))
                                Icon(Icons.verified_rounded,
                                    color: theme.colorScheme.tertiary),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(milestone.objective),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: supportedModes.map((mode) {
                              return ActionChip(
                                label: Text(mode.label),
                                avatar:
                                    Icon(Icons.play_arrow_rounded, size: 18),
                                onPressed: () => onStart(
                                  track: track,
                                  module: module,
                                  milestone: milestone,
                                  mode: mode,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
