import 'learning_models.dart';

Map<String, Object?> learningTrackToJson(LearningTrack track) {
  return <String, Object?>{
    'id': track.id,
    'title': track.title,
    'summary': track.summary,
    'lane': track.type.wireValue,
    'contentKind': _contentKindName(track.contentKind),
    'level': track.level.name,
    'topicIds': track.topicIds,
    'domainIds': track.domainIds,
    'tags': track.tags,
    'skillIds': track.skillIds,
    'exerciseRefs':
        track.exerciseRefs.map(trackExerciseRefToJson).toList(growable: false),
  };
}

LearningTrack learningTrackFromJson(Map<String, dynamic> json) {
  return LearningTrack(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    type: _trackTypeFromLane(json['lane'] ?? json['type']),
    contentKind: _contentKindFromName(json['contentKind'] as String?),
    level: _learningLevelFromName(json['level'] as String?),
    topicIds: _readStringList(json['topicIds']),
    domainIds: _readStringList(json['domainIds']),
    tags: _readStringList(json['tags']),
    skillIds: _readStringList(json['skillIds']),
    exerciseRefs:
        _readObjectList(json['exerciseRefs'], trackExerciseRefFromJson),
  );
}

Map<String, Object?> trackExerciseRefToJson(TrackExerciseRef ref) {
  return <String, Object?>{
    'exerciseId': ref.exerciseId,
    'title': ref.title,
    'summary': ref.summary,
    'milestoneLabel': ref.milestoneLabel,
  };
}

TrackExerciseRef trackExerciseRefFromJson(Map<String, dynamic> json) {
  return TrackExerciseRef(
    exerciseId: json['exerciseId'] as String? ?? '',
    title: json['title'] as String?,
    summary: json['summary'] as String?,
    milestoneLabel: json['milestoneLabel'] as String?,
  );
}

Map<String, Object?> learningExerciseToJson(LearningExercise exercise) {
  return <String, Object?>{
    'id': exercise.id,
    'title': exercise.title,
    'summary': exercise.summary,
    'lane': exercise.type.wireValue,
    'contentKind': _contentKindName(exercise.contentKind),
    'level': exercise.level.name,
    'topicIds': exercise.topicIds,
    'domainIds': exercise.domainIds,
    'tags': exercise.tags,
    'skillIds': exercise.skillIds,
    'problemStatement': exercise.problemStatement,
    'acceptanceCriteria': exercise.acceptanceCriteria,
    'taskSteps': exercise.taskSteps.map(taskStepToJson).toList(growable: false),
    'supportedModes': exercise.supportedModes
        .map((mode) => mode.name)
        .toList(growable: false),
    'hints': <String, String>{
      for (final entry in exercise.hints.entries) entry.key.name: entry.value,
    },
    'reflectionPrompts': exercise.reflectionPrompts,
    'requirements': exercise.requirements
        .map(requirementCheckToJson)
        .toList(growable: false),
    'languageVariants': exercise.languageVariants
        .map(exerciseLanguageVariantToJson)
        .toList(growable: false),
  };
}

LearningExercise learningExerciseFromJson(Map<String, dynamic> json) {
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

  return LearningExercise(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    type: _trackTypeFromLane(json['lane'] ?? json['type']),
    contentKind: _contentKindFromName(json['contentKind'] as String?),
    level: _learningLevelFromName(json['level'] as String?),
    topicIds: _readStringList(json['topicIds']),
    domainIds: _readStringList(json['domainIds']),
    tags: _readStringList(json['tags']),
    skillIds: _readStringList(json['skillIds']),
    problemStatement: json['problemStatement'] as String? ?? '',
    acceptanceCriteria: _readStringList(json['acceptanceCriteria']),
    taskSteps: _readObjectList(json['taskSteps'], taskStepFromJson),
    supportedModes: _readList(json['supportedModes'])
        .map((item) => _practiceModeFromName(item as String?))
        .toList(growable: false),
    hints: hints,
    reflectionPrompts: _readStringList(json['reflectionPrompts']),
    requirements:
        _readObjectList(json['requirements'], requirementCheckFromJson),
    languageVariants: _readObjectList(
      json['languageVariants'],
      exerciseLanguageVariantFromJson,
    ),
  );
}

