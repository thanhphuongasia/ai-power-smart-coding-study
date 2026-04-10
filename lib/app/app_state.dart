import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/sample_curriculum.dart';
import '../models/learning_models.dart';
import '../services/sandbox_api_service.dart';

class AppState extends ChangeNotifier {
  AppState.seeded({
    SandboxApiService? sandboxApiService,
  })  : _sandboxApiService = sandboxApiService ?? SandboxApiService(),
        _tracks = SeedData.tracks(),
        _skillNodes = SeedData.skills(),
        _skillMemory = SeedData.skillMemory();

  final SandboxApiService _sandboxApiService;
  final List<LearningTrack> _tracks;
  final List<SkillNode> _skillNodes;
  final Map<String, SkillMasteryRecord> _skillMemory;
  final Set<String> _completedMilestones = <String>{};
  PracticeSession? _activeSession;

  List<LearningTrack> get tracks => List<LearningTrack>.unmodifiable(_tracks);
  List<SkillNode> get skillNodes => List<SkillNode>.unmodifiable(_skillNodes);
  PracticeSession? get activeSession => _activeSession;
  Map<String, SkillMasteryRecord> get skillMemory =>
      Map<String, SkillMasteryRecord>.unmodifiable(_skillMemory);

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
      final record = _skillMemory[skill.id]!;
      return SkillMasteryView(skill: skill, record: record);
    }).toList();

    views
        .sort((a, b) => a.record.masteryScore.compareTo(b.record.masteryScore));
    return views;
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
    notifyListeners();
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
    notifyListeners();
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
    return hint;
  }

  Future<ValidationResult> buildSession() {
    return _executeSession(action: SandboxExecutionAction.build);
  }

  Future<ValidationResult> runSession() {
    return _executeSession(action: SandboxExecutionAction.run);
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
        entryFilePath: session.primaryFilePath,
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
    return result;
  }

  bool isMilestoneCompleted(String milestoneId) =>
      _completedMilestones.contains(milestoneId);

  Map<String, String> _initialFileContentsFor(Milestone milestone) {
    if (milestone.relatedFiles.isEmpty) {
      return <String, String>{'solution.txt': milestone.starterCode};
    }

    final fileContents = <String, String>{};
    for (var i = 0; i < milestone.relatedFiles.length; i += 1) {
      final path = milestone.relatedFiles[i];
      fileContents[path] = i == 0 ? milestone.starterCode : '';
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
                track: track, module: module, milestone: milestone);
          }
        }
      }
    }
    return null;
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

class SkillMasteryView {
  const SkillMasteryView({
    required this.skill,
    required this.record,
  });

  final SkillNode skill;
  final SkillMasteryRecord record;
}
