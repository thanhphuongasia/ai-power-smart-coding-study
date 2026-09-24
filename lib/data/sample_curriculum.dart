import '../models/learning_models.dart';

class SeedData {
  static List<LearningTrack> tracks() {
    return <LearningTrack>[
      const LearningTrack(
        id: 'project_document_service',
        title: 'Document Management Service',
        summary:
            'Practice modeling and querying document workflows with reusable exercises.',
        type: LearningTrackType.project,
        contentKind: ContentKind.projectTrack,
        level: LearningLevel.foundation,
        topicIds: <String>['sql'],
        domainIds: <String>['document-management'],
        tags: <String>['list', 'query'],
        skillIds: <String>['python_class_definition', 'sql_list_queries'],
        exerciseRefs: <TrackExerciseRef>[
          TrackExerciseRef(
            exerciseId: 'project_document_class',
            title: 'Create the Document class',
            summary: 'Build the core entity used across the service.',
          ),
          TrackExerciseRef(
            exerciseId: 'project_list_documents',
            title: 'List documents with filters',
            summary: 'Shape the query layer for browse screens.',
          ),
        ],
      ),
      const LearningTrack(
        id: 'dsa_core_patterns',
        title: 'Core DSA Patterns',
        summary: 'Warm up with frequency maps and list traversal.',
        type: LearningTrackType.dataStructure,
        contentKind: ContentKind.dsaTrack,
        level: LearningLevel.foundation,
        topicIds: <String>[],
        domainIds: <String>[],
        tags: <String>['map'],
        skillIds: <String>['hash_map_lookup'],
        exerciseRefs: <TrackExerciseRef>[
          TrackExerciseRef(
            exerciseId: 'dsa_frequency_counter',
            title: 'Build a frequency counter',
          ),
        ],
      ),
      const LearningTrack(
        id: 'leetcode_interval_playbook',
        title: 'LeetCode Interval Playbook',
        summary: 'Train interval sorting and merge reasoning.',
        type: LearningTrackType.leetcode,
        contentKind: ContentKind.leetcodeSet,
        level: LearningLevel.intermediate,
        topicIds: <String>[],
        domainIds: <String>[],
        tags: <String>['interval'],
        skillIds: <String>['interval_sorting_strategy'],
        exerciseRefs: <TrackExerciseRef>[
          TrackExerciseRef(
            exerciseId: 'lc_merge_intervals',
            title: 'Merge overlapping intervals',
          ),
        ],
      ),
    ];
  }

