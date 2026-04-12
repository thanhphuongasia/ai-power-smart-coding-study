import 'package:flutter/material.dart';

enum LearningTrackType { project, dataStructure, leetcode }

enum LearningLevel { foundation, intermediate, advanced }

enum ContentKind {
  projectTrack,
  projectExercise,
  dsaTrack,
  dsaExercise,
  leetcodeSet,
  leetcodeExercise,
}

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
    required this.contentKind,
    required this.level,
    required this.topicIds,
    required this.domainIds,
    required this.tags,
    required this.skillIds,
    required this.exerciseRefs,
  });

  final String id;
  final String title;
  final String summary;
  final LearningTrackType type;
  final ContentKind contentKind;
  final LearningLevel level;
  final List<String> topicIds;
  final List<String> domainIds;
  final List<String> tags;
  final List<String> skillIds;
  final List<TrackExerciseRef> exerciseRefs;
}

class TrackExerciseRef {
  const TrackExerciseRef({
    required this.exerciseId,
    this.title,
    this.summary,
    this.milestoneLabel,
  });

  final String exerciseId;
  final String? title;
  final String? summary;
  final String? milestoneLabel;
}

class LearningExercise {
  const LearningExercise({
    required this.id,
    required this.title,
    required this.summary,
    required this.type,
    required this.contentKind,
    required this.level,
    required this.topicIds,
    required this.domainIds,
    required this.tags,
    required this.skillIds,
    required this.problemStatement,
    required this.acceptanceCriteria,
    required this.taskSteps,
    required this.supportedModes,
    required this.hints,
    required this.reflectionPrompts,
    required this.requirements,
    required this.languageVariants,
  });

  final String id;
  final String title;
  final String summary;
  final LearningTrackType type;
  final ContentKind contentKind;
  final LearningLevel level;
  final List<String> topicIds;
  final List<String> domainIds;
  final List<String> tags;
  final List<String> skillIds;
  final String problemStatement;
  final List<String> acceptanceCriteria;
  final List<TaskStep> taskSteps;
  final List<PracticeMode> supportedModes;
  final Map<HintLevel, String> hints;
  final List<String> reflectionPrompts;
  final List<RequirementCheck> requirements;
  final List<ExerciseLanguageVariant> languageVariants;

  ExerciseLanguageVariant resolveVariant({
    String? preferredLanguageId,
    String? explicitLanguageId,
  }) {
    if (explicitLanguageId != null) {
      for (final variant in languageVariants) {
        if (variant.languageId == explicitLanguageId) {
          return variant;
        }
      }
    }
    if (preferredLanguageId != null) {
      for (final variant in languageVariants) {
        if (variant.languageId == preferredLanguageId) {
          return variant;
        }
      }
    }
    for (final variant in languageVariants) {
      if (variant.isDefault) {
        return variant;
      }
    }
    return languageVariants.first;
  }
}

class ExerciseLanguageVariant {
  const ExerciseLanguageVariant({
    required this.languageId,
    required this.languageLabel,
    required this.isDefault,
    required this.starterCode,
    this.starterFiles = const <String, String>{},
    this.solutionCode,
    this.sandboxHarnessTemplate =
        ExerciseLanguageVariant.defaultSandboxHarnessTemplate,
    required this.runCommand,
    required this.entryFilePath,
    this.demoFilePath,
    this.testCases = const <ExecutionTestCase>[],
  });

  final String languageId;
  final String languageLabel;
  final bool isDefault;
  final String starterCode;
  final Map<String, String> starterFiles;
  final String? solutionCode;
  final String sandboxHarnessTemplate;
  final String runCommand;
  final String entryFilePath;
  final String? demoFilePath;
  final List<ExecutionTestCase> testCases;

  static const String defaultSandboxHarnessTemplate = '''{{USER_CODE}}

{{TEST_BODY}}
''';
}

class TopicDefinition {
  const TopicDefinition({
    required this.id,
    required this.title,
    required this.summary,
  });

  final String id;
  final String title;
  final String summary;
}

class DomainDefinition {
  const DomainDefinition({
    required this.id,
    required this.title,
    required this.summary,
  });

