import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/domain/class_scope.dart';
import 'package:smart_coding_study/domain/models.dart';
import 'package:smart_coding_study/features/exercise/challenge_tab.dart';
import 'package:smart_coding_study/features/exercise/class_diagram.dart';

import 'support/content_fixture.dart';

DiagramAttribute _a(String n, String t, String g) =>
    DiagramAttribute(name: n, type: t, group: g);

final _diagram = ClassDiagram(
  classes: [
    DiagramClass(
      name: 'Flight',
      file: 'flight.py',
      attributes: [
        _a('code', 'str', 'core'),
        _a('origin', 'str', 'core'),
        _a('dest', 'str', 'core'),
        _a('capacity', 'int', 'core'),
        _a('booked', 'int', 'support'),
        _a('status', 'str', 'support'),
      ],
      methods: ['__init__', 'seats_left', 'is_full'],
    ),
    DiagramClass(
      name: 'FlightService',
      file: 'service.py',
      attributes: [_a('flights', 'list', 'core')],
      methods: ['add_flight', 'remove_flight', 'search'],
    ),
  ],
  relations: const [
    DiagramRelation(
      from: 'FlightService',
      to: 'Flight',
      kind: 'aggregation',
      label: 'quản lý',
      via: ['add_flight', 'search'],
    ),
    DiagramRelation(
      from: 'Flight',
      to: 'Schedule',
      kind: 'association',
      label: 'theo lịch',
      via: ['seats_left'],
    ),
  ],
);

Future<void> _pumpView(WidgetTester t) async {
  t.view.physicalSize = const Size(375, 667);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness: Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClassDiagramView(
            diagram: _diagram,
            scope: const ClassScope(
              className: 'Flight',
              method: 'seats_left',
              attributes: {'capacity', 'booked'},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpTab(WidgetTester t, String id) async {
  t.view.physicalSize = const Size(375, 667);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [...contentOverrides],
      child: MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: Scaffold(
          body: DefaultTabController(
            length: 3,
            child: ChallengeTab(exercise: testContent.exerciseById(id)),
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('tô sáng đúng method và attribute trong phạm vi', (t) async {
    await _pumpView(t);
    expect(find.byKey(const Key('diagram-class-Flight')), findsOneWidget);
    expect(
      find.byKey(const Key('diagram-hl-Flight-seats_left')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('diagram-hl-Flight-capacity')), findsOneWidget);
    expect(find.byKey(const Key('diagram-hl-Flight-booked')), findsOneWidget);
    expect(find.byKey(const Key('diagram-hl-Flight-code')), findsNothing);
    expect(find.byKey(const Key('diagram-hl-Flight-is_full')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('quan hệ: from hiện via, to chỉ hiện tên lớp', (t) async {
    await _pumpView(t);
    expect(
      find.byKey(const Key('diagram-rel-FlightService-Flight')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('diagram-via-FlightService-add_flight')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('diagram-via-FlightService-search')),
      findsOneWidget,
    );
    expect(find.text('remove_flight()'), findsNothing);

    expect(
      find.byKey(const Key('diagram-rel-Flight-Schedule')),
      findsOneWidget,
    );
    expect(find.text('class Schedule'), findsOneWidget);
    expect(
      find.byKey(const Key('diagram-via-Schedule-seats_left')),
      findsNothing,
    );
  });

  testWidgets('bài hàm tự do: không có mục SƠ ĐỒ CLASS', (t) async {
    await _pumpTab(t, 'split-chunks');
    expect(find.text('ĐỀ BÀI'), findsOneWidget);
    expect(find.text('SƠ ĐỒ CLASS'), findsNothing);
  });

  testWidgets('bài method: có sơ đồ, không overflow ở 375x667', (t) async {
    await _pumpTab(t, 'flight-init');
    await t.scrollUntilVisible(
      find.text('SƠ ĐỒ CLASS'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('challenge-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('SƠ ĐỒ CLASS'), findsOneWidget);
    expect(find.byKey(const Key('diagram-class-Flight')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