  static List<LearningExercise> exercises() {
    return <LearningExercise>[
      LearningExercise(
        id: 'project_document_class',
        title: 'Create the Document class',
        summary: 'Define a tiny entity and a readable summary method.',
        type: LearningTrackType.project,
        contentKind: ContentKind.projectExercise,
        level: LearningLevel.foundation,
        topicIds: const <String>[],
        domainIds: const <String>['document-management'],
        tags: const <String>['class-design'],
        skillIds: const <String>[
          'python_class_definition',
          'python_instance_fields',
        ],
        problemStatement:
            'Create a class that stores title, owner, and page_count, then returns a readable summary line.',
        acceptanceCriteria: const <String>[
          'The class has an initializer that stores title, owner, and page_count.',
          'The class exposes a summary method.',
          'The summary includes all three values in one string.',
        ],
        taskSteps: const <TaskStep>[
          TaskStep(
            id: 'identify_fields',
            title: 'Identify the entity shape',
            description: 'List the three properties the model must remember.',
          ),
          TaskStep(
            id: 'write_init',
            title: 'Build the initializer',
            description:
                'Store the incoming values on self so the rest of the system can use them.',
          ),
          TaskStep(
            id: 'add_summary',
            title: 'Return a preview string',
            description:
                'Expose a method that returns one formatted summary line.',
          ),
        ],
        supportedModes: const <PracticeMode>[
          PracticeMode.guided,
          PracticeMode.standard,
        ],
        hints: const <HintLevel, String>{
          HintLevel.concept:
              'Think data plus behavior: the class stores metadata and exposes one helper method.',
          HintLevel.structure:
              'You need class Document, __init__, and summary(self).',
          HintLevel.pseudocode:
              'Inside __init__, assign the incoming fields to self. Inside summary, build an f-string.',
          HintLevel.lineHint:
              'Use self.title = title and return an f-string from summary.',
          HintLevel.fullExplain:
              'This exercise checks class syntax, instance fields, and a simple instance method.',
        },
        reflectionPrompts: const <String>[
          'Why is a class better than a plain dict here?',
          'How would you add a document type later without breaking callers?',
        ],
        requirements: const <RequirementCheck>[
          RequirementCheck(
            label: 'Document class exists',
            pattern: r'class\s+Document',
            feedback: 'Define the Document class before adding behavior.',
          ),
          RequirementCheck(
            label: 'Initializer stores title',
            pattern: r'def\s+__init__\s*\([\s\S]*self\.title\s*=\s*title',
            feedback: 'Store title on self inside __init__.',
          ),
          RequirementCheck(
            label: 'Initializer stores owner',
            pattern: r'self\.owner\s*=\s*owner',
            feedback: 'Store owner on self inside __init__.',
          ),
          RequirementCheck(
            label: 'Initializer stores page_count',
            pattern: r'self\.page_count\s*=\s*page_count',
            feedback: 'Store page_count on self inside __init__.',
          ),
          RequirementCheck(
            label: 'Summary method exists',
            pattern: r'def\s+summary\s*\(',
            feedback: 'Add a summary method to format the preview string.',
          ),
        ],
        languageVariants: const <ExerciseLanguageVariant>[
          ExerciseLanguageVariant(
            languageId: 'python',
            languageLabel: 'Python',
            isDefault: true,
            starterCode: '''class Document:
    pass
''',
            starterFiles: <String, String>{
              'main.py': '''from models.document import Document


def main():
    document = Document("Quarterly Report", "Nina", 14)
    print(document.summary())


if __name__ == "__main__":
    main()
''',
            },
            solutionCode: '''class Document:
    def __init__(self, title, owner, page_count):
        self.title = title
        self.owner = owner
        self.page_count = page_count

    def summary(self):
        return f"{self.title} by {self.owner} ({self.page_count} pages)"
''',
            runCommand: 'python main.py',
            entryFilePath: 'models/document.py',
            demoFilePath: 'main.py',
            testCases: <ExecutionTestCase>[
              ExecutionTestCase(
                id: 'document_summary_primary',
                label: 'Formats the sample document summary',
                body:
                    'document = Document("Quarterly Report", "Nina", 14)\nprint(document.summary())',
                expectedOutput: 'Quarterly Report by Nina (14 pages)',
              ),
            ],
          ),
          ExerciseLanguageVariant(
            languageId: 'csharp',
            languageLabel: 'C#',
            isDefault: false,
            starterCode: '''public class Document
{
}
''',
            starterFiles: <String, String>{
              'Program.cs': '''using System;

public static class Program
{
    public static void Main()
    {
        Document document = new Document("Quarterly Report", "Nina", 14);
        Console.WriteLine(document.Summary());
    }
}
''',
            },
            runCommand: 'dotnet-script Program.cs',
            entryFilePath: 'Document.cs',
            demoFilePath: 'Program.cs',
          ),
        ],
      ),
      const LearningExercise(
        id: 'project_list_documents',
        title: 'List documents with filters',
        summary: 'Build a lightweight list query with stable ordering.',
        type: LearningTrackType.project,
        contentKind: ContentKind.projectExercise,
        level: LearningLevel.foundation,
        topicIds: <String>['sql'],
        domainIds: <String>['document-management'],
        tags: <String>['list', 'query'],
        skillIds: <String>['sql_list_queries'],
        problemStatement:
            'Filter archived rows, optionally narrow by owner, and keep deterministic ordering.',
        acceptanceCriteria: <String>[
          'Only active rows are returned.',
          'The optional owner filter narrows the result set.',
          'Rows are ordered by update time descending.',
        ],
        taskSteps: <TaskStep>[],
        supportedModes: <PracticeMode>[PracticeMode.guided],
        hints: <HintLevel, String>{},
        reflectionPrompts: <String>[],
        requirements: <RequirementCheck>[],
        languageVariants: <ExerciseLanguageVariant>[
          ExerciseLanguageVariant(
            languageId: 'python',
            languageLabel: 'Python',
            isDefault: true,
            starterCode: 'def list_active(rows, owner=None):\n    return []\n',
            starterFiles: <String, String>{'main.py': 'print("demo")\n'},
            runCommand: 'python main.py',
            entryFilePath: 'list_documents.py',
            demoFilePath: 'main.py',
          ),
        ],
      ),
      const LearningExercise(
        id: 'dsa_frequency_counter',
        title: 'Build a frequency counter',
        summary: 'Count repeated values with a map.',
        type: LearningTrackType.dataStructure,
        contentKind: ContentKind.dsaExercise,
        level: LearningLevel.foundation,
        topicIds: <String>[],
        domainIds: <String>[],
        tags: <String>['map'],
        skillIds: <String>['hash_map_lookup'],
        problemStatement: 'Return how many times each value appears.',
        acceptanceCriteria: <String>[],
        taskSteps: <TaskStep>[],
        supportedModes: <PracticeMode>[PracticeMode.guided, PracticeMode.timed],
        hints: <HintLevel, String>{},
        reflectionPrompts: <String>[],
        requirements: <RequirementCheck>[],
        languageVariants: <ExerciseLanguageVariant>[
          ExerciseLanguageVariant(
            languageId: 'python',
            languageLabel: 'Python',
            isDefault: true,
            starterCode: 'def build_counts(values):\n    return {}\n',
            starterFiles: <String, String>{
              'main.py': 'print(build_counts([1,2,1]))\n'
            },
            runCommand: 'python main.py',
            entryFilePath: 'frequency_counter.py',
            demoFilePath: 'main.py',
          ),
        ],
      ),
      const LearningExercise(
        id: 'lc_merge_intervals',
        title: 'Merge overlapping intervals',
        summary: 'Sort first, then merge while scanning.',
        type: LearningTrackType.leetcode,
        contentKind: ContentKind.leetcodeExercise,
        level: LearningLevel.intermediate,
        topicIds: <String>[],
        domainIds: <String>[],
        tags: <String>['interval'],
        skillIds: <String>['interval_sorting_strategy'],
        problemStatement: 'Merge all overlapping intervals.',
        acceptanceCriteria: <String>[],
        taskSteps: <TaskStep>[],
        supportedModes: <PracticeMode>[
          PracticeMode.guided,
          PracticeMode.standard,
          PracticeMode.timed,
        ],
        hints: <HintLevel, String>{},
        reflectionPrompts: <String>[],
        requirements: <RequirementCheck>[],
        languageVariants: <ExerciseLanguageVariant>[
          ExerciseLanguageVariant(
            languageId: 'python',
            languageLabel: 'Python',
            isDefault: true,
            starterCode: 'def merge(intervals):\n    return []\n',
            starterFiles: <String, String>{
              'main.py': 'print(merge([[1,3],[2,6]]))\n'
            },
            runCommand: 'python main.py',
            entryFilePath: 'solution.py',
            demoFilePath: 'main.py',
            testCases: <ExecutionTestCase>[
              ExecutionTestCase(
                id: 'merge_intervals_primary',
                label: 'Merges the standard overlap case',
                body: 'print(merge([[1, 3], [2, 6], [8, 10], [15, 18]]))',
                expectedOutput: '[[1, 6], [8, 10], [15, 18]]',
              ),
            ],
          ),
        ],
      ),
    ];
  }

