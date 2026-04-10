import 'package:flutter/material.dart';

enum LearningTrackType { project, dataStructure, leetcode }

enum PracticeMode { guided, standard, timed }

enum HintLevel { concept, structure, pseudocode, lineHint, fullExplain }

enum SkillCategory {
  languageSyntax,
  oopClassDesign,
  dataStructureFundamentals,
  algorithmPatterns,
  debugging,
  testingEdgeCases,
}

enum ValidationStatus { idle, running, passed, needsWork }

class LearningTrack {
  const LearningTrack({
    required this.id,
    required this.title,
    required this.summary,
    required this.type,
    required this.difficultyLabel,
    required this.focusAreas,
    required this.modules,
  });

  final String id;
  final String title;
  final String summary;
  final LearningTrackType type;
  final String difficultyLabel;
  final List<String> focusAreas;
  final List<LearningModule> modules;
}

class LearningModule {
  const LearningModule({
    required this.id,
    required this.title,
    required this.summary,
    required this.estimatedMinutes,
    required this.milestones,
  });

  final String id;
  final String title;
  final String summary;
  final int estimatedMinutes;
  final List<Milestone> milestones;
}

class Milestone {
  const Milestone({
    required this.id,
    required this.title,
    required this.objective,
    required this.problemStatement,
    required this.languageLabel,
    required this.relatedFiles,
    required this.acceptanceCriteria,
    required this.taskSteps,
    required this.supportedModes,
    required this.hints,
    required this.starterCode,
    required this.exampleInput,
    required this.exampleOutput,
    this.sandboxHarnessTemplate = defaultSandboxHarnessTemplate,
    this.testCases = const <ExecutionTestCase>[],
    required this.reflectionPrompts,
    required this.skillIds,
    required this.requirements,
    this.runCommand = 'python main.py',
    this.reviewPrompt,
  });

  final String id;
  final String title;
  final String objective;
  final String problemStatement;
  final String languageLabel;
  final List<String> relatedFiles;
  final List<String> acceptanceCriteria;
  final List<TaskStep> taskSteps;
  final List<PracticeMode> supportedModes;
  final Map<HintLevel, String> hints;
  final String starterCode;
  final String exampleInput;
  final String exampleOutput;
  final String sandboxHarnessTemplate;
  final List<ExecutionTestCase> testCases;
  final List<String> reflectionPrompts;
  final List<String> skillIds;
  final List<RequirementCheck> requirements;
  final String runCommand;
  final String? reviewPrompt;

  static const String defaultSandboxHarnessTemplate = '''{{USER_CODE}}

{{TEST_BODY}}
''';
}

