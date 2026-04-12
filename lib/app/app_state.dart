import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/app_sync_models.dart';
import '../models/learning_models.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/learner_repository.dart';
import '../repositories/sync_repository.dart';
import '../services/app_api_service.dart';
import '../services/sandbox_api_service.dart';
import '../storage/local_app_store.dart';

class AppState extends ChangeNotifier {
  AppState._({
    required CatalogRepository catalogRepository,
    required LearnerRepository learnerRepository,
    required SyncRepository syncRepository,
    required SandboxApiService sandboxApiService,
    required LearnerProfile learnerProfile,
    required List<LearningTrack> tracks,
    required List<LearningExercise> exercises,
    required List<TopicDefinition> topics,
    required List<DomainDefinition> domains,
    required List<String> tagSuggestions,
    required List<SkillNode> skillNodes,
    required Map<String, SkillMasteryRecord> skillMemory,
    required Set<String> completedExercises,
    required String? preferredLanguageId,
  })  : _catalogRepository = catalogRepository,
        _learnerRepository = learnerRepository,
        _syncRepository = syncRepository,
        _sandboxApiService = sandboxApiService,
        _learnerProfile = learnerProfile,
        _tracks = tracks,
        _exercises = exercises,
        _topics = topics,
        _domains = domains,
        _tagSuggestions = tagSuggestions,
        _skillNodes = skillNodes,
        _skillMemory = skillMemory,
        _completedExercises = completedExercises,
        _preferredLanguageId = preferredLanguageId;

  static Future<AppState> bootstrap({
    CatalogRepository? catalogRepository,
    LearnerRepository? learnerRepository,
    SyncRepository? syncRepository,
    LocalAppStore? localAppStore,
    AppApiService? appApiService,
    SandboxApiService? sandboxApiService,
  }) async {
    final store = localAppStore ?? FileLocalAppStore();
    final apiService = appApiService ?? AppApiService();
    final resolvedCatalogRepository = catalogRepository ??
        AppApiCatalogRepository(
          localAppStore: store,
          appApiService: apiService,
        );
    final resolvedLearnerRepository = learnerRepository ??
        AppApiLearnerRepository(
          localAppStore: store,
          appApiService: apiService,
        );
    final resolvedSyncRepository = syncRepository ??
        AppApiSyncRepository(
          localAppStore: store,
          appApiService: apiService,
        );

    final learnerProfile = await resolvedLearnerRepository.bootstrapLearner();

    try {
      await resolvedCatalogRepository.refreshCatalogIfNeeded();
    } catch (_) {
      // Keep cached catalog when the network is unavailable during bootstrap.
    }

    try {
      await resolvedSyncRepository.flushPendingEvents(
        learnerProfile: learnerProfile,
      );
      await resolvedLearnerRepository.refreshLearnerState();
    } catch (_) {
      // Offline bootstrap should still succeed from cache.
    }

    final tracks = await resolvedCatalogRepository.readCachedTracks();
    final exercises = await resolvedCatalogRepository.readCachedExercises();
    final topics = await resolvedCatalogRepository.readCachedTopics();
    final domains = await resolvedCatalogRepository.readCachedDomains();
    final tagSuggestions =
        await resolvedCatalogRepository.readCachedTagSuggestions();
    final skillNodes = await resolvedCatalogRepository.readCachedSkillNodes();
    final cachedSkillMemory =
        await resolvedLearnerRepository.readCachedSkillMemory();
    final completedExercises =
        await resolvedLearnerRepository.readCachedCompletedExerciseIds();
    final preferredLanguageId =
        await resolvedLearnerRepository.readCachedPreferredLanguageId();

    return AppState._(
      catalogRepository: resolvedCatalogRepository,
      learnerRepository: resolvedLearnerRepository,
      syncRepository: resolvedSyncRepository,
      sandboxApiService: sandboxApiService ?? SandboxApiService(),
      learnerProfile: learnerProfile,
      tracks: tracks,
      exercises: exercises,
      topics: topics,
      domains: domains,
      tagSuggestions: tagSuggestions,
      skillNodes: skillNodes,
      skillMemory: _normalizeSkillMemory(skillNodes, cachedSkillMemory),
      completedExercises: completedExercises,
      preferredLanguageId: preferredLanguageId,
    );
  }

