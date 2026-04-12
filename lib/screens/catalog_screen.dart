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
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
  }) onStartSession;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late LearningTrackType _selectedType;
  var _showTracks = true;
  LearningLevel? _selectedLevel;
  String? _selectedLanguageId;
  String? _selectedTopicId;
  String? _selectedDomainId;
  String? _selectedTag;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _selectedLanguageId = widget.appState.preferredLanguageId;
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
    final exercises = _filteredExercises();
    final trackCards = widget.appState
        .tracksForType(_selectedType)
        .where((track) => _matchesTrack(track))
        .toList(growable: false);

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
                'Browse tracks or jump straight into standalone exercises. Filters stay aligned across lanes, languages, topics, domains, and tags.',
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
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Tracks'),
                    icon: Icon(Icons.route_rounded),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Exercises'),
                    icon: Icon(Icons.code_rounded),
                  ),
                ],
                selected: <bool>{_showTracks},
                onSelectionChanged: (selection) {
                  setState(() => _showTracks = selection.first);
                },
              ),
              const SizedBox(height: 14),
              _FilterBar(
                selectedLevel: _selectedLevel,
                selectedLanguageId: _selectedLanguageId,
                selectedTopicId: _selectedTopicId,
                selectedDomainId: _selectedDomainId,
                selectedTag: _selectedTag,
                availableLanguageIds:
                    widget.appState.languageIdsForType(_selectedType),
                topics: widget.appState.topics,
                domains: widget.appState.domains,
                tagSuggestions: widget.appState.tagSuggestions,
                onLevelChanged: (value) =>
                    setState(() => _selectedLevel = value),
                onLanguageChanged: (value) =>
                    setState(() => _selectedLanguageId = value),
                onTopicChanged: (value) =>
                    setState(() => _selectedTopicId = value),
                onDomainChanged: (value) =>
                    setState(() => _selectedDomainId = value),
                onTagChanged: (value) => setState(() => _selectedTag = value),
                onReset: () {
                  setState(() {
                    _selectedLevel = null;
                    _selectedLanguageId = widget.appState.preferredLanguageId;
                    _selectedTopicId = null;
                    _selectedDomainId = null;
                    _selectedTag = null;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemBuilder: (context, index) {
              if (_showTracks) {
                final track = trackCards[index];
                final trackExercises = track.exerciseRefs
                    .map((ref) => _findExercise(ref.exerciseId))
                    .whereType<LearningExercise>()
                    .where(_matchesExercise)
                    .toList(growable: false);
                return _TrackCard(
                  appState: widget.appState,
                  track: track,
                  exercises: trackExercises,
                  onStartSession: widget.onStartSession,
                );
              }
              final exercise = exercises[index];
              return _ExerciseCard(
                appState: widget.appState,
                exercise: exercise,
                onStartSession: widget.onStartSession,
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemCount: _showTracks ? trackCards.length : exercises.length,
          ),
        ),
      ],
    );
  }

  bool _matchesTrack(LearningTrack track) {
    if (_selectedLevel != null && track.level != _selectedLevel) {
      return false;
    }
    if (_selectedTopicId != null &&
        !track.topicIds.contains(_selectedTopicId)) {
      return false;
    }
    if (_selectedDomainId != null &&
        !track.domainIds.contains(_selectedDomainId)) {
      return false;
    }
    if (_selectedTag != null && !track.tags.contains(_selectedTag)) {
      return false;
    }
    if (_selectedLanguageId == null) {
      return true;
    }
    final trackExerciseIds =
        track.exerciseRefs.map((ref) => ref.exerciseId).toSet();
    return widget.appState.exercises.any(
      (exercise) =>
          trackExerciseIds.contains(exercise.id) &&
          exercise.languageVariants
              .any((variant) => variant.languageId == _selectedLanguageId),
    );
  }

  List<LearningExercise> _filteredExercises() {
    return widget.appState
        .exercisesForType(_selectedType)
        .where(_matchesExercise)
        .toList(growable: false);
  }

  bool _matchesExercise(LearningExercise exercise) {
    if (_selectedLevel != null && exercise.level != _selectedLevel) {
      return false;
    }
    if (_selectedLanguageId != null &&
        !exercise.languageVariants
            .any((variant) => variant.languageId == _selectedLanguageId)) {
      return false;
    }
    if (_selectedTopicId != null &&
        !exercise.topicIds.contains(_selectedTopicId)) {
      return false;
    }
    if (_selectedDomainId != null &&
        !exercise.domainIds.contains(_selectedDomainId)) {
      return false;
    }
    if (_selectedTag != null && !exercise.tags.contains(_selectedTag)) {
      return false;
    }
    return true;
  }

  LearningExercise? _findExercise(String exerciseId) {
    for (final exercise in widget.appState.exercises) {
      if (exercise.id == exerciseId) {
        return exercise;
      }
    }
    return null;
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selectedLevel,
    required this.selectedLanguageId,
    required this.selectedTopicId,
    required this.selectedDomainId,
    required this.selectedTag,
    required this.availableLanguageIds,
    required this.topics,
    required this.domains,
    required this.tagSuggestions,
    required this.onLevelChanged,
    required this.onLanguageChanged,
    required this.onTopicChanged,
    required this.onDomainChanged,
    required this.onTagChanged,
    required this.onReset,
  });

  final LearningLevel? selectedLevel;
  final String? selectedLanguageId;
  final String? selectedTopicId;
  final String? selectedDomainId;
  final String? selectedTag;
  final List<String> availableLanguageIds;
  final List<TopicDefinition> topics;
  final List<DomainDefinition> domains;
  final List<String> tagSuggestions;
  final ValueChanged<LearningLevel?> onLevelChanged;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<String?> onTopicChanged;
  final ValueChanged<String?> onDomainChanged;
  final ValueChanged<String?> onTagChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        _DropdownChip<LearningLevel?>(
          label: 'Level',
          value: selectedLevel,
          items: <DropdownMenuItem<LearningLevel?>>[
            const DropdownMenuItem<LearningLevel?>(
              value: null,
              child: Text('All levels'),
            ),
            ...LearningLevel.values.map(
              (level) => DropdownMenuItem<LearningLevel?>(
                value: level,
                child: Text(level.label),
              ),
            ),
          ],
          onChanged: onLevelChanged,
        ),
        _DropdownChip<String?>(
          label: 'Language',
          value: selectedLanguageId,
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All languages'),
            ),
            ...availableLanguageIds.map(
              (languageId) => DropdownMenuItem<String?>(
                value: languageId,
                child: Text(languageId),
              ),
            ),
          ],
          onChanged: onLanguageChanged,
        ),
        _DropdownChip<String?>(
          label: 'Topic',
          value: selectedTopicId,
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All topics'),
            ),
            ...topics.map(
              (topic) => DropdownMenuItem<String?>(
                value: topic.id,
                child: Text(topic.title),
              ),
            ),
          ],
          onChanged: onTopicChanged,
        ),
        _DropdownChip<String?>(
          label: 'Domain',
          value: selectedDomainId,
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All domains'),
            ),
            ...domains.map(
              (domain) => DropdownMenuItem<String?>(
                value: domain.id,
                child: Text(domain.title),
              ),
            ),
          ],
          onChanged: onDomainChanged,
        ),
        _DropdownChip<String?>(
          label: 'Tag',
          value: selectedTag,
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All tags'),
            ),
            ...tagSuggestions.map(
              (tag) => DropdownMenuItem<String?>(
                value: tag,
                child: Text(tag),
              ),
            ),
          ],
          onChanged: onTagChanged,
        ),
        FilledButton.tonalIcon(
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset'),
        ),
      ],
    );
  }
}

