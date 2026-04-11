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
    required List<SkillNode> skillNodes,
    required Map<String, SkillMasteryRecord> skillMemory,
    required Set<String> completedMilestones,
  })  : _catalogRepository = catalogRepository,
        _learnerRepository = learnerRepository,
        _syncRepository = syncRepository,
        _sandboxApiService = sandboxApiService,
        _learnerProfile = learnerProfile,
        _tracks = tracks,
        _skillNodes = skillNodes,
        _skillMemory = skillMemory,
        _completedMilestones = completedMilestones;

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
    final skillNodes = await resolvedCatalogRepository.readCachedSkillNodes();
    final cachedSkillMemory =
        await resolvedLearnerRepository.readCachedSkillMemory();
    final completedMilestones =
        await resolvedLearnerRepository.readCachedCompletedMilestoneIds();

    return AppState._(
      catalogRepository: resolvedCatalogRepository,
      learnerRepository: resolvedLearnerRepository,
      syncRepository: resolvedSyncRepository,
      sandboxApiService: sandboxApiService ?? SandboxApiService(),
      learnerProfile: learnerProfile,
      tracks: tracks,
      skillNodes: skillNodes,
      skillMemory: _normalizeSkillMemory(skillNodes, cachedSkillMemory),
      completedMilestones: completedMilestones,
    );
  }

  final CatalogRepository _catalogRepository;
  final LearnerRepository _learnerRepository;
  final SyncRepository _syncRepository;
  final SandboxApiService _sandboxApiService;
  LearnerProfile _learnerProfile;

  final List<LearningTrack> _tracks;
  final List<SkillNode> _skillNodes;
  final Map<String, SkillMasteryRecord> _skillMemory;
  final Set<String> _completedMilestones;
  Future<ValidationResult>? _inFlightSandboxExecution;
  PracticeSession? _activeSession;

  List<LearningTrack> get tracks => List<LearningTrack>.unmodifiable(_tracks);
  List<SkillNode> get skillNodes => List<SkillNode>.unmodifiable(_skillNodes);
  PracticeSession? get activeSession => _activeSession;
  bool get isSandboxExecutionRunning =>
      _inFlightSandboxExecution != null ||
      _activeSession?.validationResult.status == ValidationStatus.running;
  Map<String, SkillMasteryRecord> get skillMemory =>
      Map<String, SkillMasteryRecord>.unmodifiable(_skillMemory);
  LearnerProfile get learnerProfile => _learnerProfile;

  List<LearningTrack> tracksForType(LearningTrackType type) {
    return _tracks.where((track) => track.type == type).toList(growable: false);
  }

  DashboardStats get dashboardStats {
    final reviewCount = reviewQueue.length;
    final average = _skillMemory.values.isEmpty
        ? 0.0
        : _skillMemory.values
                .map((record) => record.masteryScore)
                .reduce((value, element) => value + element) /
            _skillMemory.length;
    final completedProjectCount = _completedMilestones
        .where((id) =>
            _findMilestoneById(id)?.track.type == LearningTrackType.project)
        .length;
    final completedAlgoCount =
        _completedMilestones.length - completedProjectCount;

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
        final milestoneInfo = _findMilestoneById(skill.reviewMilestoneId);
        if (milestoneInfo == null) {
          continue;
        }
        tasks.add(
          ReviewTask(
            id: 'review_${skill.id}',
            title: 'Review ${skill.title}',
            description: '${skill.description} ${record.lastOutcome}',
            skillIds: <String>[skill.id],
            milestoneId: skill.reviewMilestoneId,
            laneLabel: milestoneInfo.track.type.label,
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
    final latestSkillNodes = await _catalogRepository.readCachedSkillNodes();
    final latestSkillMemory = await _learnerRepository.readCachedSkillMemory();
    final latestCompletedMilestones =
        await _learnerRepository.readCachedCompletedMilestoneIds();
    final latestLearnerProfile =
        await _learnerRepository.readCachedLearnerProfile() ?? _learnerProfile;

    _tracks
      ..clear()
      ..addAll(latestTracks);
    _skillNodes
      ..clear()
      ..addAll(latestSkillNodes);
    _skillMemory
      ..clear()
      ..addAll(_normalizeSkillMemory(latestSkillNodes, latestSkillMemory));
    _completedMilestones
      ..clear()
      ..addAll(latestCompletedMilestones);
    _learnerProfile = latestLearnerProfile;
    notifyListeners();
  }

  void startSession({
    required LearningTrack track,
    required LearningModule module,
    required Milestone milestone,
    PracticeMode mode = PracticeMode.guided,
  }) {
    final fileContents = _initialFileContentsFor(milestone);
    final activeFilePath = milestone.relatedFiles.isEmpty
        ? 'solution.txt'
        : milestone.relatedFiles.first;
    _activeSession = PracticeSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      track: track,
      module: module,
      milestone: milestone,
      mode: mode,
      fileContents: fileContents,
      activeFilePath: activeFilePath,
      revealedHintLevel: null,
      validationResult: ValidationResult.idle,
      sessionLog: <String>[
        'Opened ${milestone.title} in ${mode.label} mode.',
      ],
      executionHistory: const <ExecutionAttempt>[],
    );
    notifyListeners();
    unawaited(
      _recordEvent(
        LearnerSyncEventType.sessionStarted,
        <String, Object?>{
          'track_id': track.id,
          'module_id': module.id,
          'milestone_id': milestone.id,
          'mode': mode.name,
        },
      ),
    );
  }

  bool startReviewTask(ReviewTask task) {
    final milestoneInfo = _findMilestoneById(task.milestoneId);
    if (milestoneInfo == null) {
      return false;
    }
    startSession(
      track: milestoneInfo.track,
      module: milestoneInfo.module,
      milestone: milestoneInfo.milestone,
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
    final hint = session.milestone.hints[nextLevel] ?? 'No hint available.';

    _activeSession = session.copyWith(
      revealedHintLevel: nextLevel,
      sessionLog: <String>[
        ...session.sessionLog,
        'Opened ${nextLevel.label}.',
      ],
    );

    for (final skillId in session.milestone.skillIds) {
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
          'milestone_id': session.milestone.id,
          'hint_level': nextLevel.name,
          'skill_ids': session.milestone.skillIds,
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
        milestone: session.milestone,
        fileContents: session.fileContents,
        entryFilePath:
            session.milestone.sandboxEntryFilePath ?? session.primaryFilePath,
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
            'milestone_id': session.milestone.id,
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
    for (final requirement in session.milestone.requirements) {
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
      _completedMilestones.add(session.milestone.id);
    }

    for (final skillId in session.milestone.skillIds) {
      final record = _skillMemory[skillId];
      if (record == null) {
        continue;
      }
      if (passed) {
        _skillMemory[skillId] = record.copyWith(
          masteryScore: (record.masteryScore + 0.08).clamp(0.0, 1.0),
          confidenceScore: (record.confidenceScore + 0.07).clamp(0.0, 1.0),
          hintDependence: (record.hintDependence - 0.04).clamp(0.0, 1.0),
          lastOutcome: 'Passed ${session.milestone.title}',
        );
      } else {
        _skillMemory[skillId] = record.copyWith(
          masteryScore: (record.masteryScore - 0.03).clamp(0.0, 1.0),
          confidenceScore: (record.confidenceScore - 0.02).clamp(0.0, 1.0),
          failureCount: record.failureCount + 1,
          lastOutcome: 'Missed part of ${session.milestone.title}',
        );
      }
    }

    final result = ValidationResult(
      status: passed ? ValidationStatus.passed : ValidationStatus.needsWork,
      summary: passed
          ? 'Nice work. This milestone meets the core acceptance checks.'
          : 'Close. Tighten the missing pieces below and run Check again.',
      output: passed
          ? 'Core requirements matched.\n\nReflection prompts:\n- ${session.milestone.reflectionPrompts.join('\n- ')}'
          : 'Missing focus areas:\n- ${missing.join('\n- ')}',
      executionReport: null,
      matchedRequirements: matched,
      missingRequirements: missing,
      suggestedReviewSkillIds: passed ? <String>[] : session.milestone.skillIds,
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
        eventType:
            passed ? LearnerSyncEventType.checkPassed : LearnerSyncEventType.checkFailed,
        payload: <String, Object?>{
          'milestone_id': session.milestone.id,
          'matched_requirements': matched,
          'missing_requirements': missing,
          'skill_ids': session.milestone.skillIds,
        },
      ),
    );
    if (passed) {
      unawaited(
        _recordEvent(
          LearnerSyncEventType.milestoneCompleted,
          <String, Object?>{
            'milestone_id': session.milestone.id,
            'track_id': session.track.id,
            'module_id': session.module.id,
          },
        ),
      );
    }
    return result;
  }

  bool isMilestoneCompleted(String milestoneId) =>
      _completedMilestones.contains(milestoneId);

  Map<String, String> _initialFileContentsFor(Milestone milestone) {
    if (milestone.relatedFiles.isEmpty) {
      return <String, String>{
        'solution.txt':
            milestone.starterFiles['solution.txt'] ?? milestone.starterCode,
      };
    }

    final fileContents = <String, String>{};
    for (var i = 0; i < milestone.relatedFiles.length; i += 1) {
      final path = milestone.relatedFiles[i];
      fileContents[path] =
          milestone.starterFiles[path] ?? (i == 0 ? milestone.starterCode : '');
    }
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
    final total = track.modules
        .fold<int>(0, (sum, module) => sum + module.milestones.length);
    if (total == 0) {
      return 0;
    }
    final completed = track.modules.fold<int>(
      0,
      (sum, module) =>
          sum +
          module.milestones.where((m) => isMilestoneCompleted(m.id)).length,
    );
    return completed / total;
  }

  MilestoneBundle? _findMilestoneById(String milestoneId) {
    for (final track in _tracks) {
      for (final module in track.modules) {
        for (final milestone in module.milestones) {
          if (milestone.id == milestoneId) {
            return MilestoneBundle(
              track: track,
              module: module,
              milestone: milestone,
            );
          }
        }
      }
    }
    return null;
  }

  Future<void> _persistDerivedStateAndSync({
    required LearnerSyncEventType eventType,
    required Map<String, Object?> payload,
  }) async {
    await _learnerRepository.saveDerivedState(
      skillMemory: _skillMemory,
      reviewQueue: reviewQueue,
      dashboardStats: dashboardStats,
      completedMilestoneIds: _completedMilestones,
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
      _learnerProfile =
          await _learnerRepository.readCachedLearnerProfile() ?? _learnerProfile;
    } catch (_) {
      // Keep pending events queued for the next retry.
    }
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

class MilestoneBundle {
  const MilestoneBundle({
    required this.track,
    required this.module,
    required this.milestone,
  });

  final LearningTrack track;
  final LearningModule module;
  final Milestone milestone;
}
