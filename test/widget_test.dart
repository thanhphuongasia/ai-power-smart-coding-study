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
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Exercises'), findsOneWidget);
  });

  testWidgets('session editor accepts code input and can validate it',
      (WidgetTester tester) async {
    final state = await buildTestAppState();
    final exercise = state.exercises.firstWhere(
      (item) => item.id == 'project_document_class',
    );

    state.startSession(
      exercise: exercise,
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

  testWidgets('fullscreen editor stays editable after rotating the screen',
      (WidgetTester tester) async {
    final view = tester.view;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(430, 932);

    final state = await buildTestAppState();
    final exercise = state.exercises.firstWhere(
      (item) => item.id == 'project_document_class',
    );

    state.startSession(
      exercise: exercise,
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

    await tester.tap(find.text('Full screen'));
    await tester.pumpAndSettle();

    const initialCode = 'class Document:\n    pass\n';
    await tester.enterText(find.byType(EditableText).first, initialCode);
    await tester.pumpAndSettle();

    view.physicalSize = const Size(932, 430);
    await tester.pumpAndSettle();

    expect(find.byType(EditableText), findsOneWidget);
    expect(state.activeSession!.code, initialCode);

    const rotatedCode =
        'class Document:\n    pass\n\nprint("rotation still works")\n';
    await tester.tap(find.byType(EditableText).first);
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, rotatedCode);
    await tester.pumpAndSettle();

    expect(state.activeSession!.code, rotatedCode);
    expect(state.activeSession!.code, contains('rotation still works'));
  });
}