class TaskStep {
  const TaskStep({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;
}

class ExecutionTestCase {
  const ExecutionTestCase({
    required this.id,
    required this.label,
    required this.body,
    required this.expectedOutput,
  });

  final String id;
  final String label;
  final String body;
  final String expectedOutput;
}

class RequirementCheck {
  const RequirementCheck({
    required this.label,
    required this.pattern,
    required this.feedback,
  });

  final String label;
  final String pattern;
  final String feedback;
}

class SkillNode {
  const SkillNode({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.reviewMilestoneId,
  });

  final String id;
  final String title;
  final SkillCategory category;
  final String description;
  final String reviewMilestoneId;
}

class SkillMasteryRecord {
  const SkillMasteryRecord({
    required this.skillId,
    required this.masteryScore,
    required this.confidenceScore,
    required this.hintDependence,
    required this.failureCount,
    required this.lastOutcome,
  });

  final String skillId;
  final double masteryScore;
  final double confidenceScore;
  final double hintDependence;
  final int failureCount;
  final String lastOutcome;

  SkillMasteryRecord copyWith({
    double? masteryScore,
    double? confidenceScore,
    double? hintDependence,
    int? failureCount,
    String? lastOutcome,
  }) {
    return SkillMasteryRecord(
      skillId: skillId,
      masteryScore: masteryScore ?? this.masteryScore,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      hintDependence: hintDependence ?? this.hintDependence,
      failureCount: failureCount ?? this.failureCount,
      lastOutcome: lastOutcome ?? this.lastOutcome,
    );
  }
}

class PracticeSession {
  const PracticeSession({
    required this.id,
    required this.track,
    required this.module,
    required this.milestone,
    required this.mode,
    required this.fileContents,
    required this.activeFilePath,
    required this.revealedHintLevel,
    required this.validationResult,
    required this.sessionLog,
    required this.executionHistory,
  });

  final String id;
  final LearningTrack track;
  final LearningModule module;
  final Milestone milestone;
  final PracticeMode mode;
  final Map<String, String> fileContents;
  final String activeFilePath;
  final HintLevel? revealedHintLevel;
  final ValidationResult validationResult;
  final List<String> sessionLog;
  final List<ExecutionAttempt> executionHistory;

  String get primaryFilePath => milestone.relatedFiles.isEmpty
      ? activeFilePath
      : milestone.relatedFiles.first;

  String get code => fileContentFor(primaryFilePath);

  String fileContentFor(String path) => fileContents[path] ?? '';

  PracticeSession copyWith({
    Map<String, String>? fileContents,
    String? activeFilePath,
    HintLevel? revealedHintLevel,
    bool clearHint = false,
    ValidationResult? validationResult,
    List<String>? sessionLog,
    List<ExecutionAttempt>? executionHistory,
  }) {
    return PracticeSession(
      id: id,
      track: track,
      module: module,
      milestone: milestone,
      mode: mode,
      fileContents: fileContents ?? this.fileContents,
      activeFilePath: activeFilePath ?? this.activeFilePath,
      revealedHintLevel:
          clearHint ? null : (revealedHintLevel ?? this.revealedHintLevel),
      validationResult: validationResult ?? this.validationResult,
      sessionLog: sessionLog ?? this.sessionLog,
      executionHistory: executionHistory ?? this.executionHistory,
    );
  }
}

class ExecutionAttempt {
  const ExecutionAttempt({
    required this.id,
    required this.actionLabel,
    required this.statusLabel,
    required this.summary,
    required this.timestamp,
    this.passedCaseCount,
    this.totalCaseCount,
  });

  final String id;
  final String actionLabel;
  final String statusLabel;
  final String summary;
  final DateTime timestamp;
  final int? passedCaseCount;
  final int? totalCaseCount;
}

class ValidationResult {
  const ValidationResult({
    required this.status,
    required this.summary,
    required this.output,
    this.executionReport,
    required this.matchedRequirements,
    required this.missingRequirements,
    required this.suggestedReviewSkillIds,
  });

  final ValidationStatus status;
  final String summary;
  final String output;
  final ExecutionReport? executionReport;
  final List<String> matchedRequirements;
  final List<String> missingRequirements;
  final List<String> suggestedReviewSkillIds;

  static const idle = ValidationResult(
    status: ValidationStatus.idle,
    summary: 'Ready to check your work.',
    output: 'Tap Check or Run when you want feedback.',
    executionReport: null,
    matchedRequirements: <String>[],
    missingRequirements: <String>[],
    suggestedReviewSkillIds: <String>[],
  );
}

class ExecutionReport {
  const ExecutionReport({
    required this.engineLabel,
    required this.statusLabel,
    required this.passedCaseCount,
    required this.totalCaseCount,
    required this.sections,
    required this.caseResults,
  });

  final String engineLabel;
  final String statusLabel;
  final int passedCaseCount;
  final int totalCaseCount;
  final List<ExecutionOutputSection> sections;
  final List<ExecutionCaseResult> caseResults;
}

class ExecutionOutputSection {
  const ExecutionOutputSection({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;
}

class ExecutionCaseResult {
  const ExecutionCaseResult({
    required this.id,
    required this.label,
    required this.passed,
    required this.statusLabel,
    required this.expectedOutput,
    required this.actualOutput,
    required this.stdout,
    required this.stderr,
    required this.compileOutput,
    required this.message,
  });

  final String id;
  final String label;
  final bool passed;
  final String statusLabel;
  final String expectedOutput;
  final String actualOutput;
  final String stdout;
  final String stderr;
  final String compileOutput;
  final String message;
}

class ReviewTask {
  const ReviewTask({
    required this.id,
    required this.title,
    required this.description,
    required this.skillIds,
    required this.milestoneId,
    required this.laneLabel,
  });

  final String id;
  final String title;
  final String description;
  final List<String> skillIds;
  final String milestoneId;
  final String laneLabel;
}

class DashboardStats {
  const DashboardStats({
    required this.completedProjects,
    required this.completedDsAlgo,
    required this.reviewQueueCount,
    required this.averageMastery,
  });

  final int completedProjects;
  final int completedDsAlgo;
  final int reviewQueueCount;
  final double averageMastery;
}

extension LearningTrackTypeCopy on LearningTrackType {
  String get label {
    switch (this) {
      case LearningTrackType.project:
        return 'Projects';
      case LearningTrackType.dataStructure:
        return 'DS & Algo';
      case LearningTrackType.leetcode:
        return 'LeetCode';
    }
  }

  IconData get icon {
    switch (this) {
      case LearningTrackType.project:
        return Icons.widgets_rounded;
      case LearningTrackType.dataStructure:
        return Icons.account_tree_rounded;
      case LearningTrackType.leetcode:
        return Icons.bolt_rounded;
    }
  }
}

extension PracticeModeCopy on PracticeMode {
  String get label {
    switch (this) {
      case PracticeMode.guided:
        return 'Guided';
      case PracticeMode.standard:
        return 'Standard';
      case PracticeMode.timed:
        return 'Timed';
    }
  }
}

extension HintLevelCopy on HintLevel {
  String get label {
    switch (this) {
      case HintLevel.concept:
        return 'Concept hint';
      case HintLevel.structure:
        return 'Structure hint';
      case HintLevel.pseudocode:
        return 'Pseudocode hint';
      case HintLevel.lineHint:
        return 'Line hint';
      case HintLevel.fullExplain:
        return 'Full explanation';
    }
  }
}