class _DropdownChip<T> extends StatelessWidget {
  const _DropdownChip({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          hint: Text(label),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.appState,
    required this.track,
    required this.exercises,
    required this.onStartSession,
  });

  final AppState appState;
  final LearningTrack track;
  final List<LearningExercise> exercises;
  final void Function({
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
  }) onStartSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completion = appState.completionForTrack(track);
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
                  child: Text(track.level.label),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ...track.topicIds
                    .map((id) => Chip(label: Text(appState.topicTitle(id)))),
                ...track.domainIds
                    .map((id) => Chip(label: Text(appState.domainTitle(id)))),
                ...track.tags.map((tag) => Chip(label: Text(tag))),
              ],
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
            ...exercises.map(
              (exercise) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ExerciseTile(
                  appState: appState,
                  exercise: exercise,
                  track: track,
                  onStartSession: onStartSession,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.appState,
    required this.exercise,
    required this.onStartSession,
  });

  final AppState appState;
  final LearningExercise exercise;
  final void Function({
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
  }) onStartSession;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: _ExerciseTile(
          appState: appState,
          exercise: exercise,
          onStartSession: onStartSession,
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.appState,
    required this.exercise,
    this.track,
    required this.onStartSession,
  });

  final AppState appState;
  final LearningExercise exercise;
  final LearningTrack? track;
  final void Function({
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
  }) onStartSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = appState.isExerciseCompleted(exercise.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(exercise.title, style: theme.textTheme.titleMedium),
            ),
            if (isCompleted)
              Icon(Icons.verified_rounded, color: theme.colorScheme.tertiary),
          ],
        ),
        const SizedBox(height: 6),
        Text(exercise.summary),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ...exercise.languageVariants.map(
              (variant) => Chip(label: Text(variant.languageLabel)),
            ),
            ...exercise.topicIds
                .map((id) => Chip(label: Text(appState.topicTitle(id)))),
            ...exercise.domainIds
                .map((id) => Chip(label: Text(appState.domainTitle(id)))),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: exercise.supportedModes.map((mode) {
            return ActionChip(
              label: Text(mode.label),
              avatar: Icon(Icons.play_arrow_rounded, size: 18),
              onPressed: () => _startWithVariantPicker(context, mode),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _startWithVariantPicker(
    BuildContext context,
    PracticeMode mode,
  ) async {
    final variants = exercise.languageVariants;
    if (variants.length == 1) {
      onStartSession(
        track: track,
        exercise: exercise,
        mode: mode,
        languageId: variants.first.languageId,
      );
      return;
    }

    final selectedLanguageId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        var currentId = appState.preferredLanguageId ??
            exercise
                .resolveVariant(
                  preferredLanguageId: appState.preferredLanguageId,
                )
                .languageId;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Choose language',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  ...variants.map(
                    (variant) => RadioListTile<String>(
                      title: Text(variant.languageLabel),
                      subtitle: Text(variant.runCommand),
                      value: variant.languageId,
                      groupValue: currentId,
                      onChanged: (value) =>
                          setModalState(() => currentId = value ?? currentId),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(currentId),
                    child: const Text('Start session'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selectedLanguageId == null) {
      return;
    }
    onStartSession(
      track: track,
      exercise: exercise,
      mode: mode,
      languageId: selectedLanguageId,
    );
  }
}
