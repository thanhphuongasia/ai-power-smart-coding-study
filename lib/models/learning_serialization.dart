import 'learning_models.dart';

Map<String, Object?> learningTrackToJson(LearningTrack track) {
  return <String, Object?>{
    'id': track.id,
    'title': track.title,
    'summary': track.summary,
    'type': track.type.name,
    'difficultyLabel': track.difficultyLabel,
    'focusAreas': track.focusAreas,
    'modules': track.modules.map(learningModuleToJson).toList(growable: false),
  };
}

LearningTrack learningTrackFromJson(Map<String, dynamic> json) {
  return LearningTrack(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    type: _trackTypeFromName(json['type'] as String?),
    difficultyLabel: json['difficultyLabel'] as String? ?? '',
    focusAreas: _readStringList(json['focusAreas']),
    modules: _readObjectList(json['modules'], learningModuleFromJson),
  );
}

Map<String, Object?> learningModuleToJson(LearningModule module) {
  return <String, Object?>{
    'id': module.id,
    'title': module.title,
    'summary': module.summary,
    'estimatedMinutes': module.estimatedMinutes,
    'milestones':
        module.milestones.map(milestoneToJson).toList(growable: false),
  };
}

LearningModule learningModuleFromJson(Map<String, dynamic> json) {
  return LearningModule(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    estimatedMinutes: json['estimatedMinutes'] as int? ?? 0,
    milestones: _readObjectList(json['milestones'], milestoneFromJson),
  );
}

Map<String, Object?> milestoneToJson(Milestone milestone) {
  return <String, Object?>{
    'id': milestone.id,
    'title': milestone.title,
    'objective': milestone.objective,
    'problemStatement': milestone.problemStatement,
    'languageLabel': milestone.languageLabel,
    'relatedFiles': milestone.relatedFiles,
    'acceptanceCriteria': milestone.acceptanceCriteria,
    'taskSteps': milestone.taskSteps.map(taskStepToJson).toList(growable: false),
    'supportedModes':
        milestone.supportedModes.map((mode) => mode.name).toList(growable: false),
    'hints': <String, String>{
      for (final entry in milestone.hints.entries) entry.key.name: entry.value,
    },
    'starterCode': milestone.starterCode,
    'starterFiles': milestone.starterFiles,
    'solutionCode': milestone.solutionCode,
    'exampleInput': milestone.exampleInput,
    'exampleOutput': milestone.exampleOutput,
    'sandboxHarnessTemplate': milestone.sandboxHarnessTemplate,
    'sandboxEntryFilePath': milestone.sandboxEntryFilePath,
    'demoFilePath': milestone.demoFilePath,
    'testCases':
        milestone.testCases.map(executionTestCaseToJson).toList(growable: false),
    'reflectionPrompts': milestone.reflectionPrompts,
    'skillIds': milestone.skillIds,
    'requirements':
        milestone.requirements.map(requirementCheckToJson).toList(growable: false),
    'runCommand': milestone.runCommand,
    'reviewPrompt': milestone.reviewPrompt,
  };
}

Milestone milestoneFromJson(Map<String, dynamic> json) {
  final rawHints = json['hints'];
  final hints = <HintLevel, String>{};
  if (rawHints is Map) {
    for (final entry in rawHints.entries) {
      final key = _hintLevelFromName(entry.key as String?);
      if (key == null) {
        continue;
      }
      hints[key] = entry.value as String? ?? '';
    }
  }

  return Milestone(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    objective: json['objective'] as String? ?? '',
    problemStatement: json['problemStatement'] as String? ?? '',
    languageLabel: json['languageLabel'] as String? ?? '',
    relatedFiles: _readStringList(json['relatedFiles']),
    acceptanceCriteria: _readStringList(json['acceptanceCriteria']),
    taskSteps: _readObjectList(json['taskSteps'], taskStepFromJson),
    supportedModes: _readList(json['supportedModes'])
        .map((item) => _practiceModeFromName(item as String?))
        .toList(growable: false),
    hints: hints,
    starterCode: json['starterCode'] as String? ?? '',
    starterFiles: _readStringMap(json['starterFiles']),
    solutionCode: json['solutionCode'] as String?,
    exampleInput: json['exampleInput'] as String? ?? '',
    exampleOutput: json['exampleOutput'] as String? ?? '',
    sandboxHarnessTemplate:
        json['sandboxHarnessTemplate'] as String? ??
            Milestone.defaultSandboxHarnessTemplate,
    sandboxEntryFilePath: json['sandboxEntryFilePath'] as String?,
    demoFilePath: json['demoFilePath'] as String?,
    testCases:
        _readObjectList(json['testCases'], executionTestCaseFromJson),
    reflectionPrompts: _readStringList(json['reflectionPrompts']),
    skillIds: _readStringList(json['skillIds']),
    requirements:
        _readObjectList(json['requirements'], requirementCheckFromJson),
    runCommand: json['runCommand'] as String? ?? 'python main.py',
    reviewPrompt: json['reviewPrompt'] as String?,
  );
}

Map<String, Object?> taskStepToJson(TaskStep step) {
  return <String, Object?>{
    'id': step.id,
    'title': step.title,
    'description': step.description,
  };
}

TaskStep taskStepFromJson(Map<String, dynamic> json) {
  return TaskStep(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );
}

