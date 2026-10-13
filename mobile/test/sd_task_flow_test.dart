/// Phase 2 của System Design (T-10): màn bối cảnh, màn làm task (bản nháp,
/// nộp, lỗi, lịch sử, feedback reviewed thắng auto — INV-03), và 3 route mới
/// trong router THẬT của app.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Transitive của shared_preferences; test cần chặn store để điều khiển thời điểm đọc.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/data/auth_repository.dart';
import 'package:smart_coding_study/data/sd_repository.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/system_design/block_renderer.dart'
    show kPaperInk;
import 'package:smart_coding_study/features/system_design/context_screen.dart';
import 'package:smart_coding_study/features/system_design/reader_screen.dart';
import 'package:smart_coding_study/features/system_design/sd_path_screen.dart';
import 'package:smart_coding_study/features/system_design/task_screen.dart';
import 'package:smart_coding_study/main.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _task(
  String id,
  int pos, {
  bool unlocked = true,
  bool done = false,
  List<String> hints = const [],
  String? ref,
}) => {
  'id': id,
  'position': pos,
  'name': 'Task $pos',
  'unlocked': unlocked,
  'done': done,
  'attempts': 0,
  'prompt': ?(unlocked ? 'Đề của $id' : null),
  'hints': hints,
  'ref_section_id': ?ref,
};

Map<String, dynamic> _doc({
  bool phase2 = true,
  List<Map<String, dynamic>>? tasks,
}) => {
  'id': 'doc1',
  'title': 'Thiết kế URL shortener',
  'phase2_unlocked': phase2,
  'context': phase2
      ? [
          {
            'id': 'ctx1',
            'kind': 'text',
            'title': 'Bối cảnh chung',
            'body': 'Hệ thống rút gọn link cho 10 triệu người dùng.',
          },
        ]
      : <Object>[],
  'sections': [
    {
      'id': 's1',
      'position': 1,
      'chapter': 'Nền tảng',
      'chapter_position': 1,
      'title': 'Section s1',
      'cards': [
        {'id': 'c1', 'kind': 'text', 'title': 'Thẻ 1', 'body': 'Nội dung c1'},
      ],
      'read': ['c1'],
      'done': true,
      'unlocked': true,
    },
  ],
  'tasks': tasks ?? [_task('t1', 1), _task('t2', 2)],
};

Map<String, dynamic> _attempt(
  int n, {
  int? id,
  String source = 'auto',
  num score = 50,
  List<Map<String, dynamic>>? items,
  String? feedback,
}) => {
  'id': id ?? n,
  'n': n,
  'answer': 'câu trả lời $n',
  'created_at': '2026-10-12T09:00:00Z',
  'source': source,
  'score': score,
  'items':
      items ??
      [
        {'text': 'Có cache', 'ok': true, 'note': ''},
        {'text': 'Có CDN', 'ok': false, 'note': 'chưa nhắc tới'},
      ],
  'feedback': ?feedback,
  if (feedback != null) 'reviewed_at': '2026-10-12T10:00:00Z',
};

class _Server {
  _Server({Map<String, dynamic>? doc}) : doc = doc ?? _doc();

  Map<String, dynamic> doc;
  List<Map<String, dynamic>> attempts = [];
  int docGets = 0;
  int listGets = 0;
  int attemptGets = 0;
  final posts = <String>[];

  /// Thay cho POST mặc định (tạo lần thử auto).
  Future<http.Response> Function(String answer)? onPost;

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    if (r.method == 'GET' && path == '/api/sd/docs') {
      listGets++;
      return _json({
        'items': [
          {
            'id': 'doc1',
            'title': 'Thiết kế URL shortener',
            'sections': 1,
            'sections_done': 1,
            'cards': 1,
            'cards_read': 1,
            'phase2_unlocked': true,
            'tasks': 2,
            'tasks_done': 0,
          },
        ],
      });
    }
    if (r.method == 'GET' && RegExp(r'^/api/sd/docs/[^/]+$').hasMatch(path)) {
      docGets++;
      return _json(doc);
    }
    if (path.endsWith('/attempts')) {
      if (r.method == 'GET') {
        attemptGets++;
        return _json({'items': attempts});
      }
      final answer = (jsonDecode(r.body) as Map)['answer'] as String;
      posts.add(answer);
      if (onPost != null) return onPost!(answer);
      final a = _attempt(attempts.length + 1);
      attempts.insert(0, a);
      return _json({'attempt': a}, 201);
    }
    if (r.method == 'PUT') {
      return _json({
        'section_id': 's1',
        'read': ['c1'],
        'done': true,
        'next_section_id': null,
        'phase2_unlocked': true,
      });
    }
    return http.Response('không có route', 404);
  }

  SdRepository get repo =>
      SdRepository(MockClient(handle), baseUrl: Uri.parse('http://test'));
}

late GoRouter _router;

/// Người dùng đang đăng nhập trong test (null = chưa đăng nhập). Reset ở setUp.
const _kEmail = 'learner@example.com';
String? _email = _kEmail;

/// Phiên đăng nhập giả theo [_email].
List<Override> _auth() => [
  authControllerProvider.overrideWith(
    () => FakeAuthController(
      _email == null
          ? null
          : AuthSession(
              token: 't',
              user: AuthUser(email: _email!, roles: const ['learner']),
            ),
    ),
  ),
];

Widget _app(_Server s) => ProviderScope(
  retry: (_, _) => null,
  overrides: [sdRepositoryProvider.overrideWithValue(s.repo), ..._auth()],
  child: MaterialApp.router(theme: buildAppTheme(), routerConfig: _router),
);

/// Store SharedPreferences chặn `getAll` tới khi [gate] xong: giữ việc khôi
/// phục bản nháp ở trạng thái "chưa đọc xong".
class _GatedStore extends InMemorySharedPreferencesStore {
  _GatedStore(super.data, this.gate) : super.withData();
  final Completer<void> gate;