  final CatalogRepository _catalogRepository;
  final LearnerRepository _learnerRepository;
  final SyncRepository _syncRepository;
  final SandboxApiService _sandboxApiService;
  LearnerProfile _learnerProfile;

  final List<LearningTrack> _tracks;
  final List<LearningExercise> _exercises;
  final List<TopicDefinition> _topics;
  final List<DomainDefinition> _domains;
  final List<String> _tagSuggestions;
  final List<SkillNode> _skillNodes;
  final Map<String, SkillMasteryRecord> _skillMemory;
  final Set<String> _completedExercises;
  String? _preferredLanguageId;
  Future<ValidationResult>? _inFlightSandboxExecution;
  PracticeSession? _activeSession;

  List<LearningTrack> get tracks => List<LearningTrack>.unmodifiable(_tracks);
  List<LearningExercise> get exercises =>
      List<LearningExercise>.unmodifiable(_exercises);
  List<TopicDefinition> get topics =>
      List<TopicDefinition>.unmodifiable(_topics);
  List<DomainDefinition> get domains =>
      List<DomainDefinition>.unmodifiable(_domains);
  List<String> get tagSuggestions => List<String>.unmodifiable(_tagSuggestions);
  List<SkillNode> get skillNodes => List<SkillNode>.unmodifiable(_skillNodes);
  PracticeSession? get activeSession => _activeSession;
  bool get isSandboxExecutionRunning =>
      _inFlightSandboxExecution != null ||
      _activeSession?.validationResult.status == ValidationStatus.running;
  Map<String, SkillMasteryRecord> get skillMemory =>
      Map<String, SkillMasteryRecord>.unmodifiable(_skillMemory);
  LearnerProfile get learnerProfile => _learnerProfile;
  String? get preferredLanguageId => _preferredLanguageId;

  List<LearningTrack> tracksForType(LearningTrackType type) {
    return _tracks.where((track) => track.type == type).toList(growable: false);
  }

  List<LearningExercise> exercisesForType(LearningTrackType type) {
    return _exercises
        .where((exercise) => exercise.type == type)
        .toList(growable: false);
  }

  List<String> languageIdsForType(LearningTrackType type) {
    final values = <String>{};
    for (final exercise in _exercises.where((item) => item.type == type)) {
      for (final variant in exercise.languageVariants) {
        values.add(variant.languageId);
      }
    }
    final result = values.toList(growable: false)..sort();
    return result;
  }

  String topicTitle(String topicId) {
    for (final topic in _topics) {
      if (topic.id == topicId) {
        return topic.title;
      }
    }
    return topicId;
  }

  String domainTitle(String domainId) {
    for (final domain in _domains) {
      if (domain.id == domainId) {
        return domain.title;
      }
    }
    return domainId;
  }

  DashboardStats get dashboardStats {
    final reviewCount = reviewQueue.length;
    final average = _skillMemory.values.isEmpty
        ? 0.0
        : _skillMemory.values
                .map((record) => record.masteryScore)
                .reduce((value, element) => value + element) /
            _skillMemory.length;
    final completedProjectCount = _completedExercises
        .where((id) => _findExerciseById(id)?.type == LearningTrackType.project)
        .length;
    final completedAlgoCount =
        _completedExercises.length - completedProjectCount;

    return DashboardStats(
      completedProjects: completedProjectCount,
      completedDsAlgo: completedAlgoCount,
      reviewQueueCount: reviewCount,
      averageMastery: average,
    );
  }

