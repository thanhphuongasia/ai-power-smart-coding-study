// Test màn danh sách tài liệu System Design + lộ trình Duolingo (T-08).
// Phần (a)-(f) dùng GoRouter nhỏ với Placeholder; (g) dùng router THẬT của app.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/sd_repository.dart';
import 'package:smart_coding_study/domain/sd_models.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/system_design/sd_docs_screen.dart';
import 'package:smart_coding_study/features/system_design/sd_path_screen.dart';
import 'package:smart_coding_study/main.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

SdCard _card(String id) =>
    SdCard(id: id, kind: 'text', title: id, body: 'nội dung $id');

SdSection _section(
  String id, {
  required int pos,
  required String chapter,
  required int chapterPos,
  bool done = false,
  bool unlocked = true,
  int read = 0,
}) => SdSection(
  id: id,
  position: pos,
  chapter: chapter,
  chapterPosition: chapterPos,
  title: 'Section $id',
  cards: [_card('$id-c1'), _card('$id-c2')],
  read: {for (var i = 1; i <= read; i++) '$id-c$i'},
  done: done,
  unlocked: unlocked,
);

SdTask _task(String id, int pos, {bool done = false, bool unlocked = false}) =>
    SdTask(
      id: id,
      position: pos,
      name: 'Task $id',
      unlocked: unlocked,
      done: done,
      attempts: 0,
      hints: const [],
    );

SdDoc _doc({
  List<SdSection>? sections,
  bool phase2 = false,
  List<SdTask>? tasks,
}) => SdDoc(
  id: 'sd1',
  title: 'Thiết kế URL shortener',
  sections:
      sections ??
      [
        _section(
          's1',
          pos: 1,
          chapter: 'Nền tảng',
          chapterPos: 1,
          done: true,
          read: 2,
        ),
        _section('s2', pos: 2, chapter: 'Nền tảng', chapterPos: 1, read: 1),
        _section(
          's3',
          pos: 3,
          chapter: 'Mở rộng',
          chapterPos: 2,
          unlocked: false,
        ),
      ],
  phase2Unlocked: phase2,
  context: [_card('ctx')],
  tasks: tasks ?? [_task('t1', 1), _task('t2', 2), _task('t3', 3)],
);

const _summary = SdDocSummary(
  id: 'sd1',
  title: 'Thiết kế URL shortener',
  sections: 3,
  sectionsDone: 1,
  cards: 6,
  cardsRead: 3,
  phase2Unlocked: false,
  tasks: 3,
  tasksDone: 0,
);

/// Dữ liệu "server" giả: test đổi biến rồi invalidate để mô phỏng tải lại.
class _Server {
  Object? docs = const [_summary];
  Object? doc;
  int docsCalls = 0;
  int docCalls = 0;

  List<Override> get overrides => [
    sdDocsProvider.overrideWith((ref) async {
      docsCalls++;
      final d = docs;
      if (d is Exception) throw d;
      return d as List<SdDocSummary>;
    }),
    sdDocProvider.overrideWith((ref, id) async {
      docCalls++;
      final d = doc;
      if (d is Exception) throw d;
      return d as SdDoc;
    }),
  ];
}

GoRouter _testRouter({String initial = '/design'}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/design', builder: (_, _) => const SdDocsScreen()),
    GoRoute(
      path: '/design/:docId',
      builder: (_, s) => SdPathScreen(docId: s.pathParameters['docId']!),
    ),
    GoRoute(
      path: '/design/:docId/read',
      builder: (_, s) => Placeholder(
        key: Key('page-read-${s.uri.queryParameters['section']}'),
      ),
    ),
    GoRoute(
      path: '/design/:docId/context',
      builder: (_, s) => Placeholder(key: const Key('page-context')),
    ),
    GoRoute(
      path: '/design/:docId/tasks/:taskId',
      builder: (_, s) => Placeholder(key: const Key('page-task')),
    ),
  ],
);