  @override
  Future<Map<String, Object>> getAll() async {
    await gate.future;
    return super.getAll();
  }
}

/// Dựng router nhỏ (3 route Phase 2 + trang đọc giả) rồi push [location].
Future<void> _open(
  WidgetTester tester,
  _Server s,
  String location, {
  Size size = const Size(400, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Placeholder(key: Key('home')),
      ),
      GoRoute(
        path: '/design/:docId/read',
        builder: (_, st) => Placeholder(
          key: Key('page-read-${st.uri.queryParameters['section']}'),
        ),
      ),
      GoRoute(
        path: '/design/:docId/context',
        builder: (_, st) => SdContextScreen(docId: st.pathParameters['docId']!),
      ),
      GoRoute(
        path: '/design/:docId/tasks/:taskId',
        builder: (_, st) => SdTaskScreen(
          docId: st.pathParameters['docId']!,
          taskId: st.pathParameters['taskId']!,
        ),
      ),
    ],
  );
  await tester.pumpWidget(_app(s));
  await tester.pumpAndSettle();
  unawaited(_router.push(location));
  await tester.pumpAndSettle();
}

String _loc() =>
    _router.routerDelegate.currentConfiguration.last.matchedLocation;

Finder _k(String key) => find.byKey(Key(key));

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_k('sd-task-input'), text);
  await tester.pump(kSdDraftDebounce + const Duration(milliseconds: 50));
}

Future<String?> _draft([String key = 'sd-draft:$_kEmail:doc1:t1']) async =>
    (await SharedPreferences.getInstance()).getString(key);

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<SdPaperButton>(_k(key)).onPressed != null;

String _inputText(WidgetTester tester) =>
    tester.widget<TextField>(_k('sd-task-input')).controller!.text;

