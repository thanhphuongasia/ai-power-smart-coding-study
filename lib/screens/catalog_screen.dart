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
    bool openEditorOnStart,
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
                    avatar: Icon(type.icon, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
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
                  sequenceNumber: index + 1,
                  exercises: trackExercises,
                  onStartSession: widget.onStartSession,
                );
              }
              final exercise = exercises[index];
              return _ExerciseCard(
                appState: widget.appState,
                exercise: exercise,
                sequenceNumber: index + 1,
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
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _FilterIconButton(
          tooltip: 'Level',
          icon: Icons.stairs_rounded,
          isActive: selectedLevel != null,
          onPressed: () async {
            final choice = await _openSelectionSheet<LearningLevel?>(
              context,
              title: 'Level',
              selectedValue: selectedLevel,
              options: <_SelectionOption<LearningLevel?>>[
                const _SelectionOption(value: null, label: 'All levels'),
                ...LearningLevel.values.map(
                  (level) =>
                      _SelectionOption(value: level, label: level.label),
                ),
              ],
            );
            if (choice == null) return;
            onLevelChanged(choice.value);
          },
        ),
        _FilterIconButton(
          tooltip: 'Language',
          icon: Icons.translate_rounded,
          isActive: selectedLanguageId != null,
          onPressed: () async {
            final choice = await _openSelectionSheet<String?>(
              context,
              title: 'Language',
              selectedValue: selectedLanguageId,
              options: <_SelectionOption<String?>>[
                const _SelectionOption(value: null, label: 'All languages'),
                ...availableLanguageIds.map(
                  (languageId) =>
                      _SelectionOption(value: languageId, label: languageId),
                ),
              ],
            );
            if (choice == null) return;
            onLanguageChanged(choice.value);
          },
        ),
        _FilterIconButton(
          tooltip: 'Topic',
          icon: Icons.category_rounded,
          isActive: selectedTopicId != null,
          onPressed: () async {
            final choice = await _openSelectionSheet<String?>(
              context,
              title: 'Topic',
              selectedValue: selectedTopicId,
              options: <_SelectionOption<String?>>[
                const _SelectionOption(value: null, label: 'All topics'),
                ...topics.map(
                  (topic) =>
                      _SelectionOption(value: topic.id, label: topic.title),
                ),
              ],
            );
            if (choice == null) return;
            onTopicChanged(choice.value);
          },
        ),
        _FilterIconButton(
          tooltip: 'Domain',
          icon: Icons.public_rounded,
          isActive: selectedDomainId != null,
          onPressed: () async {
            final choice = await _openSelectionSheet<String?>(
              context,
              title: 'Domain',
              selectedValue: selectedDomainId,
              options: <_SelectionOption<String?>>[
                const _SelectionOption(value: null, label: 'All domains'),
                ...domains.map(
                  (domain) => _SelectionOption(
                    value: domain.id,
                    label: domain.title,
                  ),
                ),
              ],
            );
            if (choice == null) return;
            onDomainChanged(choice.value);
          },
        ),
        _FilterIconButton(
          tooltip: 'Tag',
          icon: Icons.sell_rounded,
          isActive: selectedTag != null,
          onPressed: () async {
            final choice = await _openSelectionSheet<String?>(
              context,
              title: 'Tag',
              selectedValue: selectedTag,
              options: <_SelectionOption<String?>>[
                const _SelectionOption(value: null, label: 'All tags'),
                ...tagSuggestions.map(
                  (tag) => _SelectionOption(value: tag, label: tag),
                ),
              ],
            );
            if (choice == null) return;
            onTagChanged(choice.value);
          },
        ),
        const SizedBox(width: 6),
        FilledButton.tonalIcon(
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Reset'),
        ),
      ],
    );
  }
}

class _SelectionOption<T> {
  const _SelectionOption({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

class _SelectionChoice<T> {
  const _SelectionChoice(this.value);
  final T value;
}

Future<_SelectionChoice<T>?> _openSelectionSheet<T>(
  BuildContext context, {
  required String title,
  required T selectedValue,
  required List<_SelectionOption<T>> options,
}) {
  return showModalBottomSheet<_SelectionChoice<T>>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final isSelected = option.value == selectedValue;
                    return ListTile(
                      title: Text(option.label),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded)
                          : const SizedBox.shrink(),
                      onTap: () => Navigator.of(context)
                          .pop(_SelectionChoice<T>(option.value)),
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: options.length,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.tooltip,
    required this.icon,
    required this.isActive,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
    );

    if (!isActive) {
      return button;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        button,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({
    required this.value,
  });

  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        value.toString(),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.appState,
    required this.track,
    required this.sequenceNumber,
    required this.exercises,
    required this.onStartSession,
  });

  final AppState appState;
  final LearningTrack track;
  final int sequenceNumber;
  final List<LearningExercise> exercises;
  final void Function({
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
    bool openEditorOnStart,
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
                _NumberBadge(value: sequenceNumber),
                const SizedBox(width: 12),
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
            ...exercises.asMap().entries.map((entry) {
              final index = entry.key;
              final exercise = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ExerciseTile(
                  appState: appState,
                  exercise: exercise,
                  track: track,
                  sequenceNumber: index + 1,
                  onStartSession: onStartSession,
                ),
              );
            }),
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
    required this.sequenceNumber,
    required this.onStartSession,
  });

  final AppState appState;
  final LearningExercise exercise;
  final int sequenceNumber;
  final void Function({
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
    bool openEditorOnStart,
  }) onStartSession;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: _ExerciseTile(
          appState: appState,
          exercise: exercise,
          sequenceNumber: sequenceNumber,
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
    this.sequenceNumber,
    required this.onStartSession,
  });

  final AppState appState;
  final LearningExercise exercise;
  final LearningTrack? track;
  final int? sequenceNumber;
  final void Function({
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
    bool openEditorOnStart,
  }) onStartSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = appState.isExerciseCompleted(exercise.id);
    final defaultMode = exercise.supportedModes.contains(PracticeMode.guided)
        ? PracticeMode.guided
        : exercise.supportedModes.first;
    final isInTrack = track != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (sequenceNumber != null) ...<Widget>[
              _NumberBadge(value: sequenceNumber!),
              const SizedBox(width: 10),
            ],
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
        if (isInTrack)
          FilledButton.tonalIcon(
            onPressed: () => _startWithVariantPicker(
              context,
              defaultMode,
              openEditorOnStart: true,
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Practice'),
          )
        else
          FilledButton.icon(
            onPressed: () => _startWithVariantPicker(
              context,
              defaultMode,
              openEditorOnStart: true,
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Practice · ${defaultMode.label}'),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: exercise.supportedModes.map((mode) {
            return ActionChip(
              label: Text(mode.label),
              avatar: Icon(Icons.play_arrow_rounded, size: 18),
              onPressed: () => _startWithVariantPicker(
                context,
                mode,
                openEditorOnStart: true,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _startWithVariantPicker(
    BuildContext context,
    PracticeMode mode,
    {bool openEditorOnStart = false}
  ) async {
    final variants = exercise.languageVariants;
    if (variants.length == 1) {
      onStartSession(
        track: track,
        exercise: exercise,
        mode: mode,
        languageId: variants.first.languageId,
        openEditorOnStart: openEditorOnStart,
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
      openEditorOnStart: openEditorOnStart,
    );
  }
}