late GoRouter _router;

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  String initial = '/design',
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _router = _testRouter(initial: initial);
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null, // lỗi hiện ngay, không chờ thử lại ngầm
      overrides: server.overrides,
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _router,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

String _loc() =>
    _router.routerDelegate.currentConfiguration.last.matchedLocation;

Finder _node(String id) => find.byKey(Key('duo-node-$id'));

Future<void> _tapNode(WidgetTester tester, String id) async {
  await tester.ensureVisible(_node(id));
  await tester.tap(_node(id));
  await tester.pumpAndSettle();
}

void main() {
  group('SdDocsScreen', () {
    testWidgets('hiện tên, tiến độ, không có chip khi phase 2 chưa mở', (
      tester,
    ) async {
      await _pump(tester, _Server());
      expect(find.text('System Design'), findsOneWidget);
      expect(find.text('Thiết kế URL shortener'), findsOneWidget);
      expect(find.text('1/3 section · 3/6 card'), findsOneWidget);
      expect(find.text('Thực chiến mở'), findsNothing);
    });

    testWidgets('phase2Unlocked → chip "Thực chiến mở"', (tester) async {
      final s = _Server()
        ..docs = [
          const SdDocSummary(
            id: 'sd1',
            title: 'A',
            sections: 2,
            sectionsDone: 2,
            cards: 4,
            cardsRead: 4,
            phase2Unlocked: true,
            tasks: 6,
            tasksDone: 0,
          ),
        ];
      await _pump(tester, s);
      expect(find.text('Thực chiến mở'), findsOneWidget);
    });

    testWidgets('rỗng: thông điệp + dòng phụ', (tester) async {
      await _pump(tester, _Server()..docs = <SdDocSummary>[]);
      expect(find.text('Chưa có tài liệu nào'), findsOneWidget);
      expect(find.text('Admin nhập file .md để bắt đầu'), findsOneWidget);
    });

    testWidgets('lỗi → thông điệp + Thử lại gọi lại API và hiện dữ liệu', (
      tester,
    ) async {
      final s = _Server()..docs = const SdApiException(500, null);
      await _pump(tester, s);
      expect(find.text('Không tải được (mã 500)'), findsOneWidget);
      expect(s.docsCalls, 1);

      s.docs = const [_summary];
      await tester.tap(find.byKey(const Key('sd-retry')));
      await tester.pumpAndSettle();
      expect(s.docsCalls, 2);
      expect(find.text('Thiết kế URL shortener'), findsOneWidget);
    });

    testWidgets('401 → "Cần đăng nhập"', (tester) async {
      await _pump(tester, _Server()..docs = const SdApiException(401, null));
      expect(find.text('Cần đăng nhập'), findsOneWidget);
    });

    testWidgets('nút refresh ở header gọi lại API (issue #48)', (tester) async {
      final s = _Server();
      await _pump(tester, s);
      expect(s.docsCalls, 1);

      await tester.tap(find.byKey(const Key('refresh-button')));
      await tester.pumpAndSettle();
      expect(s.docsCalls, greaterThan(1));
      expect(
        find.text('Thiết kế URL shortener'),
        findsOneWidget,
      ); // vẫn thấy danh sách
    });

    testWidgets('chạm thẻ push /design/<id>; quay lại thì tải lại', (
      tester,
    ) async {
      final s = _Server()..doc = _doc();
      await _pump(tester, s);
      await tester.tap(find.byKey(const Key('sd-doc-sd1')));
      await tester.pumpAndSettle();
      expect(_loc(), '/design/sd1');
      expect(find.byType(SdPathScreen), findsOneWidget);

      final before = s.docsCalls;
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(_loc(), '/design');
      expect(s.docsCalls, greaterThan(before)); // sdDocsProvider đã invalidate
    });
  });

  group('SdPathScreen', () {
    testWidgets('Phase 1: banner chapter đúng chữ, đúng MỘT bóng BẮT ĐẦU ở '
        'section open đầu tiên; phase 2 khoá', (tester) async {
      await _pump(tester, _Server()..doc = _doc(), initial: '/design/sd1');
      expect(find.text('Thiết kế URL shortener'), findsOneWidget); // header
      expect(find.text('CHAPTER 1 · 1/2 SECTION'), findsOneWidget);
      expect(find.text('Nền tảng'), findsOneWidget);
      expect(find.text('CHAPTER 2 · 0/1 SECTION'), findsOneWidget);
      expect(find.text('Mở rộng'), findsOneWidget);
      expect(find.text('PHASE 2 · THỰC CHIẾN · 0/3 TASK'), findsOneWidget);
      expect(find.text('Thiết kế thật'), findsOneWidget);
      expect(find.text('1/2 card'), findsOneWidget); // s2 đã đọc 1/2
      expect(find.byKey(const Key('duo-start-bubble')), findsOneWidget);

      // Bóng nằm ngay trên s2 (open đầu tiên), không phải s1 (done).
      final bubbleBottom = tester
          .getBottomLeft(find.byKey(const Key('duo-start-bubble')))
          .dy;
      expect(
        bubbleBottom,
        lessThanOrEqualTo(tester.getTopLeft(_node('s2')).dy),
      );
      expect(tester.getTopLeft(_node('s2')).dy - bubbleBottom, lessThan(30));
    });

    testWidgets('F7a: hai node open → toàn màn đúng MỘT bóng BẮT ĐẦU, ở node '
        'đầu tiên', (tester) async {
      await _pump(
        tester,
        _Server()
          ..doc = _doc(
            sections: [
              _section('s1', pos: 1, chapter: 'A', chapterPos: 1),
              _section('s2', pos: 2, chapter: 'A', chapterPos: 1),
              // Chapter khác = DuoPath khác: chỉ bước nâng current duy nhất
              // của màn (không phải DuoPath) mới giữ được "một bóng".
              _section('s3', pos: 3, chapter: 'B', chapterPos: 2),
            ],
          ),
        initial: '/design/sd1',
      );
      final bubble = find.byKey(const Key('duo-start-bubble'));
      expect(bubble, findsOneWidget);
      final bottom = tester.getBottomLeft(bubble).dy;
      expect(
        tester.getTopLeft(_node('s1')).dy - bottom,
        inInclusiveRange(0, 30),
      );
      expect(tester.getTopLeft(_node('s2')).dy, greaterThan(bottom + 60));
    });

    testWidgets('F2: tài liệu dài, node current ở chương cuối → cuộn tới và '
        'nằm trong viewport', (tester) async {
      final secs = [
        for (var c = 1; c <= 12; c++)
          for (var j = 1; j <= 4; j++)
            _section(
              's$c-$j',
              pos: (c - 1) * 4 + j,
              chapter: 'Chương $c',
              chapterPos: c,
              done: !(c == 12 && j == 4),
              unlocked: true,
              read: 2,
            ),
      ];
      await _pump(
        tester,
        _Server()..doc = _doc(sections: secs),
        initial: '/design/sd1',
        height: 800,
      );
      final node = _node('s12-4');
      expect(node, findsOneWidget);
      final r = tester.getRect(node);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(800));
      expect(find.byKey(const Key('duo-start-bubble')), findsOneWidget);
    });

    testWidgets('F6: docId có ký tự đặc biệt được mã hoá ở mọi route con', (
      tester,
    ) async {
      const id = 'a b/c';
      final s = _Server()
        ..docs = [
          const SdDocSummary(
            id: id,
            title: 'Lạ',
            sections: 1,
            sectionsDone: 0,
            cards: 2,
            cardsRead: 0,
            phase2Unlocked: true,
            tasks: 1,
            tasksDone: 0,
          ),
        ]
        ..doc = _doc(
          phase2: true,
          sections: [
            _section(
              's 1',
              pos: 1,
              chapter: 'A',
              chapterPos: 1,
              done: true,
              read: 2,
            ),
          ],
          tasks: [_task('t/1', 1, unlocked: true)],
        );
      await _pump(tester, s);
      String uri() => _loc();
      final enc = Uri.encodeComponent(id);
      await tester.tap(find.byKey(const Key('sd-doc-a b/c')));
      await tester.pumpAndSettle();
      expect(uri(), '/design/$enc');

      await _tapNode(tester, 'context');
      expect(uri(), '/design/$enc/context');
      _router.pop();
      await tester.pumpAndSettle();

      await _tapNode(tester, 't/1');
      expect(uri(), '/design/$enc/tasks/${Uri.encodeComponent('t/1')}');
      _router.pop();
      await tester.pumpAndSettle();

      await _tapNode(tester, 's 1');
      expect(uri(), '/design/$enc/read');
      expect(find.byKey(const Key('page-read-s 1')), findsOneWidget);
    });

    testWidgets('chạm node locked: SnackBar, KHÔNG đổi location', (
      tester,
    ) async {
      await _pump(tester, _Server()..doc = _doc(), initial: '/design/sd1');
      await _tapNode(tester, 's3');
      expect(find.text('Hoàn thành section trước để mở khoá'), findsOneWidget);
      expect(_loc(), '/design/sd1');

      await _tapNode(tester, 'context');
      expect(find.text('Đọc xong Phase 1 để mở Thực chiến'), findsOneWidget);
      expect(_loc(), '/design/sd1');

      await _tapNode(tester, 't1');
      expect(find.text('Đọc xong Phase 1 để mở Thực chiến'), findsOneWidget);
      expect(_loc(), '/design/sd1');
    });

    testWidgets('chạm section open push đúng /read?section=<id>; quay lại '
        'tải lại doc', (tester) async {
      final s = _Server()..doc = _doc();
      await _pump(tester, s, initial: '/design/sd1');
      final before = s.docCalls;
      await _tapNode(tester, 's2');
      expect(_loc(), '/design/sd1/read');
      expect(find.byKey(const Key('page-read-s2')), findsOneWidget);

      _router.pop();
      await tester.pumpAndSettle();
      expect(_loc(), '/design/sd1');
      expect(s.docCalls, greaterThan(before));
    });

    testWidgets('xong hết Phase 1: bóng sang "Bối cảnh", mọi task open; '
        'chạm task push /tasks/<id>', (tester) async {
      final s = _Server()
        ..doc = _doc(
          phase2: true,
          sections: [
            _section(
              's1',
              pos: 1,
              chapter: 'Nền tảng',
              chapterPos: 1,
              done: true,
              read: 2,
            ),
            _section(
              's2',
              pos: 2,
              chapter: 'Nền tảng',
              chapterPos: 1,
              done: true,
              read: 2,
            ),
          ],
          tasks: [
            _task('t1', 1, unlocked: true),
            _task('t2', 2, unlocked: true),
            _task('t3', 3, unlocked: true),
          ],
        );
      await _pump(tester, s, initial: '/design/sd1');
      expect(find.text('CHAPTER 1 · 2/2 SECTION'), findsOneWidget);
      expect(find.byKey(const Key('duo-start-bubble')), findsOneWidget);
      expect(
        tester.getTopLeft(_node('context')).dy -
            tester.getBottomLeft(find.byKey(const Key('duo-start-bubble'))).dy,
        inInclusiveRange(0, 30),
      );

      await _tapNode(tester, 't1');
      expect(_loc(), '/design/sd1/tasks/t1');
      expect(find.byKey(const Key('page-task')), findsOneWidget);

      _router.pop();
      await tester.pumpAndSettle();
      await _tapNode(tester, 'context');
      expect(_loc(), '/design/sd1/context');
    });

    testWidgets('task đã xong → "Bối cảnh" done, bóng sang task open đầu', (
      tester,
    ) async {
      final s = _Server()
        ..doc = _doc(
          phase2: true,
          sections: [
            _section(
              's1',
              pos: 1,
              chapter: 'A',
              chapterPos: 1,
              done: true,
              read: 2,
            ),
          ],
          tasks: [
            _task('t1', 1, done: true, unlocked: true),
            _task('t2', 2, unlocked: true),
            _task('t3', 3, unlocked: true),
          ],
        );
      await _pump(tester, s, initial: '/design/sd1');
      expect(find.text('PHASE 2 · THỰC CHIẾN · 1/3 TASK'), findsOneWidget);
      expect(find.byKey(const Key('duo-start-bubble')), findsOneWidget);
      expect(
        tester.getTopLeft(_node('t2')).dy -
            tester.getBottomLeft(find.byKey(const Key('duo-start-bubble'))).dy,
        inInclusiveRange(0, 30),
      );
    });

    // --- Hotfix #35: Phase 2 mở thì MỌI task mở, không khoá tuần tự ---

    SdDoc phase2Doc({bool unlocked = true, List<SdTask>? tasks}) => _doc(
      phase2: unlocked,
      sections: [
        _section(
          's1',
          pos: 1,
          chapter: 'A',
          chapterPos: 1,
          done: true,
          read: 2,
        ),
      ],
      tasks:
          tasks ??
          [
            _task('t1', 1, unlocked: unlocked),
            _task('t2', 2, unlocked: unlocked),
            _task('t3', 3, unlocked: unlocked),
          ],
    );
    final lockIcon = find.byIcon(Icons.lock_rounded);

    testWidgets('Phase 2 mở, mọi task unlocked: không đĩa khoá, đúng một '
        'bóng BẮT ĐẦU', (tester) async {
      await _pump(tester, _Server()..doc = phase2Doc(), initial: '/design/sd1');
      for (final id in ['context', 't1', 't2', 't3']) {
        await tester.ensureVisible(_node(id));
        expect(
          find.descendant(of: _node(id), matching: lockIcon),
          findsNothing,
          reason: 'node $id không được khoá',
        );
      }
      expect(lockIcon, findsNothing);
      expect(find.byKey(const Key('duo-start-bubble')), findsOneWidget);
      // Bối cảnh là node mở chưa xong đầu tiên → bóng ở đó.
      expect(
        tester.getTopLeft(_node('context')).dy -
            tester.getBottomLeft(find.byKey(const Key('duo-start-bubble'))).dy,
        inInclusiveRange(0, 30),
      );
    });

    testWidgets('chạm task thứ 3 khi task 1, 2 chưa làm → mở đúng task 3', (
      tester,
    ) async {
      await _pump(tester, _Server()..doc = phase2Doc(), initial: '/design/sd1');
      await _tapNode(tester, 't3');
      expect(_loc(), '/design/sd1/tasks/t3');
      expect(find.byKey(const Key('page-task')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Phase 2 chưa mở: mọi task khoá, chạm hiện SnackBar và không '
        'điều hướng', (tester) async {
      await _pump(
        tester,
        _Server()..doc = phase2Doc(unlocked: false),
        initial: '/design/sd1',
      );
      for (final id in ['context', 't1', 't2', 't3']) {
        await tester.ensureVisible(_node(id));
        expect(
          find.descendant(of: _node(id), matching: lockIcon),
          findsOneWidget,
          reason: 'node $id phải khoá',
        );
      }
      for (final id in ['t1', 't3']) {
        await _tapNode(tester, id);
        expect(find.text('Đọc xong Phase 1 để mở Thực chiến'), findsOneWidget);
        expect(_loc(), '/design/sd1');
      }
    });

    testWidgets('làm task 3 trước: task 3 done, task 1 vẫn open và là '
        'current', (tester) async {
      final s = _Server()..doc = phase2Doc();
      await _pump(tester, s, initial: '/design/sd1');
      // "Bối cảnh" done khi có task xong → current rơi vào task chưa xong
      // đầu tiên theo thứ tự (t1), dù t3 đã xong.
      s.doc = phase2Doc(
        tasks: [
          _task('t1', 1, unlocked: true),
          _task('t2', 2, unlocked: true),
          _task('t3', 3, done: true, unlocked: true),
        ],
      );
      await _tapNode(tester, 't3'); // vào rồi quay lại → tải lại doc
      _router.pop();
      await tester.pumpAndSettle();
      expect(find.text('PHASE 2 · THỰC CHIẾN · 1/3 TASK'), findsOneWidget);
      expect(lockIcon, findsNothing);
      expect(find.byKey(const Key('duo-start-bubble')), findsOneWidget);
      expect(
        tester.getTopLeft(_node('t1')).dy -
            tester.getBottomLeft(find.byKey(const Key('duo-start-bubble'))).dy,
        inInclusiveRange(0, 30),
      );
      expect(
        find.descendant(
          of: _node('t3'),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
    });

    test('chuỗi "Làm task trước để mở khoá" không còn trong '
        'lib/features/system_design', () {
      final hits = [
        for (final f in Directory(
          'lib/features/system_design',
        ).listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('Làm task trước'))
            f.path,
      ];
      expect(hits, isEmpty);
    });

    testWidgets('INV-04: server nói locked thì locked dù đã đọc đủ thẻ', (
      tester,
    ) async {
      final s = _Server()
        ..doc = _doc(
          sections: [
            _section(
              's1',
              pos: 1,
              chapter: 'A',
              chapterPos: 1,
              done: true,
              read: 2,
            ),
            // Đọc đủ 2/2 thẻ nhưng server chưa mở.
            _section(
              's2',
              pos: 2,
              chapter: 'A',
              chapterPos: 1,
              unlocked: false,
              read: 2,
            ),
          ],
        );
      await _pump(tester, s, initial: '/design/sd1');
      expect(find.text('2/2 card'), findsWidgets);
      await _tapNode(tester, 's2');
      expect(find.text('Hoàn thành section trước để mở khoá'), findsOneWidget);
      expect(_loc(), '/design/sd1');
      // Không còn node open → không có bóng.
      expect(find.byKey(const Key('duo-start-bubble')), findsNothing);
    });

    testWidgets('lỗi 401 → "Cần đăng nhập"; Thử lại tải lại', (tester) async {
      final s = _Server()..doc = const SdApiException(401, 'unauthorized');
      await _pump(tester, s, initial: '/design/sd1');
      expect(find.text('Cần đăng nhập'), findsOneWidget);

      s.doc = _doc();
      await tester.tap(find.byKey(const Key('sd-retry')));
      await tester.pumpAndSettle();
      expect(find.text('CHAPTER 1 · 1/2 SECTION'), findsOneWidget);
    });
  });

  testWidgets('E2E màn chính: Home → tab Design → thẻ tài liệu → lộ trình '
      '(2 chạm)', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = _Server()..doc = _doc();
    appRouter.go('/');
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...contentOverrides,
          ...authOverrides(),
          clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
          ...s.overrides,
        ],
        child: const SmartCodingStudyApp(),
      ),
    );
    await tester.pumpAndSettle();
    String loc() =>
        appRouter.routerDelegate.currentConfiguration.last.matchedLocation;
    expect(loc(), '/');

    // Chạm 1: tab Design.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('bottom-nav')),
        matching: find.text('Design'),
      ),
    );
    await tester.pumpAndSettle();
    expect(loc(), '/design');
    expect(find.byKey(const Key('sd-docs-screen')), findsOneWidget);

    // Chạm 2: thẻ tài liệu → lộ trình toàn màn (không còn bottom nav).
    await tester.tap(find.byKey(const Key('sd-doc-sd1')));
    await tester.pumpAndSettle();
    expect(loc(), '/design/sd1');
    expect(find.byType(SdPathScreen), findsOneWidget);
    expect(find.text('CHAPTER 1 · 1/2 SECTION'), findsOneWidget);
    expect(find.byKey(const Key('bottom-nav')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