Map<String, Object?> exerciseLanguageVariantToJson(
  ExerciseLanguageVariant variant,
) {
  return <String, Object?>{
    'languageId': variant.languageId,
    'languageLabel': variant.languageLabel,
    'isDefault': variant.isDefault,
    'starterCode': variant.starterCode,
    'starterFiles': variant.starterFiles,
    'solutionCode': variant.solutionCode,
    'sandboxHarnessTemplate': variant.sandboxHarnessTemplate,
    'runCommand': variant.runCommand,
    'entryFilePath': variant.entryFilePath,
    'demoFilePath': variant.demoFilePath,
    'testCases':
        variant.testCases.map(executionTestCaseToJson).toList(growable: false),
  };
}

ExerciseLanguageVariant exerciseLanguageVariantFromJson(
  Map<String, dynamic> json,
) {
  return ExerciseLanguageVariant(
    languageId: json['languageId'] as String? ?? '',
    languageLabel: json['languageLabel'] as String? ?? '',
    isDefault: json['isDefault'] == true,
    starterCode: json['starterCode'] as String? ?? '',
    starterFiles: _readStringMap(json['starterFiles']),
    solutionCode: json['solutionCode'] as String?,
    sandboxHarnessTemplate: json['sandboxHarnessTemplate'] as String? ??
        ExerciseLanguageVariant.defaultSandboxHarnessTemplate,
    runCommand: json['runCommand'] as String? ?? '',
    entryFilePath: json['entryFilePath'] as String? ?? 'main.py',
    demoFilePath: json['demoFilePath'] as String?,
    testCases: _readObjectList(json['testCases'], executionTestCaseFromJson),
  );
}

Map<String, Object?> topicDefinitionToJson(TopicDefinition topic) {
  return <String, Object?>{
    'id': topic.id,
    'title': topic.title,
    'summary': topic.summary,
  };
}

TopicDefinition topicDefinitionFromJson(Map<String, dynamic> json) {
  return TopicDefinition(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
  );
}

Map<String, Object?> domainDefinitionToJson(DomainDefinition domain) {
  return <String, Object?>{
    'id': domain.id,
    'title': domain.title,
    'summary': domain.summary,
  };
}

DomainDefinition domainDefinitionFromJson(Map<String, dynamic> json) {
  return DomainDefinition(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
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
    'reviewExerciseId': skillNode.reviewExerciseId,
  };
}

SkillNode skillNodeFromJson(Map<String, dynamic> json) {
  return SkillNode(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    category: _skillCategoryFromName(json['category'] as String?),
    description: json['description'] as String? ?? '',
    reviewExerciseId: json['reviewExerciseId'] as String? ??
        json['reviewMilestoneId'] as String? ??
        '',
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
    'exerciseId': task.exerciseId,
    'laneLabel': task.laneLabel,
  };
}

ReviewTask reviewTaskFromJson(Map<String, dynamic> json) {
  return ReviewTask(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    skillIds: _readStringList(json['skillIds']),
    exerciseId:
        json['exerciseId'] as String? ?? json['milestoneId'] as String? ?? '',
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
  return _readList(value)
      .map((item) => item.toString())
      .toList(growable: false);
}

Map<String, String> _readStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }

  return <String, String>{
    for (final entry in value.entries)
      entry.key.toString(): entry.value.toString(),
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

LearningTrackType _trackTypeFromLane(Object? value) {
  final name = value?.toString().toLowerCase();
  switch (name) {
    case 'dsa':
    case 'datastructure':
      return LearningTrackType.dataStructure;
    case 'leetcode':
      return LearningTrackType.leetcode;
    default:
      return LearningTrackType.project;
  }
}

LearningLevel _learningLevelFromName(String? name) {
  return LearningLevel.values.firstWhere(
    (value) => value.name == name,
    orElse: () => LearningLevel.foundation,
  );
}

ContentKind _contentKindFromName(String? name) {
  switch (name) {
    case 'project_track':
      return ContentKind.projectTrack;
    case 'project_exercise':
      return ContentKind.projectExercise;
    case 'dsa_track':
      return ContentKind.dsaTrack;
    case 'dsa_exercise':
      return ContentKind.dsaExercise;
    case 'leetcode_set':
      return ContentKind.leetcodeSet;
    case 'leetcode_exercise':
      return ContentKind.leetcodeExercise;
    default:
      return ContentKind.projectExercise;
  }
}

String _contentKindName(ContentKind value) {
  switch (value) {
    case ContentKind.projectTrack:
      return 'project_track';
    case ContentKind.projectExercise:
      return 'project_exercise';
    case ContentKind.dsaTrack:
      return 'dsa_track';
    case ContentKind.dsaExercise:
      return 'dsa_exercise';
    case ContentKind.leetcodeSet:
      return 'leetcode_set';
    case ContentKind.leetcodeExercise:
      return 'leetcode_exercise';
  }
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