  List<ReviewTask> get reviewQueue {
    final tasks = <ReviewTask>[];
    for (final skill in _skillNodes) {
      final record = _skillMemory[skill.id];
      if (record == null) {
        continue;
      }
      if (record.masteryScore < 0.58 || record.failureCount >= 3) {
        final exercise = _findExerciseById(skill.reviewExerciseId);
        if (exercise == null) {
          continue;
        }
        tasks.add(
          ReviewTask(
            id: 'review_${skill.id}',
            title: 'Review ${skill.title}',
            description: '${skill.description} ${record.lastOutcome}',
            skillIds: <String>[skill.id],
            exerciseId: skill.reviewExerciseId,
            laneLabel: exercise.type.label,
          ),
        );
      }
    }
    tasks.sort((a, b) {
      final aRecord = _skillMemory[a.skillIds.first]!;
      final bRecord = _skillMemory[b.skillIds.first]!;
      return aRecord.masteryScore.compareTo(bRecord.masteryScore);
    });
    return tasks;
  }

  List<SkillMasteryView> weakestSkills() {
    final views = _skillNodes.map((skill) {
      final record = _skillMemory[skill.id] ?? _defaultRecord(skill.id);
      return SkillMasteryView(skill: skill, record: record);
    }).toList();

    views
        .sort((a, b) => a.record.masteryScore.compareTo(b.record.masteryScore));
    return views;
  }

  Future<void> refreshFromRemote({
    bool forceCatalogRefresh = false,
  }) async {
    var changed = false;
    try {
      changed = await _catalogRepository.refreshCatalogIfNeeded(
            force: forceCatalogRefresh,
          ) ||
          changed;
    } catch (_) {
      // Keep cached data on network failures.
    }

    try {
      changed = await _syncRepository.flushPendingEvents(
            learnerProfile: _learnerProfile,
          ) ||
          changed;
      changed = await _learnerRepository.refreshLearnerState() || changed;
    } catch (_) {
      // Offline mode is expected on mobile.
    }

    if (!changed) {
      return;
    }

    final latestTracks = await _catalogRepository.readCachedTracks();
    final latestExercises = await _catalogRepository.readCachedExercises();
    final latestTopics = await _catalogRepository.readCachedTopics();
    final latestDomains = await _catalogRepository.readCachedDomains();
    final latestTagSuggestions =
        await _catalogRepository.readCachedTagSuggestions();
    final latestSkillNodes = await _catalogRepository.readCachedSkillNodes();
    final latestSkillMemory = await _learnerRepository.readCachedSkillMemory();
    final latestCompletedExercises =
        await _learnerRepository.readCachedCompletedExerciseIds();
    final latestLearnerProfile =
        await _learnerRepository.readCachedLearnerProfile() ?? _learnerProfile;
    final latestPreferredLanguageId =
        await _learnerRepository.readCachedPreferredLanguageId();

    _tracks
      ..clear()
      ..addAll(latestTracks);
    _exercises
      ..clear()
      ..addAll(latestExercises);
    _topics
      ..clear()
      ..addAll(latestTopics);
    _domains
      ..clear()
      ..addAll(latestDomains);
    _tagSuggestions
      ..clear()
      ..addAll(latestTagSuggestions);
    _skillNodes
      ..clear()
      ..addAll(latestSkillNodes);
    _skillMemory
      ..clear()
      ..addAll(_normalizeSkillMemory(latestSkillNodes, latestSkillMemory));
    _completedExercises
      ..clear()
      ..addAll(latestCompletedExercises);
    _learnerProfile = latestLearnerProfile;
    _preferredLanguageId = latestPreferredLanguageId;
    notifyListeners();
  }

  Future<void> setPreferredLanguageId(String? languageId) async {
    if (_preferredLanguageId == languageId) {
      return;
    }
    _preferredLanguageId = languageId;
    await _learnerRepository.savePreferredLanguageId(languageId);
    notifyListeners();
  }

