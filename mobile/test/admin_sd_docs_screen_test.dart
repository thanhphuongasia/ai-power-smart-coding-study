import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/data/admin_repository.dart';
import 'package:smart_coding_study/main.dart';

import 'admin_controller_test.dart' show jsonResponse, sampleContent;
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

Map<String, dynamic> _doc(String id, String status) => {
  'id': id,
  'title': 'Doc $id',
  'status': status,
  'sections': 3,
  'cards': 5,
  'tasks': 0,
  'has_markdown': true,
};

class _Harness {
  final requests = <http.Request>[];
  final docs = <Map<String, dynamic>>[];

  /// (status, body) trả cho PUT; null = thành công.
  (int, Map<String, dynamic>)? failPut;
}

Future<_Harness> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> initial, {
  bool viaAdmin = false,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Harness()..docs.addAll(initial);
  final client = MockClient((r) async {
    h.requests.add(r);
    final path = r.url.path;
    if (r.method == 'GET' && path == '/api/admin/sd/docs') {
      return jsonResponse(jsonEncode({'items': h.docs}), 200);
    }
    final m = RegExp(r'/api/admin/sd/docs/([^/]+)/status$').firstMatch(path);
    if (r.method == 'PUT' && m != null) {
      final fail = h.failPut;
      if (fail != null) return jsonResponse(jsonEncode(fail.$2), fail.$1);
      final id = m.group(1)!;
      final status = (jsonDecode(r.body) as Map)['status'] as String;
      h.docs.firstWhere((d) => d['id'] == id)['status'] = status;
      return jsonResponse(jsonEncode({'id': id, 'status': status}), 200);
    }
    if (r.method == 'GET' && path == '/api/admin/changes') {
      return jsonResponse(jsonEncode({'changes': []}), 200);
    }
    if (r.method == 'GET') {
      return jsonResponse(
        jsonEncode({
          'version': 'v1',
          'content': sampleContent(),
          'pending': [],
        }),
        200,
      );
    }
    return jsonResponse('{}', 404);
  });
  appRouter.go(viaAdmin ? '/' : '/admin/sd');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...contentOverrides,
        ...authOverrides(roles: {'learner', 'admin'}),
        adminRepositoryProvider.overrideWithValue(
          AdminRepository(client, baseUrl: Uri.parse('http://x')),
        ),
      ],
      child: const SmartCodingStudyApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (viaAdmin) {
    await tester.tap(find.byKey(const Key('admin-button')));
    await tester.pumpAndSettle();
  }
  return h;
}

void main() {
  testWidgets('hiện đủ 3 trạng thái với đúng nút', (tester) async {
    await _pump(tester, [
      _doc('a', 'draft'),
      _doc('b', 'published'),
      _doc('c', 'archived'),
    ]);
    expect(find.byKey(const Key('admin-sd-docs')), findsOneWidget);
    expect(find.text('Bản nháp'), findsOneWidget);
    expect(find.text('Đã publish'), findsOneWidget);
    expect(find.text('Đã xoá mềm'), findsOneWidget);
    expect(find.text('3 section · 5 card'), findsNWidgets(3));
    expect(find.byKey(const Key('sd-publish-a')), findsOneWidget);
    expect(find.byKey(const Key('sd-unpublish-b')), findsOneWidget);
    expect(find.byKey(const Key('sd-restore-c')), findsOneWidget);
    expect(find.byKey(const Key('sd-publish-b')), findsNothing);
  });

  testWidgets('danh sách rỗng', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Chưa có tài liệu nào'), findsOneWidget);
  });

  testWidgets('Publish gọi PUT đúng rồi tải lại: doc chuyển sang nút Ẩn', (
    tester,
  ) async {
    final h = await _pump(tester, [_doc('a', 'draft')]);
    await tester.tap(find.byKey(const Key('sd-publish-a')));
    await tester.pumpAndSettle();
    final puts = h.requests.where((r) => r.method == 'PUT').toList();
    expect(puts, hasLength(1));
    expect(puts.single.url.path, '/api/admin/sd/docs/a/status');
    expect(jsonDecode(puts.single.body), {'status': 'published'});
    expect(find.byKey(const Key('sd-publish-a')), findsNothing);
    expect(find.byKey(const Key('sd-unpublish-a')), findsOneWidget);
    expect(find.text('Đã publish'), findsOneWidget);
  });

  testWidgets('Ẩn và Khôi phục đưa về draft', (tester) async {
    final h = await _pump(tester, [
      _doc('b', 'published'),
      _doc('c', 'archived'),
    ]);
    await tester.tap(find.byKey(const Key('sd-unpublish-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-restore-c')));
    await tester.pumpAndSettle();
    final bodies = [
      for (final r in h.requests.where((r) => r.method == 'PUT'))
        jsonDecode(r.body)['status'],
    ];
    expect(bodies, ['draft', 'draft']);
    expect(find.byKey(const Key('sd-publish-b')), findsOneWidget);
    expect(find.byKey(const Key('sd-publish-c')), findsOneWidget);
  });

  testWidgets('lỗi 422 hiện thông điệp, không crash, doc còn nguyên', (
    tester,
  ) async {
    final h = await _pump(tester, [_doc('a', 'draft')]);
    h.failPut = (
      422,
      {
        'errors': ['status không hợp lệ'],
      },
    );
    await tester.tap(find.byKey(const Key('sd-publish-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sd-docs-error')), findsOneWidget);
    expect(find.textContaining('status không hợp lệ'), findsOneWidget);
    expect(find.byKey(const Key('sd-publish-a')), findsOneWidget);
  });

  testWidgets('lỗi 404 doc_not_found hiện thông điệp, danh sách tải lại', (
    tester,
  ) async {
    final h = await _pump(tester, [_doc('a', 'draft')]);
    h.failPut = (404, {'detail': 'doc_not_found'});
    h.docs.clear();
    await tester.tap(find.byKey(const Key('sd-publish-a')));
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy tài liệu này'), findsOneWidget);
    expect(find.byKey(const Key('sd-publish-a')), findsNothing);
    expect(find.text('Chưa có tài liệu nào'), findsOneWidget);
  });

  testWidgets('từ màn Admin: 1 chạm vào được màn tài liệu SD', (tester) async {
    await _pump(tester, [_doc('a', 'draft')], viaAdmin: true);
    expect(find.byKey(const Key('admin-sd-docs')), findsNothing);
    await tester.tap(find.byKey(const Key('admin-sd-docs-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-sd-docs')), findsOneWidget);
    expect(find.byKey(const Key('sd-publish-a')), findsOneWidget);
  });
}