  static List<TopicDefinition> topics() {
    return const <TopicDefinition>[
      TopicDefinition(
        id: 'sql',
        title: 'SQL',
        summary: 'Query shaping and result filtering.',
      ),
    ];
  }

  static List<DomainDefinition> domains() {
    return const <DomainDefinition>[
      DomainDefinition(
        id: 'document-management',
        title: 'Document Management',
        summary: 'Browse and validate document metadata.',
      ),
    ];
  }

  static List<String> tagSuggestions() {
    return const <String>['class-design', 'list', 'map', 'query'];
  }

  static List<SkillNode> skills() {
    return const <SkillNode>[
      SkillNode(
        id: 'python_class_definition',
        title: 'Python class definition',
        category: SkillCategory.languageSyntax,
        description: 'Create a small Python class with clear shape and syntax.',
        reviewExerciseId: 'project_document_class',
      ),
      SkillNode(
        id: 'python_instance_fields',
        title: 'Python instance fields',
        category: SkillCategory.oopClassDesign,
        description: 'Store incoming values on self in the initializer.',
        reviewExerciseId: 'project_document_class',
      ),
      SkillNode(
        id: 'sql_list_queries',
        title: 'List query shaping',
        category: SkillCategory.testingEdgeCases,
        description:
            'Filter, sort, and cap list results without losing determinism.',
        reviewExerciseId: 'project_list_documents',
      ),
      SkillNode(
        id: 'hash_map_lookup',
        title: 'Hash map lookup fluency',
        category: SkillCategory.dataStructureFundamentals,
        description: 'Use maps for complements, counts, and grouping.',
        reviewExerciseId: 'dsa_frequency_counter',
      ),
      SkillNode(
        id: 'interval_sorting_strategy',
        title: 'Interval sorting strategy',
        category: SkillCategory.algorithmPatterns,
        description: 'Sort the right way before merging interval ranges.',
        reviewExerciseId: 'lc_merge_intervals',
      ),
    ];
  }

  static Map<String, SkillMasteryRecord> skillMemory() {
    return <String, SkillMasteryRecord>{
      for (final skill in skills())
        skill.id: SkillMasteryRecord(
          skillId: skill.id,
          masteryScore: 0.5,
          confidenceScore: 0.5,
          hintDependence: 0,
          failureCount: 0,
          lastOutcome: 'Waiting for your first real attempt.',
        ),
    };
  }
}