  void startSession({
    required LearningExercise exercise,
    LearningTrack? track,
    PracticeMode mode = PracticeMode.guided,
    String? languageId,
  }) {
    final selectedVariant = exercise.resolveVariant(
      preferredLanguageId: _preferredLanguageId,
      explicitLanguageId: languageId,
    );
    if (_preferredLanguageId != selectedVariant.languageId) {
      _preferredLanguageId = selectedVariant.languageId;
      unawaited(
          _learnerRepository.savePreferredLanguageId(_preferredLanguageId));
    }
    final fileContents = _initialFileContentsFor(selectedVariant);
    _activeSession = PracticeSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      exercise: exercise,
      selectedVariant: selectedVariant,
      mode: mode,
      track: track,
      fileContents: fileContents,
      activeFilePath: selectedVariant.entryFilePath,
      revealedHintLevel: null,
      validationResult: ValidationResult.idle,
      sessionLog: <String>[
        'Opened ${exercise.title} in ${mode.label} mode.',
      ],
      executionHistory: const <ExecutionAttempt>[],
    );
    notifyListeners();
    unawaited(
      _recordEvent(
        LearnerSyncEventType.sessionStarted,
        <String, Object?>{
          'track_id': track?.id,
          'exercise_id': exercise.id,
          'mode': mode.name,
          'language_id': selectedVariant.languageId,
        },
      ),
    );
  }

  bool startReviewTask(ReviewTask task) {
    final exercise = _findExerciseById(task.exerciseId);
    if (exercise == null) {
      return false;
    }
    startSession(
      exercise: exercise,
      mode: PracticeMode.guided,
    );
    return true;
  }

  void closeSession() {
    _activeSession = null;
    notifyListeners();
  }

  void updateSessionCode(String code) {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    final activeFilePath = session.activeFilePath;
    if (session.fileContentFor(activeFilePath) == code) {
      return;
    }

    _activeSession = session.copyWith(
      fileContents: <String, String>{
        ...session.fileContents,
        activeFilePath: code,
      },
    );
  }

  void updateSessionFileCode({
    required String filePath,
    required String code,
  }) {
    final session = _activeSession;
    if (session == null) {
      return;
    }

    if (session.fileContentFor(filePath) == code) {
      return;
    }

    _activeSession = session.copyWith(
      fileContents: <String, String>{
        ...session.fileContents,
        filePath: code,
      },
    );
  }

  void selectSessionFile(String filePath) {
    final session = _activeSession;
    if (session == null || session.activeFilePath == filePath) {
      return;
    }

    _activeSession = session.copyWith(activeFilePath: filePath);
    notifyListeners();
  }

  String revealNextHint() {
    final session = _activeSession;
    if (session == null) {
      return 'No active session.';
    }

    final levels = HintLevel.values;
    final currentIndex = session.revealedHintLevel == null
        ? -1
        : levels.indexOf(session.revealedHintLevel!);
    final nextLevel = levels[min(currentIndex + 1, levels.length - 1)];
    final hint = session.exercise.hints[nextLevel] ?? 'No hint available.';

    _activeSession = session.copyWith(
      revealedHintLevel: nextLevel,
      sessionLog: <String>[
        ...session.sessionLog,
        'Opened ${nextLevel.label}.',
      ],
    );

    for (final skillId in session.exercise.skillIds) {
      final record = _skillMemory[skillId];
      if (record == null) {
        continue;
      }
      _skillMemory[skillId] = record.copyWith(
        hintDependence: (record.hintDependence + 0.05).clamp(0.0, 1.0),
        lastOutcome: 'Needed ${nextLevel.label.toLowerCase()}',
      );
    }

    notifyListeners();
    unawaited(
      _persistDerivedStateAndSync(
        eventType: LearnerSyncEventType.hintRevealed,
        payload: <String, Object?>{
          'exercise_id': session.exercise.id,
          'hint_level': nextLevel.name,
          'skill_ids': session.exercise.skillIds,
        },
      ),
    );
    return hint;
  }

  Future<ValidationResult> buildSession() {
    return _startSandboxExecution(action: SandboxExecutionAction.build);
  }

  Future<ValidationResult> runSession() {
    return _startSandboxExecution(action: SandboxExecutionAction.run);
  }

  Future<ValidationResult> _startSandboxExecution({
    required SandboxExecutionAction action,
  }) {
    final existingExecution = _inFlightSandboxExecution;
    if (existingExecution != null) {
      return existingExecution;
    }

    final execution = _executeSession(action: action);
    _inFlightSandboxExecution = execution;
    execution.whenComplete(() {
      if (identical(_inFlightSandboxExecution, execution)) {
        _inFlightSandboxExecution = null;
      }
    });
    return execution;
  }

  Future<ValidationResult> _executeSession({
    required SandboxExecutionAction action,
  }) async {
    final session = _activeSession;
    if (session == null) {
      return ValidationResult.idle;
    }

    final queuedResult = ValidationResult(
      status: ValidationStatus.running,
      summary: action == SandboxExecutionAction.build
          ? 'Build queued on the sandbox API.'
          : 'Run queued on the sandbox API.',
      output: action == SandboxExecutionAction.build
          ? 'Submitting your code to the sandbox API for compilation or syntax validation.'
          : 'Submitting your code to the sandbox API for multi-case execution.',
      executionReport: null,
      matchedRequirements: session.validationResult.matchedRequirements,
      missingRequirements: session.validationResult.missingRequirements,
      suggestedReviewSkillIds: session.validationResult.suggestedReviewSkillIds,
    );

    _activeSession = session.copyWith(
      validationResult: queuedResult,
      sessionLog: <String>[
        ...session.sessionLog,
        action == SandboxExecutionAction.build
            ? 'Queued sandbox build.'
            : 'Queued sandbox run.',
      ],
    );
    notifyListeners();

    try {
      final execution = await _sandboxApiService.execute(
        action: action,
        exercise: session.exercise,
        variant: session.selectedVariant,
        fileContents: session.fileContents,
        entryFilePath: session.selectedVariant.entryFilePath,
      );

      final result = ValidationResult(
        status: execution.success
            ? ValidationStatus.passed
            : ValidationStatus.needsWork,
        summary: execution.summary,
        output: execution.output,
        executionReport: execution.report,
        matchedRequirements: session.validationResult.matchedRequirements,
        missingRequirements: session.validationResult.missingRequirements,
        suggestedReviewSkillIds:
            session.validationResult.suggestedReviewSkillIds,
      );

      final latestSession = _activeSession ?? session;
      _activeSession = latestSession.copyWith(
        validationResult: result,
        sessionLog: <String>[
          ...latestSession.sessionLog,
          action == SandboxExecutionAction.build
              ? execution.success
                  ? 'Sandbox build succeeded.'
                  : 'Sandbox build reported issues.'
              : execution.success
                  ? 'Sandbox run completed.'
                  : 'Sandbox run reported issues.',
        ],
        executionHistory: _nextExecutionHistory(
          latestSession,
          action: action,
          result: result,
        ),
      );
      notifyListeners();

      unawaited(
        _recordEvent(
          action == SandboxExecutionAction.build
              ? LearnerSyncEventType.sandboxBuild
              : LearnerSyncEventType.sandboxRun,
          <String, Object?>{
            'exercise_id': session.exercise.id,
            'language_id': session.selectedVariant.languageId,
            'status': result.status.name,
            'summary': result.summary,
            'passed_case_count': result.executionReport?.passedCaseCount,
            'total_case_count': result.executionReport?.totalCaseCount,
          },
        ),
      );

      return result;
    } catch (error) {
      final result = ValidationResult(
        status: ValidationStatus.needsWork,
        summary: action == SandboxExecutionAction.build
            ? 'Build request failed.'
            : 'Run request failed.',
        output: error.toString(),
        executionReport: null,
        matchedRequirements: session.validationResult.matchedRequirements,
        missingRequirements: session.validationResult.missingRequirements,
        suggestedReviewSkillIds:
            session.validationResult.suggestedReviewSkillIds,
      );

      final latestSession = _activeSession ?? session;
      _activeSession = latestSession.copyWith(
        validationResult: result,
        sessionLog: <String>[
          ...latestSession.sessionLog,
          action == SandboxExecutionAction.build
              ? 'Sandbox build failed to start.'
              : 'Sandbox run failed to start.',
        ],
        executionHistory: _nextExecutionHistory(
          latestSession,
          action: action,
          result: result,
        ),
      );
      notifyListeners();
      return result;
    }
  }

  ValidationResult checkSession() {
    final session = _activeSession;
    if (session == null) {
      return ValidationResult.idle;
    }

    final matched = <String>[];
    final missing = <String>[];
    for (final requirement in session.exercise.requirements) {
      final exp =
          RegExp(requirement.pattern, multiLine: true, caseSensitive: false);
      if (exp.hasMatch(session.code)) {
        matched.add(requirement.label);
      } else {
        missing.add(requirement.feedback);
      }
    }

    final passed = missing.isEmpty;
    if (passed) {
      _completedExercises.add(session.exercise.id);
    }

    for (final skillId in session.exercise.skillIds) {
      final record = _skillMemory[skillId];
      if (record == null) {
        continue;
      }
      if (passed) {
        _skillMemory[skillId] = record.copyWith(
          masteryScore: (record.masteryScore + 0.08).clamp(0.0, 1.0),
          confidenceScore: (record.confidenceScore + 0.07).clamp(0.0, 1.0),
          hintDependence: (record.hintDependence - 0.04).clamp(0.0, 1.0),
          lastOutcome: 'Passed ${session.exercise.title}',
        );
      } else {
        _skillMemory[skillId] = record.copyWith(
          masteryScore: (record.masteryScore - 0.03).clamp(0.0, 1.0),
          confidenceScore: (record.confidenceScore - 0.02).clamp(0.0, 1.0),
          failureCount: record.failureCount + 1,
          lastOutcome: 'Missed part of ${session.exercise.title}',
        );
      }
    }

    final result = ValidationResult(
      status: passed ? ValidationStatus.passed : ValidationStatus.needsWork,
      summary: passed
          ? 'Nice work. This exercise meets the core acceptance checks.'
          : 'Close. Tighten the missing pieces below and run Check again.',
      output: passed
          ? 'Core requirements matched.\n\nReflection prompts:\n- ${session.exercise.reflectionPrompts.join('\n- ')}'
          : 'Missing focus areas:\n- ${missing.join('\n- ')}',
      executionReport: null,
      matchedRequirements: matched,
      missingRequirements: missing,
      suggestedReviewSkillIds: passed ? <String>[] : session.exercise.skillIds,
    );

    _activeSession = session.copyWith(
      validationResult: result,
      sessionLog: <String>[
        ...session.sessionLog,
        passed ? 'Passed validation.' : 'Validation needs more work.',
      ],
    );

    notifyListeners();
    unawaited(
      _persistDerivedStateAndSync(
        eventType: passed
            ? LearnerSyncEventType.checkPassed
            : LearnerSyncEventType.checkFailed,
        payload: <String, Object?>{
          'exercise_id': session.exercise.id,
          'matched_requirements': matched,
          'missing_requirements': missing,
          'skill_ids': session.exercise.skillIds,
          'language_id': session.selectedVariant.languageId,
        },
      ),
    );
    if (passed) {
      unawaited(
        _recordEvent(
          LearnerSyncEventType.milestoneCompleted,
          <String, Object?>{
            'exercise_id': session.exercise.id,
            'track_id': session.track?.id,
          },
        ),
      );
    }
    return result;
  }

  bool isExerciseCompleted(String exerciseId) =>
      _completedExercises.contains(exerciseId);

  bool isMilestoneCompleted(String milestoneId) =>
      isExerciseCompleted(milestoneId);

  Map<String, String> _initialFileContentsFor(ExerciseLanguageVariant variant) {
    final fileContents = <String, String>{
      ...variant.starterFiles,
    };
    fileContents.putIfAbsent(variant.entryFilePath, () => variant.starterCode);
    return fileContents;
  }

  List<ExecutionAttempt> _nextExecutionHistory(
    PracticeSession session, {
    required SandboxExecutionAction action,
    required ValidationResult result,
  }) {
    final report = result.executionReport;
    final nextEntry = ExecutionAttempt(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      actionLabel: action == SandboxExecutionAction.build ? 'Build' : 'Run',
      statusLabel: result.status.name,
      summary: result.summary,
      timestamp: DateTime.now(),
      passedCaseCount: report?.passedCaseCount,
      totalCaseCount: report?.totalCaseCount,
    );

    return <ExecutionAttempt>[
      nextEntry,
      ...session.executionHistory,
    ].take(8).toList(growable: false);
  }

  double completionForTrack(LearningTrack track) {
    if (track.exerciseRefs.isEmpty) {
      return 0;
    }
    final completed = track.exerciseRefs
        .where((ref) => isExerciseCompleted(ref.exerciseId))
        .length;
    return completed / track.exerciseRefs.length;
  }

  Future<void> _persistDerivedStateAndSync({
    required LearnerSyncEventType eventType,
    required Map<String, Object?> payload,
  }) async {
    await _learnerRepository.saveDerivedState(
      skillMemory: _skillMemory,
      reviewQueue: reviewQueue,
      dashboardStats: dashboardStats,
      completedExerciseIds: _completedExercises,
    );
    await _recordEvent(eventType, payload);
  }

  Future<void> _recordEvent(
    LearnerSyncEventType type,
    Map<String, Object?> payload,
  ) async {
    await _syncRepository.enqueueEvent(
      PendingSyncEvent(
        clientEventId:
            '${DateTime.now().microsecondsSinceEpoch}-${type.name}-${Random().nextInt(1 << 32)}',
        type: type,
        occurredAt: DateTime.now().toUtc(),
        payload: payload,
      ),
    );

    try {
      final flushed = await _syncRepository.flushPendingEvents(
        learnerProfile: _learnerProfile,
      );
      if (flushed) {
        await _learnerRepository.refreshLearnerState();
      }
      _learnerProfile = await _learnerRepository.readCachedLearnerProfile() ??
          _learnerProfile;
    } catch (_) {
      // Keep pending events queued for the next retry.
    }
  }

  LearningExercise? _findExerciseById(String exerciseId) {
    for (final exercise in _exercises) {
      if (exercise.id == exerciseId) {
        return exercise;
      }
    }
    return null;
  }

  static Map<String, SkillMasteryRecord> _normalizeSkillMemory(
    List<SkillNode> skillNodes,
    Map<String, SkillMasteryRecord> cachedSkillMemory,
  ) {
    final normalized = <String, SkillMasteryRecord>{
      ...cachedSkillMemory,
    };

    for (final skillNode in skillNodes) {
      normalized.putIfAbsent(skillNode.id, () => _defaultRecord(skillNode.id));
    }

    return normalized;
  }

  static SkillMasteryRecord _defaultRecord(String skillId) {
    return SkillMasteryRecord(
      skillId: skillId,
      masteryScore: 0.5,
      confidenceScore: 0.5,
      hintDependence: 0.0,
      failureCount: 0,
      lastOutcome: 'Waiting for your first real attempt.',
    );
  }
}