void main() {
  setUp(() {
    _email = _kEmail;
    SharedPreferences.setMockInitialValues({});
  });

  group('SdContextScreen', () {
    testWidgets('hiện card bối cảnh; nút mở task mở-chưa-xong đầu tiên', (
      tester,
    ) async {
      final s = _Server(
        doc: _doc(
          tasks: [_task('t1', 1, done: true), _task('t2', 2), _task('t3', 3)],
        ),
      );
      await _open(tester, s, '/design/doc1/context');
      expect(find.text('PHASE 2 · THỰC CHIẾN · BỐI CẢNH'), findsOneWidget);
      expect(
        find.textContaining('Hệ thống rút gọn link cho 10 triệu'),
        findsOneWidget,
      );
      expect(find.text('Bắt đầu Task 2'), findsOneWidget);

      await _tap(tester, _k('sd-context-start'));
      expect(_loc(), '/design/doc1/tasks/t2');
      expect(find.byType(SdTaskScreen), findsOneWidget);
    });

    testWidgets('tất cả task đã xong → nút mở task đầu', (tester) async {
      final s = _Server(
        doc: _doc(
          tasks: [_task('t1', 1, done: true), _task('t2', 2, done: true)],
        ),
      );
      await _open(tester, s, '/design/doc1/context');
      expect(find.text('Bắt đầu Task 1'), findsOneWidget);
      await _tap(tester, _k('sd-context-start'));
      expect(_loc(), '/design/doc1/tasks/t1');
    });

    testWidgets('Phase 2 khoá: thông điệp, KHÔNG có nút bắt đầu', (
      tester,
    ) async {
      final s = _Server(doc: _doc(phase2: false));
      await _open(tester, s, '/design/doc1/context');
      expect(find.text('Đọc xong Phase 1 để mở Thực chiến'), findsOneWidget);
      expect(_k('sd-context-start'), findsNothing);
      expect(find.textContaining('Hệ thống rút gọn link'), findsNothing);
    });

    testWidgets('lỗi tải → SdErrorView, Thử lại tải lại', (tester) async {
      final s = _Server();
      var fail = true;
      final base = s.handle;
      // Doc lỗi 500 lần đầu.
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _router = GoRouter(
        initialLocation: '/design/doc1/context',
        routes: [
          GoRoute(
            path: '/design/:docId/context',
            builder: (_, st) =>
                SdContextScreen(docId: st.pathParameters['docId']!),
          ),
        ],
      );
      final repo = SdRepository(
        MockClient((r) async => fail ? http.Response('x', 500) : base(r)),
        baseUrl: Uri.parse('http://test'),
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [sdRepositoryProvider.overrideWithValue(repo), ..._auth()],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Không tải được (mã 500)'), findsOneWidget);
      fail = false;
      await tester.tap(_k('sd-retry'));
      await tester.pumpAndSettle();
      expect(find.text('Bắt đầu Task 1'), findsOneWidget);
    });

    // Hotfix #35: mọi task mở cùng lúc → nút "Bắt đầu" không dựa tuần tự.
    Future<void> startCase(
      WidgetTester tester,
      List<bool> done,
      String label,
      String id,
    ) async {
      final s = _Server(
        doc: _doc(
          tasks: [
            for (var i = 0; i < done.length; i++)
              _task('t${i + 1}', i + 1, done: done[i]),
          ],
        ),
      );
      await _open(tester, s, '/design/doc1/context');
      expect(find.text(label), findsOneWidget);
      await _tap(tester, _k('sd-context-start'));
      expect(_loc(), '/design/doc1/tasks/$id');
    }

    testWidgets('mọi task mở, chưa xong task nào → Bắt đầu task ĐẦU', (
      tester,
    ) async {
      await startCase(tester, [false, false, false], 'Bắt đầu Task 1', 't1');
    });

    testWidgets('task 1 xong, 2-3 mở → Bắt đầu Task 2', (tester) async {
      await startCase(tester, [true, false, false], 'Bắt đầu Task 2', 't2');
    });

    testWidgets('task 1-2 xong, 3 chưa → Bắt đầu Task 3', (tester) async {
      await startCase(tester, [true, true, false], 'Bắt đầu Task 3', 't3');
    });

    testWidgets('làm task 2 trước (1 chưa, 3 chưa) → vẫn Bắt đầu Task 1', (
      tester,
    ) async {
      await startCase(tester, [false, true, false], 'Bắt đầu Task 1', 't1');
    });

    testWidgets('tất cả task xong → nút mở task đầu', (tester) async {
      await startCase(tester, [true, true, true], 'Bắt đầu Task 1', 't1');
    });

    testWidgets('Phase 2 chưa mở → không có nút Bắt đầu', (tester) async {
      final s = _Server(
        doc: _doc(
          phase2: false,
          tasks: [
            _task('t1', 1, unlocked: false),
            _task('t2', 2, unlocked: false),
          ],
        ),
      );
      await _open(tester, s, '/design/doc1/context');
      expect(_k('sd-context-locked'), findsOneWidget);
      expect(_k('sd-context-start'), findsNothing);
    });
  });

  group('SdTaskScreen: đề, gợi ý, bộ đếm', () {
    testWidgets('đề, tiêu đề, Task i/n; gợi ý bấm mở/đóng, mặc định đóng', (
      tester,
    ) async {
      final s = _Server(
        doc: _doc(
          tasks: [
            _task('t1', 1, hints: ['mẹo một', 'mẹo hai']),
            _task('t2', 2),
          ],
        ),
      );
      await _open(tester, s, '/design/doc1/tasks/t1');
      expect(find.text('PHASE 2 · THỰC CHIẾN'), findsOneWidget);
      expect(find.text('Task 1'), findsOneWidget);
      expect(find.text('Đề của t1'), findsOneWidget);
      expect(find.text('Task 1/2'), findsOneWidget);
      expect(find.text('Gợi ý 1'), findsOneWidget);
      expect(find.text('Gợi ý 2'), findsOneWidget);
      expect(find.text('mẹo một'), findsNothing);

      await _tap(tester, _k('sd-hint-0'));
      expect(find.text('mẹo một'), findsOneWidget);
      expect(find.text('mẹo hai'), findsNothing);
      await _tap(tester, _k('sd-hint-0'));
      expect(find.text('mẹo một'), findsNothing);
    });

    testWidgets('bộ đếm theo byte UTF-8, không theo ký tự', (tester) async {
      await _open(tester, _Server(), '/design/doc1/tasks/t1');
      expect(find.text('0/8192'), findsOneWidget);
      await _type(tester, 'aéệ'); // 1 + 2 + 3 byte
      expect(find.text('6/8192'), findsOneWidget);
    });

    testWidgets('quá 8192 byte → chặn nộp và báo; vừa đủ thì nộp được', (
      tester,
    ) async {
      final s = _Server();
      // Màn rất cao để ô viết dài không đẩy bộ đếm ra ngoài vùng dựng.
      await _open(
        tester,
        s,
        '/design/doc1/tasks/t1',
        size: const Size(400, 8000),
      );
      expect(_enabled(tester, 'sd-task-submit'), isFalse); // rỗng

      await _type(tester, 'ệ' * 2731); // 8193 byte nhưng chỉ 2731 ký tự
      expect(find.text('8193/8192'), findsOneWidget);
      expect(_k('sd-task-too-long'), findsOneWidget);
      expect(_enabled(tester, 'sd-task-submit'), isFalse);

      await _type(tester, 'ệ' * 2730); // 8190 byte
      expect(find.text('8190/8192'), findsOneWidget);
      expect(_k('sd-task-too-long'), findsNothing);
      expect(_enabled(tester, 'sd-task-submit'), isTrue);
      expect(s.posts, isEmpty);
    });

    testWidgets('task khoá (Phase 2 chưa mở): thông điệp đúng lý do, KHÔNG có '
        'ô viết/nộp', (tester) async {
      final s = _Server(
        doc: _doc(
          phase2: false,
          tasks: [
            _task('t1', 1, unlocked: false),
            _task('t2', 2, unlocked: false),
          ],
        ),
      );
      await _open(tester, s, '/design/doc1/tasks/t2');
      expect(_k('sd-task-locked'), findsOneWidget);
      expect(
        find.textContaining('Đọc xong Phase 1 để mở Thực chiến'),
        findsOneWidget,
      );
      expect(find.textContaining('Làm task trước'), findsNothing);
      expect(_k('sd-task-input'), findsNothing);
      expect(_k('sd-task-submit'), findsNothing);
      expect(find.text('Task 2/2'), findsOneWidget);
    });

    testWidgets('taskId lạ → thông báo không tìm thấy', (tester) async {
      await _open(tester, _Server(), '/design/doc1/tasks/zzz');
      expect(_k('sd-task-missing'), findsOneWidget);
    });
  });

  group('SdTaskScreen: bản nháp', () {
    testWidgets('gõ → rời màn → mở lại còn nguyên', (tester) async {
      await _open(tester, _Server(), '/design/doc1/tasks/t1');
      await _type(tester, 'nháp của tôi');
      expect(await _draft(), 'nháp của tôi'); // đã qua debounce

      _router.pop();
      await tester.pumpAndSettle();
      expect(_k('sd-task-input'), findsNothing);

      unawaited(_router.push('/design/doc1/tasks/t1'));
      await tester.pumpAndSettle();
      expect(_inputText(tester), 'nháp của tôi');
      expect(find.text('${sdUtf8Length('nháp của tôi')}/8192'), findsOneWidget);
    });

    testWidgets('rời màn ngay (chưa hết debounce) vẫn ghi nốt', (tester) async {
      await _open(tester, _Server(), '/design/doc1/tasks/t1');
      await tester.enterText(_k('sd-task-input'), 'viết dở');
      await tester.pump(const Duration(milliseconds: 50)); // < 400ms
      _router.pop();
      await tester.pumpAndSettle();
      expect(await _draft(), 'viết dở');
    });

    testWidgets('nháp theo từng task: task khác không thấy', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sd-draft:$_kEmail:doc1:t1': 'của t1',
        'sd-draft:$_kEmail:doc1:t9': 'của t9',
      });
      await _open(tester, _Server(), '/design/doc1/tasks/t1');
      expect(_inputText(tester), 'của t1');
    });

    testWidgets('nộp thành công → xoá nháp, ô viết trống, lịch sử có lần mới', (
      tester,
    ) async {
      final s = _Server();
      await _open(tester, s, '/design/doc1/tasks/t1');
      await _type(tester, 'đáp án của tôi');
      expect(await _draft(), isNotNull);
      final docGetsBefore = s.docGets;

      await _tap(tester, _k('sd-task-submit'));
      expect(s.posts, ['đáp án của tôi']);
      expect(await _draft(), isNull);
      expect(_inputText(tester), '');
      expect(_k('sd-attempt-1'), findsOneWidget);
      expect(find.text('Lần 1 · 50 điểm'), findsOneWidget);
      expect(s.docGets, greaterThan(docGetsBefore)); // sdDocProvider invalidate

      // Rời màn sau nộp: không ghi lại nháp cũ.
      _router.pop();
      await tester.pumpAndSettle();
      expect(await _draft(), isNull);
    });

    testWidgets('trong lúc gửi nút bị vô hiệu hoá', (tester) async {
      final s = _Server();
      final gate = Completer<void>();
      s.onPost = (answer) async {
        await gate.future;
        final a = _attempt(1);
        s.attempts.insert(0, a);
        return _json({'attempt': a}, 201);
      };
      await _open(tester, s, '/design/doc1/tasks/t1');
      await _type(tester, 'abc');
      await tester.ensureVisible(_k('sd-task-submit'));
      await tester.tap(_k('sd-task-submit'));
      await tester.pump();
      expect(_enabled(tester, 'sd-task-submit'), isFalse);
      expect(find.text('Đang chấm…'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Lần 1 · 50 điểm'), findsOneWidget);
    });

    final errors = <String, ({http.Response Function() res, String msg})>{
      '409': (
        res: () => _json({'detail': 'task_locked'}, 409),
        msg: 'Task này chưa mở',
      ),
      '429': (
        res: () => _json({'detail': 'attempt_limit'}, 429),
        msg: 'Hôm nay bạn đã nộp tối đa 20 lần cho task này',
      ),
      '422': (
        res: () => _json({'detail': <Object>[]}, 422),
        msg: 'Câu trả lời chưa hợp lệ',
      ),
      '500': (
        res: () => http.Response('lỗi', 500),
        msg: 'Không gửi được. Bản nháp vẫn còn, thử lại sau',
      ),
    };
    for (final e in errors.entries) {
      testWidgets('lỗi ${e.key}: đúng thông điệp, nháp còn nguyên', (
        tester,
      ) async {
        final s = _Server()..onPost = (_) async => e.value.res();
        await _open(tester, s, '/design/doc1/tasks/t1');
        await _type(tester, 'giữ lấy tôi');
        await _tap(tester, _k('sd-task-submit'));
        expect(find.text(e.value.msg), findsOneWidget);
        expect(_inputText(tester), 'giữ lấy tôi');
        expect(await _draft(), 'giữ lấy tôi');
        expect(_enabled(tester, 'sd-task-submit'), isTrue); // thử lại được
        expect(_k('sd-attempt-1'), findsNothing);
      });
    }

    testWidgets('lỗi mạng thô (ClientException): nháp còn nguyên', (
      tester,
    ) async {
      final s = _Server()
        ..onPost = (_) async => throw http.ClientException('mất mạng');
      await _open(tester, s, '/design/doc1/tasks/t1');
      await _type(tester, 'giữ lấy tôi');
      await _tap(tester, _k('sd-task-submit'));
      expect(
        find.text('Không gửi được. Bản nháp vẫn còn, thử lại sau'),
        findsOneWidget,
      );
      expect(await _draft(), 'giữ lấy tôi');
    });
  });

  group('SdTaskScreen: kết quả và lịch sử (INV-03)', () {
    testWidgets('auto: ✓/✗, ghi chú và nhãn "Chấm sơ bằng từ khoá"', (
      tester,
    ) async {
      final s = _Server()..attempts = [_attempt(1, score: 50)];
      await _open(tester, s, '/design/doc1/tasks/t1');
      expect(find.text('Lần 1 · 50 điểm'), findsOneWidget);
      expect(find.text('Chấm sơ bằng từ khoá'), findsOneWidget);
      expect(find.text('Có cache'), findsOneWidget);
      expect(find.text('Có CDN'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
      expect(find.text('✗'), findsOneWidget);
      expect(find.text('chưa nhắc tới'), findsOneWidget);
      expect(find.text('Claude đã chấm'), findsNothing);
    });

    testWidgets('reviewed: "Claude đã chấm" + feedback, KHÔNG có items auto', (
      tester,
    ) async {
      // API đã quyết reviewed thắng: items trả về là của bản reviewed.
      final s = _Server()
        ..attempts = [
          _attempt(
            1,
            source: 'reviewed',
            score: 90,
            items: [
              {'text': 'Ý đã duyệt', 'ok': true, 'note': 'chuẩn'},
            ],
            feedback: 'Bài làm tốt, thêm phần sharding nữa nhé.',
          ),
        ];
      await _open(tester, s, '/design/doc1/tasks/t1');
      expect(find.text('Lần 1 · 90 điểm'), findsOneWidget);
      expect(find.text('Claude đã chấm'), findsOneWidget);
      expect(
        find.text('Bài làm tốt, thêm phần sharding nữa nhé.'),
        findsOneWidget,
      );
      expect(find.text('Ý đã duyệt'), findsOneWidget);
      expect(find.text('Chấm sơ bằng từ khoá'), findsNothing);
      expect(find.text('Có cache'), findsNothing);
      expect(find.text('Có CDN'), findsNothing);
    });

    testWidgets('nhiều lần thử: mới nhất mở sẵn, cũ thu gọn, bấm để mở', (
      tester,
    ) async {
      final s = _Server()
        ..attempts = [
          _attempt(
            3,
            items: [
              {'text': 'ý của lần 3', 'ok': true, 'note': ''},
            ],
          ),
          _attempt(
            2,
            items: [
              {'text': 'ý của lần 2', 'ok': true, 'note': ''},
            ],
          ),
          _attempt(
            1,
            items: [
              {'text': 'ý của lần 1', 'ok': false, 'note': ''},
            ],
          ),
        ];
      await _open(tester, s, '/design/doc1/tasks/t1');
      expect(find.text('ý của lần 3'), findsOneWidget);
      expect(find.text('ý của lần 2'), findsNothing);
      expect(find.text('ý của lần 1'), findsNothing);
      // Tiêu đề cả ba lần vẫn thấy.
      expect(_k('sd-attempt-head-2'), findsOneWidget);

      await _tap(tester, _k('sd-attempt-head-2'));
      expect(find.text('ý của lần 2'), findsOneWidget);
      await _tap(tester, _k('sd-attempt-head-3'));
      expect(find.text('ý của lần 3'), findsNothing);
    });

    testWidgets('nộp lần mới: lên đầu, lần cũ thu gọn', (tester) async {
      final s = _Server()
        ..attempts = [
          _attempt(
            1,
            items: [
              {'text': 'ý cũ', 'ok': false, 'note': ''},
            ],
          ),
        ];
      await _open(tester, s, '/design/doc1/tasks/t1');
      expect(find.text('ý cũ'), findsOneWidget);
      await _type(tester, 'làm lại');
      await _tap(tester, _k('sd-task-submit'));
      expect(find.text('Lần 2 · 50 điểm'), findsOneWidget);
      expect(find.text('ý cũ'), findsNothing); // lần 1 đã thu gọn
      final y2 = tester.getTopLeft(_k('sd-attempt-2')).dy;
      final y1 = tester.getTopLeft(_k('sd-attempt-1')).dy;
      expect(y2, lessThan(y1));
    });

    testWidgets('"Làm mới" tải lại: bản reviewed thay bản auto', (
      tester,
    ) async {
      final s = _Server()..attempts = [_attempt(1)];
      await _open(tester, s, '/design/doc1/tasks/t1');
      expect(find.text('Chấm sơ bằng từ khoá'), findsOneWidget);
      final gets = s.attemptGets;

      // Claude chấm qua MCP: server giờ trả bản reviewed.
      s.attempts = [
        _attempt(
          1,
          source: 'reviewed',
          score: 85,
          items: [
            {'text': 'Ý đã duyệt', 'ok': true, 'note': ''},
          ],
          feedback: 'Đã xem xong.',
        ),
      ];
      await _tap(tester, _k('sd-task-refresh'));
      expect(s.attemptGets, greaterThan(gets));
      expect(find.text('Claude đã chấm'), findsOneWidget);
      expect(find.text('Đã xem xong.'), findsOneWidget);
      expect(find.text('Chấm sơ bằng từ khoá'), findsNothing);
      expect(find.text('Có cache'), findsNothing);
      expect(find.text('Lần 1 · 85 điểm'), findsOneWidget);
    });

    testWidgets('lỗi tải lịch sử: báo lỗi, Thử lại tải lại', (tester) async {
      final s = _Server();
      var fail = true;
      final base = s.handle;
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _router = GoRouter(
        initialLocation: '/design/doc1/tasks/t1',
        routes: [
          GoRoute(
            path: '/design/:docId/tasks/:taskId',
            builder: (_, st) => SdTaskScreen(
              docId: st.pathParameters['docId']!,
              taskId: st.pathParameters['taskId']!,
            ),
          ),
        ],
      );
      final repo = SdRepository(
        MockClient((r) async {
          if (fail && r.url.path.endsWith('/attempts')) {
            return http.Response('x', 500);
          }
          return base(r);
        }),
        baseUrl: Uri.parse('http://test'),
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [sdRepositoryProvider.overrideWithValue(repo), ..._auth()],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_k('sd-attempts-error'), findsOneWidget);
      expect(_k('sd-task-input'), findsOneWidget); // vẫn viết được
      fail = false;
      s.attempts = [_attempt(1)];
      await _tap(tester, _k('sd-attempts-retry'));
      expect(find.text('Lần 1 · 50 điểm'), findsOneWidget);
    });
  });

  group('SdTaskScreen: điều hướng', () {
    testWidgets('"Xem đáp án mẫu" push đúng /read?section=<id>', (
      tester,
    ) async {
      final s = _Server(
        doc: _doc(
          tasks: [
            _task('t1', 1, ref: 's1'),
            _task('t2', 2),
          ],
        ),
      );
      await _open(tester, s, '/design/doc1/tasks/t1');
      await _tap(tester, _k('sd-task-ref'));
      expect(_loc(), '/design/doc1/read');
      expect(_k('page-read-s1'), findsOneWidget);
    });

    testWidgets('không có refSectionId → không có nút đáp án mẫu', (
      tester,
    ) async {
      await _open(tester, _Server(), '/design/doc1/tasks/t1');
      expect(_k('sd-task-ref'), findsNothing);
    });

    testWidgets('"Task tiếp theo" chỉ hiện sau ≥1 lần thử', (tester) async {
      final s = _Server();
      await _open(tester, s, '/design/doc1/tasks/t1');
      expect(_k('sd-task-next'), findsNothing);
      await _type(tester, 'bài');
      await _tap(tester, _k('sd-task-submit'));
      expect(_k('sd-task-next'), findsOneWidget);
    });

    testWidgets('task kế đã mở khoá → thay màn bằng task kế', (tester) async {
      final s = _Server(doc: _doc(tasks: [_task('t1', 1), _task('t2', 2)]))
        ..attempts = [_attempt(1)];
      await _open(tester, s, '/design/doc1/tasks/t1');
      await _tap(tester, _k('sd-task-next'));
      expect(_loc(), '/design/doc1/tasks/t2');
      expect(find.text('Task 2/2'), findsOneWidget);
      // Replace: lùi một bước về thẳng trang gốc.
      _router.pop();
      await tester.pumpAndSettle();
      expect(_loc(), '/');
    });

    testWidgets('task kế mở sẵn (không cần nộp task trước): từ task 1 sang '
        'task 2', (tester) async {
      final s = _Server(
        doc: _doc(tasks: [_task('t1', 1), _task('t2', 2), _task('t3', 3)]),
      )..attempts = [_attempt(1)];
      await _open(tester, s, '/design/doc1/tasks/t1');
      await _tap(tester, _k('sd-task-next'));
      expect(_loc(), '/design/doc1/tasks/t2');
    });

    testWidgets('làm task 3 (cuối) trước: nộp xong không có "Task tiếp theo", '
        'doc báo task 3 done còn task 1 vẫn mở', (tester) async {
      final s = _Server(
        doc: _doc(tasks: [_task('t1', 1), _task('t2', 2), _task('t3', 3)]),
      );
      await _open(tester, s, '/design/doc1/tasks/t3');
      expect(_k('sd-task-locked'), findsNothing);
      await _type(tester, 'bài');
      s.onPost = (_) async {
        s.doc = _doc(
          tasks: [_task('t1', 1), _task('t2', 2), _task('t3', 3, done: true)],
        );
        final a = _attempt(1, score: 100);
        s.attempts.insert(0, a);
        return _json({'attempt': a}, 201);
      };
      await _tap(tester, _k('sd-task-submit'));
      expect(_k('sd-task-next'), findsNothing);
      expect(find.text('Task 3/3'), findsOneWidget);
      // Task 1 vẫn làm được: mở màn task 1 thấy ô viết, không bị khoá.
      _router.go('/design/doc1/tasks/t1');
      await tester.pumpAndSettle();
      expect(_k('sd-task-input'), findsOneWidget);
      expect(_k('sd-task-locked'), findsNothing);
    });

    testWidgets('task cuối: không có "Task tiếp theo"', (tester) async {
      final s = _Server(doc: _doc(tasks: [_task('t1', 1), _task('t2', 2)]))
        ..attempts = [_attempt(1)];
      await _open(tester, s, '/design/doc1/tasks/t2');
      expect(_k('sd-task-next'), findsNothing);
    });
  });

  group('Correction T-10: riêng tư, route, màu, làm mới, rời màn', () {
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(SdTaskScreen)));

    // M1
    testWidgets(
      'M1: đổi user → không thấy nháp của user trước, ghi vào khoá của mình',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'sd-draft:a@x.com:doc1:t1': 'nháp của A',
        });
        _email = 'b@x.com';
        await _open(tester, _Server(), '/design/doc1/tasks/t1');
        expect(_inputText(tester), ''); // không thấy nháp của A
        await _type(tester, 'nháp của B');
        expect(await _draft('sd-draft:b@x.com:doc1:t1'), 'nháp của B');
        expect(await _draft('sd-draft:a@x.com:doc1:t1'), 'nháp của A');

        // A đăng nhập lại cùng máy: nháp của A còn nguyên.
        _router.pop();
        await tester.pumpAndSettle();
        _email = 'a@x.com';
        await tester.pumpWidget(
          const SizedBox(),
        ); // bỏ ProviderScope cũ (phiên của B)
        await _open(tester, _Server(), '/design/doc1/tasks/t1');
        expect(_inputText(tester), 'nháp của A');
      },
    );

    testWidgets('M1: chưa đăng nhập → không đọc, không ghi SharedPreferences', (
      tester,
    ) async {
      final seed = {
        'sd-draft:null:doc1:t1': 'nháp ma',
        'sd-draft:doc1:t1': 'nháp cũ không user',
      };
      SharedPreferences.setMockInitialValues(Map.of(seed));
      _email = null;
      await _open(tester, _Server(), '/design/doc1/tasks/t1');
      expect(_k('sd-task-input'), findsOneWidget); // vẫn viết được
      expect(_inputText(tester), '');
      await _type(tester, 'đang viết');
      _router.pop();
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), seed.keys.toSet());
      for (final e in seed.entries) {
        expect(prefs.getString(e.key), e.value);
      }
    });

    // M2
    testWidgets('M2: id có dấu cách và "/" được mã hoá trong mọi location', (
      tester,
    ) async {
      final doc = _doc(
        tasks: [
          _task('x/y', 1, ref: 's&1=2 x'),
          _task('z/w', 2),
        ],
      )..['id'] = 'a b/c';
      final s = _Server(doc: doc)..attempts = [_attempt(1)];
      await _open(tester, s, '/design/doc1/context');
      String uri() =>
          _router.routerDelegate.currentConfiguration.last.matchedLocation;

      await _tap(tester, _k('sd-context-start'));
      expect(uri(), '/design/a%20b%2Fc/tasks/x%2Fy');
      expect(find.byType(SdTaskScreen), findsOneWidget);

      await _tap(tester, _k('sd-task-ref'));
      expect(uri(), '/design/a%20b%2Fc/read');
      expect(_k('page-read-s&1=2 x'), findsOneWidget);
      _router.pop();
      await tester.pumpAndSettle();

      await _tap(tester, _k('sd-task-next'));
      expect(uri(), '/design/a%20b%2Fc/tasks/z%2Fw');
    });

    // M3
    Color? textColor(WidgetTester tester, String key) => tester
        .widget<RichText>(
          find.descendant(of: _k(key), matching: find.byType(RichText)),
        )
        .text
        .style
        ?.color;

    testWidgets(
      'M3: "Làm mới" và "Thử lại" trên tờ giấy có màu cố định ở theme tối',
      (tester) async {
        expect(buildAppTheme().brightness, Brightness.dark);
        final s = _Server();
        var fail = true;
        final base = s.handle;
        tester.view.physicalSize = const Size(400, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        _router = GoRouter(
          initialLocation: '/design/doc1/tasks/t1',
          routes: [
            GoRoute(
              path: '/design/:docId/tasks/:taskId',
              builder: (_, st) => SdTaskScreen(
                docId: st.pathParameters['docId']!,
                taskId: st.pathParameters['taskId']!,
              ),
            ),
          ],
        );
        final repo = SdRepository(
          MockClient((r) async {
            if (fail && r.url.path.endsWith('/attempts')) {
              return http.Response('x', 500);
            }
            return base(r);
          }),
          baseUrl: Uri.parse('http://test'),
        );
        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              sdRepositoryProvider.overrideWithValue(repo),
              ..._auth(),
            ],
            child: MaterialApp.router(
              theme: buildAppTheme(),
              routerConfig: _router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(textColor(tester, 'sd-task-refresh'), kPaperInk);
        expect(textColor(tester, 'sd-attempts-retry'), kPaperInk);
        // Không dùng màu primary của theme.
        final primary = Theme.of(
          tester.element(_k('sd-task-refresh')),
        ).colorScheme.primary;
        expect(primary, isNot(kPaperInk));
      },
    );

    // M4
    testWidgets('M4: làm mới doc lỗi → giữ nội dung cũ + SnackBar', (
      tester,
    ) async {
      final s = _Server();
      var failDoc = false;
      final base = s.handle;
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _router = GoRouter(
        initialLocation: '/design/doc1/tasks/t1',
        routes: [
          GoRoute(
            path: '/design/:docId/tasks/:taskId',
            builder: (_, st) => SdTaskScreen(
              docId: st.pathParameters['docId']!,
              taskId: st.pathParameters['taskId']!,
            ),
          ),
        ],
      );
      final repo = SdRepository(
        MockClient((r) async {
          if (failDoc && RegExp(r'^/api/sd/docs/[^/]+$').hasMatch(r.url.path)) {
            return http.Response('x', 500);
          }
          return base(r);
        }),
        baseUrl: Uri.parse('http://test'),
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [sdRepositoryProvider.overrideWithValue(repo), ..._auth()],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'đang viết dở');
      expect(find.text('Đề của t1'), findsOneWidget);

      failDoc = true;
      await _tap(tester, _k('sd-task-refresh'));
      expect(_k('sd-error'), findsNothing);
      expect(find.text('Đề của t1'), findsOneWidget);
      expect(_inputText(tester), 'đang viết dở');
      expect(find.text('Không làm mới được'), findsOneWidget);
    });

    testWidgets('M4: lần tải ĐẦU lỗi → vẫn SdErrorView + Thử lại', (
      tester,
    ) async {
      final s = _Server();
      var fail = true;
      final base = s.handle;
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _router = GoRouter(
        initialLocation: '/design/doc1/tasks/t1',
        routes: [
          GoRoute(
            path: '/design/:docId/tasks/:taskId',
            builder: (_, st) => SdTaskScreen(
              docId: st.pathParameters['docId']!,
              taskId: st.pathParameters['taskId']!,
            ),
          ),
        ],
      );
      final repo = SdRepository(
        MockClient((r) async => fail ? http.Response('x', 500) : base(r)),
        baseUrl: Uri.parse('http://test'),
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [sdRepositoryProvider.overrideWithValue(repo), ..._auth()],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_k('sd-error'), findsOneWidget);
      fail = false;
      await _tap(tester, _k('sd-retry'));
      expect(find.text('Đề của t1'), findsOneWidget);
    });

    // M5
    testWidgets(
      'M5: rời màn lúc đang gửi rồi hoàn tất → doc và danh sách được làm mới',
      (tester) async {
        final s = _Server();
        final gate = Completer<void>();
        s.onPost = (answer) async {
          await gate.future;
          final a = _attempt(1);
          s.attempts.insert(0, a);
          return _json({'attempt': a}, 201);
        };
        await _open(tester, s, '/design/doc1/tasks/t1');
        final container = containerOf(tester);
        // Giữ provider sống như màn lộ trình đang đứng sau.
        final subDoc = container.listen(sdDocProvider('doc1'), (_, _) {});
        final subDocs = container.listen(sdDocsProvider, (_, _) {});
        addTearDown(subDoc.close);
        addTearDown(subDocs.close);
        await tester.pumpAndSettle();

        await _type(tester, 'bài');
        await tester.ensureVisible(_k('sd-task-submit'));
        await tester.tap(_k('sd-task-submit'));
        await tester.pump();
        _router.pop(); // rời màn khi đang gửi
        await tester.pumpAndSettle();
        expect(find.byType(SdTaskScreen), findsNothing);
        final docGets = s.docGets;
        final listGets = s.listGets;

        gate.complete();
        await tester.pumpAndSettle();
        expect(s.posts, ['bài']);
        expect(s.docGets, greaterThan(docGets));
        expect(s.listGets, greaterThan(listGets));
        expect(await _draft(), isNull); // nộp xong thì nháp cũng được xoá
      },
    );

    // Mutant sống 1
    testWidgets('nộp xong tải lại sdDocsProvider (danh sách tài liệu)', (
      tester,
    ) async {
      final s = _Server();
      await _open(tester, s, '/design/doc1/tasks/t1');
      final sub = containerOf(tester).listen(sdDocsProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.pumpAndSettle();
      final before = s.listGets;
      expect(before, greaterThan(0));

      await _type(tester, 'bài');
      await _tap(tester, _k('sd-task-submit'));
      expect(s.listGets, greaterThan(before));
    });

    // Mutant sống 2
    testWidgets('nội dung toàn khoảng trắng/xuống dòng → không nộp được', (
      tester,
    ) async {
      final s = _Server();
      await _open(tester, s, '/design/doc1/tasks/t1');
      await _type(tester, '  \n\n \t ');
      expect(
        find.text('7/8192'),
        findsOneWidget,
      ); // có nội dung nhưng toàn trắng
      expect(_enabled(tester, 'sd-task-submit'), isFalse);
      await _type(tester, '  a  ');
      expect(_enabled(tester, 'sd-task-submit'), isTrue);
    });

    // Mutant sống 3
    testWidgets(
      'rời màn TRƯỚC khi khôi phục nháp xong → nháp cũ không bị xoá',
      (tester) async {
        const key = 'sd-draft:$_kEmail:doc1:t1';
        final gate = Completer<void>();
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = _GatedStore({
          'flutter.$key': 'nháp quý',
        }, gate);
        await _open(tester, _Server(), '/design/doc1/tasks/t1');
        expect(_k('sd-task-input'), findsOneWidget);
        expect(_inputText(tester), ''); // chưa khôi phục xong

        _router.pop();
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(await _draft(), 'nháp quý');
      },
    );
  });

  group('Router THẬT của app', () {
    late _Server server;

    Future<void> pumpApp(WidgetTester tester, String location) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      server = _Server()..attempts = [_attempt(1)];
      appRouter.go(location);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...contentOverrides,
            ...authOverrides(),
            clockProvider.overrideWithValue(() => DateTime(2026, 3, 10, 9)),
            sdRepositoryProvider.overrideWithValue(server.repo),
          ],
          child: const SmartCodingStudyApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    String loc() =>
        appRouter.routerDelegate.currentConfiguration.last.matchedLocation;

    tearDown(() => appRouter.go('/'));

    testWidgets('/design/<id>/read?section=s1 → SdReaderScreen', (
      tester,
    ) async {
      await pumpApp(tester, '/design/doc1/read?section=s1');
      expect(find.byType(SdReaderScreen), findsOneWidget);
      expect(find.byType(SdPathScreen), findsNothing);
      expect(find.byKey(const Key('bottom-nav')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('/design/<id>/context → SdContextScreen', (tester) async {
      await pumpApp(tester, '/design/doc1/context');
      expect(find.byType(SdContextScreen), findsOneWidget);
      expect(find.text('Bắt đầu Task 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('/design/<id>/tasks/<id> → SdTaskScreen', (tester) async {
      await pumpApp(tester, '/design/doc1/tasks/t1');
      expect(find.byType(SdTaskScreen), findsOneWidget);
      expect(find.text('Đề của t1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('/design/<id> vẫn là màn lộ trình (không bị route con nuốt)', (
      tester,
    ) async {
      await pumpApp(tester, '/design/doc1');
      expect(find.byType(SdPathScreen), findsOneWidget);
      expect(find.byType(SdReaderScreen), findsNothing);
      expect(find.byType(SdContextScreen), findsNothing);
      expect(find.byType(SdTaskScreen), findsNothing);
    });

    testWidgets('Home → tab Design → thẻ tài liệu → node section → màn đọc', (
      tester,
    ) async {
      await pumpApp(tester, '/');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('bottom-nav')),
          matching: find.text('Design'),
        ),
      );
      await tester.pumpAndSettle();
      expect(loc(), '/design');

      await tester.tap(find.byKey(const Key('sd-doc-doc1')));
      await tester.pumpAndSettle();
      expect(loc(), '/design/doc1');
      expect(find.byType(SdPathScreen), findsOneWidget);

      final node = find.byKey(const Key('duo-node-s1'));
      await tester.ensureVisible(node);
      await tester.tap(node);
      await tester.pumpAndSettle();
      expect(loc(), '/design/doc1/read');
      expect(find.byType(SdReaderScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Không overflow', () {
    for (final w in [320.0, 800.0]) {
      testWidgets('task + lịch sử + gợi ý ở bề rộng ${w.toInt()}', (
        tester,
      ) async {
        final long = 'Một ý rất dài ' * 12;
        final s =
            _Server(
                doc: _doc(
                  tasks: [
                    _task('t1', 1, hints: [long, 'ngắn'], ref: 's1'),
                    _task('t2', 2),
                  ],
                ),
              )
              ..attempts = [
                _attempt(
                  2,
                  source: 'reviewed',
                  feedback: long,
                  items: [
                    {'text': long, 'ok': true, 'note': long},
                  ],
                ),
                _attempt(1),
              ];
        await _open(tester, s, '/design/doc1/tasks/t1', size: Size(w, 900));
        await _tap(tester, _k('sd-hint-0'));
        await _type(tester, 'dòng\n' * 30);
        expect(tester.takeException(), isNull);
      });

      testWidgets('bối cảnh + task khoá ở bề rộng ${w.toInt()}', (
        tester,
      ) async {
        final s = _Server();
        await _open(tester, s, '/design/doc1/context', size: Size(w, 900));
        expect(tester.takeException(), isNull);
        await _open(tester, s, '/design/doc1/tasks/t2', size: Size(w, 900));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