  final String id;
  final String title;
  final String summary;
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
    required this.reviewExerciseId,
  });

  final String id;
  final String title;
  final SkillCategory category;
  final String description;
  final String reviewExerciseId;
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
    required this.exercise,
    required this.selectedVariant,
    required this.mode,
    this.track,
    this.openEditorOnStart = false,
    required this.fileContents,
    required this.activeFilePath,
    required this.revealedHintLevel,
    required this.validationResult,
    required this.sessionLog,
    required this.executionHistory,
  });

  final String id;
  final LearningExercise exercise;
  final ExerciseLanguageVariant selectedVariant;
  final PracticeMode mode;
  final LearningTrack? track;
  final bool openEditorOnStart;
  final Map<String, String> fileContents;
  final String activeFilePath;
  final HintLevel? revealedHintLevel;
  final ValidationResult validationResult;
  final List<String> sessionLog;
  final List<ExecutionAttempt> executionHistory;

  SessionMilestoneView get milestone =>
      SessionMilestoneView(exercise: exercise, variant: selectedVariant);

  String get primaryFilePath => selectedVariant.entryFilePath;

  String get code => fileContentFor(primaryFilePath);

  List<String> get relatedFiles => fileContents.keys.toList(growable: false);

  String fileContentFor(String path) => fileContents[path] ?? '';

  PracticeSession copyWith({
    ExerciseLanguageVariant? selectedVariant,
    bool? openEditorOnStart,
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
      exercise: exercise,
      selectedVariant: selectedVariant ?? this.selectedVariant,
      mode: mode,
      track: track,
      openEditorOnStart: openEditorOnStart ?? this.openEditorOnStart,
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

class SessionMilestoneView {
  const SessionMilestoneView({
    required this.exercise,
    required this.variant,
  });

  final LearningExercise exercise;
  final ExerciseLanguageVariant variant;

  String get id => exercise.id;
  String get title => exercise.title;
  String get objective => exercise.summary;
  String get problemStatement => exercise.problemStatement;
  String get languageLabel => variant.languageLabel;
  List<String> get relatedFiles {
    final files = <String>{
      variant.entryFilePath,
      ...variant.starterFiles.keys,
    };
    return files.toList(growable: false);
  }

  List<String> get acceptanceCriteria => exercise.acceptanceCriteria;
  List<TaskStep> get taskSteps => exercise.taskSteps;
  List<PracticeMode> get supportedModes => exercise.supportedModes;
  Map<HintLevel, String> get hints => exercise.hints;
  String get starterCode => variant.starterCode;
  Map<String, String> get starterFiles => variant.starterFiles;
  String? get solutionCode => variant.solutionCode;
  String get exampleInput => '';
  String get exampleOutput => '';
  String get sandboxHarnessTemplate => variant.sandboxHarnessTemplate;
  String? get sandboxEntryFilePath => variant.entryFilePath;
  String? get demoFilePath => variant.demoFilePath;
  List<ExecutionTestCase> get testCases => variant.testCases;
  List<String> get reflectionPrompts => exercise.reflectionPrompts;
  List<String> get skillIds => exercise.skillIds;
  List<RequirementCheck> get requirements => exercise.requirements;
  String get runCommand => variant.runCommand;
  String? get reviewPrompt => null;
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
    required this.programResult,
    required this.sections,
    required this.caseResults,
  });

  final String engineLabel;
  final String statusLabel;
  final int passedCaseCount;
  final int totalCaseCount;
  final ExecutionProgramResult? programResult;
  final List<ExecutionOutputSection> sections;
  final List<ExecutionCaseResult> caseResults;
}

class ExecutionProgramResult {
  const ExecutionProgramResult({
    required this.label,
    required this.passed,
    required this.statusLabel,
    required this.actualOutput,
    required this.stdout,
    required this.stderr,
    required this.compileOutput,
    required this.message,
  });

  final String label;
  final bool passed;
  final String statusLabel;
  final String actualOutput;
  final String stdout;
  final String stderr;
  final String compileOutput;
  final String message;
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
    required this.exerciseId,
    required this.laneLabel,
  });

  final String id;
  final String title;
  final String description;
  final List<String> skillIds;
  final String exerciseId;
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

class SkillMasteryView {
  const SkillMasteryView({
    required this.skill,
    required this.record,
  });

  final SkillNode skill;
  final SkillMasteryRecord record;
}

extension LearningTrackTypeCopy on LearningTrackType {
  String get label {
    switch (this) {
      case LearningTrackType.project:
        return 'Projects';
      case LearningTrackType.dataStructure:
        return 'DSA';
      case LearningTrackType.leetcode:
        return 'LeetCode';
    }
  }

  String get wireValue {
    switch (this) {
      case LearningTrackType.project:
        return 'project';
      case LearningTrackType.dataStructure:
        return 'dsa';
      case LearningTrackType.leetcode:
        return 'leetcode';
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

extension LearningLevelCopy on LearningLevel {
  String get label {
    switch (this) {
      case LearningLevel.foundation:
        return 'Foundation';
      case LearningLevel.intermediate:
        return 'Intermediate';
      case LearningLevel.advanced:
        return 'Advanced';
    }
  }
}

extension ContentKindCopy on ContentKind {
  bool get isTrack {
    switch (this) {
      case ContentKind.projectTrack:
      case ContentKind.dsaTrack:
      case ContentKind.leetcodeSet:
        return true;
      case ContentKind.projectExercise:
      case ContentKind.dsaExercise:
      case ContentKind.leetcodeExercise:
        return false;
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
