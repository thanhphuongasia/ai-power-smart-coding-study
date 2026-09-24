import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_powerd_mobile_code_assitant/app/app_state.dart';
import 'package:ai_powerd_mobile_code_assitant/models/app_sync_models.dart';
import 'package:ai_powerd_mobile_code_assitant/models/learning_models.dart';
import 'package:ai_powerd_mobile_code_assitant/repositories/catalog_repository.dart';
import 'package:ai_powerd_mobile_code_assitant/repositories/learner_repository.dart';
import 'package:ai_powerd_mobile_code_assitant/repositories/sync_repository.dart';
import 'package:ai_powerd_mobile_code_assitant/services/sandbox_api_service.dart';

import 'support/test_bootstrap.dart';

void main() {
  test('starts and validates a guided exercise session', () async {
    final state = await buildTestAppState();
    final track = state.tracks.firstWhere(
      (item) => item.type == LearningTrackType.project,
    );
    final exercise = state.exercises.firstWhere(
      (item) => item.id == 'project_document_class',
    );

    state.startSession(
      track: track,
      exercise: exercise,
      mode: PracticeMode.guided,
    );

    expect(state.activeSession, isNotNull);
    expect(state.activeSession!.exercise.id, exercise.id);

    state.updateSessionCode('''
class Document:
    def __init__(self, title, owner, page_count):
        self.title = title
        self.owner = owner
        self.page_count = page_count

    def summary(self):
        return f"{self.title} by {self.owner} ({self.page_count} pages)"
''');

    final result = state.checkSession();

    expect(result.status, ValidationStatus.passed);
    expect(state.isExerciseCompleted(exercise.id), isTrue);
    expect(
      state.skillMemory['python_class_definition']!.masteryScore,
      greaterThanOrEqualTo(0.58),
    );
  });

  test('typing in the editor updates session code without notifying listeners',
      () async {
    final state = await buildTestAppState();
    final exercise = state.exercises.firstWhere(
      (item) => item.id == 'project_document_class',
    );
    var notifications = 0;

    state.addListener(() {
      notifications += 1;
    });

    state.startSession(
      exercise: exercise,
      mode: PracticeMode.guided,
    );
    notifications = 0;

    state.updateSessionCode('print("hello")');

    expect(state.activeSession!.code, 'print("hello")');
    expect(notifications, 0);
  });

  test('stores separate buffers for separate files in one session', () async {
    final state = await buildTestAppState();
    const exercise = LearningExercise(
      id: 'multi_file_test',
      title: 'Multi file',
      summary: 'Keep buffers per file.',
      type: LearningTrackType.project,
      contentKind: ContentKind.projectExercise,
      level: LearningLevel.foundation,
      topicIds: <String>[],
      domainIds: <String>[],
      tags: <String>[],
      skillIds: <String>[],
      problemStatement: 'Edit different files independently.',
      acceptanceCriteria: <String>[],
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
          starterCode: 'print("main")\n',
          starterFiles: <String, String>{
            'main.py': 'print("main")\n',
            'helpers/util.py': '',
          },
          runCommand: 'python main.py',
          entryFilePath: 'main.py',
        ),
      ],
    );

    state.startSession(
      exercise: exercise,
      mode: PracticeMode.guided,
    );

    expect(state.activeSession!.activeFilePath, 'main.py');
    expect(state.activeSession!.fileContentFor('main.py'), 'print("main")\n');
    expect(state.activeSession!.fileContentFor('helpers/util.py'), '');

    state.selectSessionFile('helpers/util.py');
    state.updateSessionCode('def helper():\n    return True\n');

    expect(
      state.activeSession!.fileContentFor('helpers/util.py'),
      'def helper():\n    return True\n',
    );
    expect(state.activeSession!.fileContentFor('main.py'), 'print("main")\n');
    expect(state.activeSession!.code, 'print("main")\n');
  });

  test('remembers preferred language between multi-language exercises',
      () async {
    final state = await buildTestAppState();
    final exercise = state.exercises.firstWhere(
      (item) => item.id == 'project_document_class',
    );

    state.startSession(
      exercise: exercise,
      languageId: 'csharp',
      mode: PracticeMode.guided,
    );

    expect(state.preferredLanguageId, 'csharp');
    expect(state.activeSession!.selectedVariant.languageId, 'csharp');

    state.closeSession();
    state.startSession(
      exercise: exercise,
      mode: PracticeMode.guided,
    );

    expect(state.activeSession!.selectedVariant.languageId, 'csharp');
  });

  test('deduplicates overlapping sandbox execution requests', () async {
    final completer = Completer<SandboxExecutionResult>();
    var executeCalls = 0;
    final bootstrapState = await buildTestAppState();
    final state = await AppState.bootstrap(
      catalogRepository: MemoryCatalogRepository(
        manifest: ContentManifest(
          contentVersion: 'test-1',
          publishedAt: DateTime.utc(2026, 1, 1),
          checksum: 'test-checksum',
        ),
        tracks: bootstrapState.tracks,
        exercises: bootstrapState.exercises,
        topics: bootstrapState.topics,
        domains: bootstrapState.domains,
        tagSuggestions: bootstrapState.tagSuggestions,
        skillNodes: bootstrapState.skillNodes,
      ),
      learnerRepository: MemoryLearnerRepository(
        learnerProfile: const LearnerProfile(
          installId: 'test-install',
          learnerId: 'test-learner',
          accessToken: '',
          syncCursor: 0,
          isOfflineOnly: true,
        ),
      ),
      syncRepository: MemorySyncRepository(),
      sandboxApiService: _FakeSandboxApiService(
        onExecute: ({
          required action,
          required exercise,
          required variant,
          required fileContents,
          required entryFilePath,
          runWithoutTests = false,
        }) {
          executeCalls += 1;
          return completer.future;
        },
      ),
    );
    final exercise = state.exercises.firstWhere(
      (item) => item.id == 'project_document_class',
    );

    state.startSession(
      exercise: exercise,
      mode: PracticeMode.guided,
    );

    final first = state.buildSession();
    final second = state.runSession();

    expect(executeCalls, 1);
    expect(identical(first, second), isTrue);
    expect(state.isSandboxExecutionRunning, isTrue);
    expect(
      state.activeSession!.validationResult.status,
      ValidationStatus.running,
    );

    completer.complete(
      const SandboxExecutionResult(
        success: true,
        summary: 'OK',
        output: 'done',
        report: null,
      ),
    );

    await first;

    expect(state.isSandboxExecutionRunning, isFalse);

    await state.runSession();

    expect(executeCalls, 2);
  });
}

class _FakeSandboxApiService extends SandboxApiService {
  _FakeSandboxApiService({
    required this.onExecute,
  }) : super(
          settings: const SandboxApiSettings(baseUrl: 'http://127.0.0.1:8787'),
        );

  final Future<SandboxExecutionResult> Function({
    required SandboxExecutionAction action,
    required LearningExercise exercise,
    required ExerciseLanguageVariant variant,
    required Map<String, String> fileContents,
    required String entryFilePath,
    bool runWithoutTests,
  }) onExecute;

  @override
  Future<SandboxExecutionResult> execute({
    required SandboxExecutionAction action,
    required LearningExercise exercise,
    required ExerciseLanguageVariant variant,
    required Map<String, String> fileContents,
    required String entryFilePath,
    bool runWithoutTests = false,
  }) {
    return onExecute(
      action: action,
      exercise: exercise,
      variant: variant,
      fileContents: fileContents,
      entryFilePath: entryFilePath,
      runWithoutTests: runWithoutTests,
    );
  }
}
