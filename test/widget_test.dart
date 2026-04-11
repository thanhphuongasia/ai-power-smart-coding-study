import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_powerd_mobile_code_assitant/app/app.dart';
import 'package:ai_powerd_mobile_code_assitant/models/learning_models.dart';
import 'package:ai_powerd_mobile_code_assitant/screens/practice_session_screen.dart';

import 'support/test_bootstrap.dart';

void main() {
  testWidgets('renders the mobile coding coach dashboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      AICodingCoachApp(
        appStateLoader: buildTestAppState,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pocket Coding Coach'), findsOneWidget);
    expect(find.text('Practice library'), findsNothing);
    expect(find.text('Projects'), findsWidgets);
    expect(find.text('Review queue'), findsNothing);
  });

  testWidgets('can open a project session from the practice library',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      AICodingCoachApp(
        appStateLoader: buildTestAppState,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();

    expect(find.text('Practice library'), findsOneWidget);
    expect(find.text('Document Management Service'), findsOneWidget);
  });

  testWidgets('session editor accepts code input and can validate it',
      (WidgetTester tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: PracticeSessionScreen(
              appState: state,
              onBackToCatalog: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const solution = '''
class Document:
    def __init__(self, title, owner, page_count):
        self.title = title
        self.owner = owner
        self.page_count = page_count

    def summary(self):
        return f"{self.title} by {self.owner} ({self.page_count} pages)"
''';

    expect(find.byIcon(Icons.account_tree_rounded), findsOneWidget);
    expect(find.text('Full screen'), findsOneWidget);

    await tester.tap(find.text('Full screen'));
    await tester.pumpAndSettle();

    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Run'), findsWidgets);

    await tester.enterText(find.byType(EditableText), solution);
    await tester.pumpAndSettle();

    expect(find.textContaining('def __init__'), findsOneWidget);
    expect(state.activeSession!.code, solution);
  });
}
