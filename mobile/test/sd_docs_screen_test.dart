// Test tab Design chia nhóm theo course (T-04 run sd-courses).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/sd_repository.dart';
import 'package:smart_coding_study/domain/sd_models.dart';
import 'package:smart_coding_study/features/system_design/sd_docs_screen.dart';

const _c1 = SdCourse(id: 'c1', title: 'Khoá một', skills: ['python']);
const _c2 = SdCourse(id: 'c2', title: 'Khoá hai');

SdDocSummary _doc(String id, [SdCourse? c]) => SdDocSummary(
  id: id,
  title: 'Doc $id',
  sections: 2,
  sectionsDone: 0,
  cards: 4,
  cardsRead: 0,
  phase2Unlocked: false,
  tasks: 1,
  tasksDone: 0,
  courseId: c?.id,
  course: c,
);

late GoRouter _router;

Future<void> _pump(WidgetTester tester, List<SdDocSummary> docs) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SdDocsScreen()),
      GoRoute(
        path: '/design/:docId',
        builder: (_, s) =>
            Placeholder(key: Key('reader-${s.pathParameters['docId']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sdDocsProvider.overrideWith((ref) async => docs)],
      child: MaterialApp.router(theme: buildAppTheme(), routerConfig: _router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('có course: header theo thứ tự, "Khác" cuối, doc đúng nhóm', (
    tester,
  ) async {
    await _pump(tester, [
      _doc('a', _c1),
      _doc('b', _c1),
      _doc('c', _c2),
      _doc('z'),
    ]);
    final h1 = tester.getTopLeft(find.byKey(const Key('sd-course-c1'))).dy;
    final h2 = tester.getTopLeft(find.byKey(const Key('sd-course-c2'))).dy;
    final ho = tester.getTopLeft(find.byKey(const Key('sd-course-other'))).dy;
    final ya = tester.getTopLeft(find.byKey(const Key('sd-doc-a'))).dy;
    final yb = tester.getTopLeft(find.byKey(const Key('sd-doc-b'))).dy;
    final yc = tester.getTopLeft(find.byKey(const Key('sd-doc-c'))).dy;
    final yz = tester.getTopLeft(find.byKey(const Key('sd-doc-z'))).dy;
    expect(h1 < ya && ya < yb && yb < h2, isTrue);
    expect(h2 < yc && yc < ho, isTrue);
    expect(ho < yz, isTrue);
    expect(find.text('Khoá một'), findsOneWidget);
    expect(find.text('python'), findsOneWidget);
    expect(find.text('Khác'), findsOneWidget);
  });

  testWidgets('không có doc ngoài course → không hiện nhóm Khác', (
    tester,
  ) async {
    await _pump(tester, [_doc('a', _c1)]);
    expect(find.byKey(const Key('sd-course-c1')), findsOneWidget);
    expect(find.byKey(const Key('sd-course-other')), findsNothing);
  });

  testWidgets('không có course: list phẳng, không header', (tester) async {
    await _pump(tester, [_doc('a'), _doc('b')]);
    expect(find.byKey(const Key('sd-doc-a')), findsOneWidget);
    expect(find.byKey(const Key('sd-doc-b')), findsOneWidget);
    expect(find.byKey(const Key('sd-course-other')), findsNothing);
    expect(find.text('Khác'), findsNothing);
  });

  testWidgets('chạm doc → mở reader', (tester) async {
    await _pump(tester, [_doc('a', _c1)]);
    await tester.tap(find.byKey(const Key('sd-doc-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-a')), findsOneWidget);
  });
}
