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
  test('starts and validates a guided milestone session', () async {
    final state = await buildTestAppState();
    final track = state.tracks.firstWhere(
      (item) => item.type == LearningTrackType.project,
    );
    final module = track.modules.first;
    final milestone = module.milestones.first;

    state.startSession(
      track: track,
      module: module,
      milestone: milestone,
      mode: PracticeMode.guided,
    );

    expect(state.activeSession, isNotNull);
    expect(state.activeSession!.milestone.id, milestone.id);

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
    expect(state.isMilestoneCompleted(milestone.id), isTrue);
    expect(
      state.skillMemory['python_class_definition']!.masteryScore,
      greaterThan(0.58),
    );
  });

  test(
      'typing in the editor updates session code without notifying listeners',
      () async {
    final state = await buildTestAppState();
    final track = state.tracks.firstWhere(
      (item) => item.type == LearningTrackType.project,
    );
    final module = track.modules.first;
    final milestone = module.milestones.first;
    var notifications = 0;

    state.addListener(() {
      notifications += 1;
    });

    state.startSession(
      track: track,
      module: module,
      milestone: milestone,
      mode: PracticeMode.guided,
    );
    notifications = 0;

    state.updateSessionCode('print("hello")');

    expect(state.activeSession!.code, 'print("hello")');
    expect(notifications, 0);
  });

  test('stores separate buffers for separate files in one session', () async {
    final state = await buildTestAppState();
    const milestone = Milestone(
      id: 'multi_file_test',
      title: 'Multi file',
      objective: 'Keep buffers per file.',
      problemStatement: 'Edit different files independently.',
      languageLabel: 'Python',
      relatedFiles: <String>['main.py', 'helpers/util.py'],
      acceptanceCriteria: <String>[],
      taskSteps: <TaskStep>[],
      supportedModes: <PracticeMode>[PracticeMode.guided],
      hints: <HintLevel, String>{},
      starterCode: 'print("main")\n',
      exampleInput: '',
      exampleOutput: '',
      reflectionPrompts: <String>[],
      skillIds: <String>[],
      requirements: <RequirementCheck>[],
    );
    const module = LearningModule(
      id: 'module',
      title: 'Module',
      summary: 'Summary',
      estimatedMinutes: 10,
      milestones: <Milestone>[milestone],
    );
    const track = LearningTrack(
      id: 'track',
      title: 'Track',
      summary: 'Summary',
      type: LearningTrackType.project,
      difficultyLabel: 'Foundation',
      focusAreas: <String>['Python'],
      modules: <LearningModule>[module],
    );

    state.startSession(
      track: track,
      module: module,
      milestone: milestone,
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
          required milestone,
          required fileContents,
          required entryFilePath,
        }) {
          executeCalls += 1;
          return completer.future;
        },
      ),
    );
    final track = state.tracks.firstWhere(
      (item) => item.type == LearningTrackType.project,
    );
    final module = track.modules.first;
    final milestone = module.milestones.first;

    state.startSession(
      track: track,
      module: module,
      milestone: milestone,
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
    required Milestone milestone,
    required Map<String, String> fileContents,
    required String entryFilePath,
  }) onExecute;

  @override
  Future<SandboxExecutionResult> execute({
    required SandboxExecutionAction action,
    required Milestone milestone,
    required Map<String, String> fileContents,
    required String entryFilePath,
  }) {
    return onExecute(
      action: action,
      milestone: milestone,
      fileContents: fileContents,
      entryFilePath: entryFilePath,
    );
  }
}