Map<String, Object?> executionTestCaseToJson(ExecutionTestCase testCase) {
  return <String, Object?>{
    'id': testCase.id,
    'label': testCase.label,
    'body': testCase.body,
    'expectedOutput': testCase.expectedOutput,
  };
}

ExecutionTestCase executionTestCaseFromJson(Map<String, dynamic> json) {
  return ExecutionTestCase(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    body: json['body'] as String? ?? '',
    expectedOutput: json['expectedOutput'] as String? ?? '',
  );
}

Map<String, Object?> requirementCheckToJson(RequirementCheck requirement) {
  return <String, Object?>{
    'label': requirement.label,
    'pattern': requirement.pattern,
    'feedback': requirement.feedback,
  };
}

RequirementCheck requirementCheckFromJson(Map<String, dynamic> json) {
  return RequirementCheck(
    label: json['label'] as String? ?? '',
    pattern: json['pattern'] as String? ?? '',
    feedback: json['feedback'] as String? ?? '',
  );
}

Map<String, Object?> skillNodeToJson(SkillNode skillNode) {
  return <String, Object?>{
    'id': skillNode.id,
    'title': skillNode.title,
    'category': skillNode.category.name,
    'description': skillNode.description,
    'reviewMilestoneId': skillNode.reviewMilestoneId,
  };
}

SkillNode skillNodeFromJson(Map<String, dynamic> json) {
  return SkillNode(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    category: _skillCategoryFromName(json['category'] as String?),
    description: json['description'] as String? ?? '',
    reviewMilestoneId: json['reviewMilestoneId'] as String? ?? '',
  );
}

Map<String, Object?> skillMasteryRecordToJson(SkillMasteryRecord record) {
  return <String, Object?>{
    'skillId': record.skillId,
    'masteryScore': record.masteryScore,
    'confidenceScore': record.confidenceScore,
    'hintDependence': record.hintDependence,
    'failureCount': record.failureCount,
    'lastOutcome': record.lastOutcome,
  };
}

SkillMasteryRecord skillMasteryRecordFromJson(Map<String, dynamic> json) {
  return SkillMasteryRecord(
    skillId: json['skillId'] as String? ?? '',
    masteryScore: (json['masteryScore'] as num?)?.toDouble() ?? 0.0,
    confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.0,
    hintDependence: (json['hintDependence'] as num?)?.toDouble() ?? 0.0,
    failureCount: json['failureCount'] as int? ?? 0,
    lastOutcome: json['lastOutcome'] as String? ?? '',
  );
}

Map<String, Object?> reviewTaskToJson(ReviewTask task) {
  return <String, Object?>{
    'id': task.id,
    'title': task.title,
    'description': task.description,
    'skillIds': task.skillIds,
    'milestoneId': task.milestoneId,
    'laneLabel': task.laneLabel,
  };
}

ReviewTask reviewTaskFromJson(Map<String, dynamic> json) {
  return ReviewTask(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    skillIds: _readStringList(json['skillIds']),
    milestoneId: json['milestoneId'] as String? ?? '',
    laneLabel: json['laneLabel'] as String? ?? '',
  );
}

Map<String, Object?> dashboardStatsToJson(DashboardStats stats) {
  return <String, Object?>{
    'completedProjects': stats.completedProjects,
    'completedDsAlgo': stats.completedDsAlgo,
    'reviewQueueCount': stats.reviewQueueCount,
    'averageMastery': stats.averageMastery,
  };
}

DashboardStats dashboardStatsFromJson(Map<String, dynamic> json) {
  return DashboardStats(
    completedProjects: json['completedProjects'] as int? ?? 0,
    completedDsAlgo: json['completedDsAlgo'] as int? ?? 0,
    reviewQueueCount: json['reviewQueueCount'] as int? ?? 0,
    averageMastery: (json['averageMastery'] as num?)?.toDouble() ?? 0.0,
  );
}

List<dynamic> _readList(Object? value) {
  if (value is List) {
    return value;
  }
  return const <dynamic>[];
}

List<String> _readStringList(Object? value) {
  return _readList(value).map((item) => item.toString()).toList(growable: false);
}

Map<String, String> _readStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }

  return <String, String>{
    for (final entry in value.entries) entry.key.toString(): entry.value.toString(),
  };
}

List<T> _readObjectList<T>(
  Object? value,
  T Function(Map<String, dynamic>) parser,
) {
  if (value is! List) {
    return <T>[];
  }

  return value
      .whereType<Map>()
      .map((item) => parser(item.cast<String, dynamic>()))
      .toList(growable: false);
}

LearningTrackType _trackTypeFromName(String? name) {
  return LearningTrackType.values.firstWhere(
    (value) => value.name == name,
    orElse: () => LearningTrackType.project,
  );
}

PracticeMode _practiceModeFromName(String? name) {
  return PracticeMode.values.firstWhere(
    (value) => value.name == name,
    orElse: () => PracticeMode.guided,
  );
}

HintLevel? _hintLevelFromName(String? name) {
  for (final value in HintLevel.values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
}

SkillCategory _skillCategoryFromName(String? name) {
  return SkillCategory.values.firstWhere(
    (value) => value.name == name,
    orElse: () => SkillCategory.languageSyntax,
  );
}
