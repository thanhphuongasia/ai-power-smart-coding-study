import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/data/admin_repository.dart';
import 'package:smart_coding_study/features/admin/admin_controller.dart';
import 'package:smart_coding_study/features/admin/review_detail_screen.dart';
import 'package:smart_coding_study/main.dart';

import 'admin_controller_test.dart' show jsonResponse;
import 'support/admin_fixture.dart' show sampleChange, samplePending;
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

const _exId = 'split-chunks';

Map<String, dynamic> _exerciseChange(int id) => {
  ...sampleChange(id: id, kind: 'exercise', itemId: _exId),
  'before': {
    'fields': {
      'id': _exId,
      'title': 'Tiêu đề cũ',
      'blocks': [
        {
          'label': 'A',
          'accepted_answers': ['x = 1'],
        },
      ],
    },
    'placements': {
      'f1': ['e0'],
    },
  },
  'after': {
    'fields': {
      'id': _exId,
      'title': 'Tiêu đề mới',
      'blocks': [
        {
          'label': 'A',
          'accepted_answers': ['x = 2'],
        },
      ],
    },
    'placements': {
      'f1': ['e0'],
    },
  },
};

class _Harness {
  final requests = <http.Request>[];
  late List<Map<String, dynamic>> pending;

  /// id -> (status, body) cho approve; mặc định 200.
  final failApprove = <int, (int, Map<String, dynamic>)>{};

  /// `also` trả về khi duyệt/bỏ thành công.
  List<int> also = [];
}

Future<_Harness> _pumpFromHome(
  WidgetTester tester,
  List<Map<String, dynamic>> initial,
) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = _Harness()..pending = [...initial];
  final client = MockClient((r) async {
    h.requests.add(r);
    final path = r.url.path;
    if (r.method == 'GET' && path == '/api/admin/changes') {
      return jsonResponse(jsonEncode({'changes': h.pending}), 200);
    }
    if (r.method == 'GET') {
      return jsonResponse(
        jsonEncode({
          'version': 'v1',
          'content': contentJson,
          'pending': [
            for (final c in h.pending)
              samplePending(
                id: c['id'] as int,
                kind: c['kind'] as String,
                itemId: c['item_id'] as String,
                action: c['action'] as String,
              ),
          ],
        }),
        200,
      );
    }
    final m = RegExp(r'/changes/(\d+)/(approve|reject)$').firstMatch(path);
    if (m != null) {
      final id = int.parse(m.group(1)!);
      final fail = m.group(2) == 'approve' ? h.failApprove[id] : null;
      if (fail != null) return jsonResponse(jsonEncode(fail.$2), fail.$1);
      h.pending.removeWhere((c) => c['id'] == id);
      return jsonResponse(
        jsonEncode({
          'id': id,
          'status': m.group(2) == 'approve' ? 'approved' : 'rejected',
          'version': 'v2',
          'also': h.also,
        }),
        200,
      );
    }
    return jsonResponse('{}', 404);
  });
  appRouter.go('/');
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
  // Đúng 2 chạm từ Home: admin-button -> admin-review-button.
  await tester.tap(find.byKey(const Key('admin-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('admin-review-button')));
  await tester.pumpAndSettle();
  return h;
}

ContentChange _change({
  required String kind,
  required String itemId,
  required String action,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) => ContentChange.fromJson({
  ...sampleChange(id: 1, kind: kind, itemId: itemId, action: action),
  'before': before,
  'after': after,
});

void main() {
  test(
    'create module: không có hàng id thô, chỉ vị trí nếu có anh em trước',
    () {
      final c = _change(
        kind: 'module',
        itemId: 'm9',
        action: 'create',
        after: {
          'fields': {'id': 'm9', 'name': 'Mới'},
          'theme_id': 't1',
          'parent_id': null,
          'order': ['m1', 'm2', 'm9'],
        },
      );
      final rows = diffOf(c, nameOf: (id) => id == 'm2' ? 'Hai' : id);
      final paths = rows.map((r) => r.path).toList();
      expect(paths, isNot(contains('order.[1]')));
      expect(paths.any((p) => p.startsWith('order.')), isFalse);
      final pos = rows.singleWhere((r) => r.path == 'order');
      expect(pos.label, 'Vị trí');
      expect(pos.after, 'Đứng sau Hai');
      expect(rows.any((r) => r.after == 'm1\nm2\nm9'), isFalse);
    },
  );

  test('sibling thêm vào order, mục không đổi chỗ: không có hàng vị trí', () {
    final c = _change(
      kind: 'module',
      itemId: 'm2',
      action: 'update',
      before: {
        'fields': {'id': 'm2', 'name': 'A'},
        'order': ['m1', 'm2'],
      },
      after: {
        'fields': {'id': 'm2', 'name': 'B'},
        'order': ['m1', 'm2', 'm3'],
      },
    );
    final rows = diffOf(c);
    expect(rows.map((r) => r.path), ['fields.name']);
  });

  test('sibling bớt đi, hoặc hai anh em khác đổi chỗ: mục không đổi chỗ', () {
    final c = _change(
      kind: 'module',
      itemId: 'm1',
      action: 'update',
      before: {
        'fields': {'id': 'm1', 'name': 'A'},
        'order': ['m1', 'm2', 'm3'],
      },
      after: {
        'fields': {'id': 'm1', 'name': 'A'},
        'order': ['m1', 'm3', 'm2'],
      },
    );
    expect(diffOf(c), isEmpty);
  });

  test('đổi chỗ thật: một hàng Vị trí có nghĩa', () {
    final c = _change(
      kind: 'module',
      itemId: 'm3',
      action: 'update',
      before: {
        'fields': {'id': 'm3', 'name': 'A'},
        'order': ['m1', 'm2', 'm3'],
      },
      after: {
        'fields': {'id': 'm3', 'name': 'A'},
        'order': ['m3', 'm1', 'm2'],
      },
    );
    final rows = diffOf(c, nameOf: (id) => 'N-$id');
    expect(rows, hasLength(1));
    expect(rows.single.label, 'Vị trí');
    expect(rows.single.before, 'Đứng sau N-m2');
    expect(rows.single.after, 'Đứng đầu');
  });

  test('cha đổi hiện nhãn dễ hiểu', () {
    final c = _change(
      kind: 'file',
      itemId: 'f1',
      action: 'update',
      before: {
        'fields': {'id': 'f1', 'name': 'F'},
        'module_id': 'm1',
        'order': ['f1'],
      },
      after: {
        'fields': {'id': 'f1', 'name': 'F'},
        'module_id': 'm2',
        'order': ['f1'],
      },
    );
    final rows = diffOf(c, nameOf: (id) => 'Mod-$id');
    expect(rows, hasLength(1));
    expect(rows.single.path, 'module_id');
    expect(rows.single.before, 'Mod-m1');
    expect(rows.single.after, 'Mod-m2');
  });

  test('placements: thêm vào file, bỏ khỏi file, đổi chỗ trong file', () {
    final c = _change(
      kind: 'exercise',
      itemId: 'e5',
      action: 'update',
      before: {
        'fields': {'id': 'e5', 'title': 'T'},
        'placements': {
          'f1': ['e1', 'e5'],
          'f2': ['e2', 'e3', 'e5'],
        },
      },
      after: {
        'fields': {'id': 'e5', 'title': 'T'},
        'placements': {
          'f1': ['e1', 'e9'], // bỏ e5, e9 là anh em mới
          'f2': ['e5', 'e2', 'e3'], // đổi chỗ
          'f3': ['e7', 'e5'], // thêm
        },
      },
    );
    final rows = {
      for (final r in diffOf(c, nameOf: (id) => id == 'f1' ? 'File 1' : id))
        r.label: r,
    };
    expect(rows.keys, {
      'Bỏ khỏi file File 1',
      'Đổi chỗ trong file f2',
      'Thêm vào file f3',
    });
    expect(rows['Thêm vào file f3']!.after, 'Đứng sau e7');
    expect(rows['Đổi chỗ trong file f2']!.after, 'Đứng đầu');
  });

  test('placements không đổi hoặc chỉ anh em đổi: không ra hàng', () {
    final c = _change(
      kind: 'exercise',
      itemId: 'e5',
      action: 'update',
      before: {
        'fields': {'id': 'e5', 'title': 'T'},
        'placements': {
          'f1': ['e1', 'e5'],
        },
      },
      after: {
        'fields': {'id': 'e5', 'title': 'T2'},
        'placements': {
          'f1': ['e1', 'e2', 'e5'],
        },
      },
    );
    expect(diffOf(c).map((r) => r.path), ['fields.title']);
  });

  test('diffOf chỉ giữ trường đổi, ô khoá theo label', () {
    final c = ContentChange.fromJson(_exerciseChange(1));
    final rows = diffOf(c);
    expect(rows.map((r) => r.path).toSet(), {
      'fields.title',
      'fields.blocks.ô A.accepted_answers',
    });
  });

  testWidgets('từ Home 2 chạm thấy danh sách; rỗng thì báo', (tester) async {
    await _pumpFromHome(tester, [
      sampleChange(id: 1),
      sampleChange(id: 2, kind: 'file', itemId: 'f9', action: 'create'),
    ]);
    expect(find.text('Chờ duyệt'), findsWidgets);
    expect(find.text('Sửa · Project'), findsOneWidget);
    expect(find.text('Thêm · File'), findsOneWidget);
    expect(find.text('Mới'), findsWidgets);
    expect(find.text('admin@x · 2026-10-11 00:00'), findsWidgets);
    expect(find.byKey(const Key('approve-1')), findsOneWidget);
    expect(find.byKey(const Key('reject-2')), findsOneWidget);
  });

  testWidgets('danh sách rỗng', (tester) async {
    await _pumpFromHome(tester, const []);
    expect(find.text('Không có gì chờ duyệt'), findsOneWidget);
  });

  testWidgets('duyệt thành công: mục biến mất', (tester) async {
    final h = await _pumpFromHome(tester, [
      sampleChange(id: 1),
      sampleChange(id: 2, kind: 'file', itemId: 'f9', action: 'create'),
    ]);
    await tester.tap(find.byKey(const Key('approve-1')));
    await tester.pumpAndSettle();
    expect(
      h.requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/1/approve'),
      ),
      hasLength(1),
    );
    expect(find.byKey(const Key('approve-1')), findsNothing);
    expect(find.byKey(const Key('approve-2')), findsOneWidget);
  });

  testWidgets('duyệt lỗi 422 dependency_missing hiện message, mục còn lại', (
    tester,
  ) async {
    final h = await _pumpFromHome(tester, [
      sampleChange(id: 2, kind: 'file', itemId: 'f9', action: 'create'),
    ]);
    h.failApprove[2] = (
      422,
      {
        'detail': 'dependency_missing',
        'message': 'Cần duyệt module "m9" trước',
        'errors': ['module m9 chưa có'],
      },
    );
    await tester.tap(find.byKey(const Key('approve-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-error')), findsOneWidget);
    expect(find.text('Cần duyệt module "m9" trước'), findsOneWidget);
    expect(find.text('• module m9 chưa có'), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-error-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve-2')), findsOneWidget);
  });

  testWidgets('bỏ: hỏi xác nhận, huỷ thì không gọi, xác nhận thì mất', (
    tester,
  ) async {
    final h = await _pumpFromHome(tester, [sampleChange(id: 1)]);
    await tester.tap(find.byKey(const Key('reject-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject-cancel')));
    await tester.pumpAndSettle();
    expect(h.requests.where((r) => r.url.path.endsWith('/reject')), isEmpty);
    expect(find.byKey(const Key('reject-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reject-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(
      h.requests.where((r) => r.url.path.endsWith('/1/reject')),
      hasLength(1),
    );
    expect(find.byKey(const Key('reject-1')), findsNothing);
    expect(find.text('Không có gì chờ duyệt'), findsOneWidget);
  });

  testWidgets('chi tiết bài: thấy diff và xem như học viên', (tester) async {
    await _pumpFromHome(tester, [_exerciseChange(7)]);
    await tester.tap(find.byKey(const Key('change-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('diff-before-fields.title')), findsOneWidget);
    expect(find.text('Tiêu đề cũ'), findsOneWidget);
    expect(find.byKey(const Key('diff-after-fields.title')), findsOneWidget);
    expect(find.text('Tiêu đề mới'), findsWidgets);
    expect(find.text('x = 1'), findsOneWidget);
    expect(find.text('x = 2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('preview-button')));
    await tester.tap(find.byKey(const Key('preview-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-banner')), findsOneWidget);
  });

  testWidgets('chi tiết: duyệt xong quay về danh sách', (tester) async {
    await _pumpFromHome(tester, [sampleChange(id: 1)]);
    await tester.tap(find.byKey(const Key('change-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-button')), findsNothing);
    await tester.tap(find.byKey(const Key('detail-approve')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-approve')), findsNothing);
    expect(find.text('Không có gì chờ duyệt'), findsOneWidget);
  });

  testWidgets('duyệt có also: SnackBar "kèm 1 mục"', (tester) async {
    final h = await _pumpFromHome(tester, [
      sampleChange(id: 1),
      sampleChange(id: 2, kind: 'file', itemId: 'f9', action: 'create'),
    ]);
    h.also = [2];
    await tester.tap(find.byKey(const Key('approve-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('kèm 1 mục'), findsOneWidget);
  });

  testWidgets('bỏ lúc đang có sửa chưa gửi: hiện notice đề xuất lại', (
    tester,
  ) async {
    await _pumpFromHome(tester, [sampleChange(id: 1)]);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('review-list'))),
    );
    expect(
      container.read(adminProvider.notifier).updateNode('airline', name: 'Sửa'),
      isTrue,
    );
    expect(container.read(adminProvider).dirty, isTrue);
    await tester.tap(find.byKey(const Key('reject-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('đề xuất lại'), findsOneWidget);
  });

  testWidgets('preview lúc dirty: cảnh báo trước, Huỷ thì không mở', (
    tester,
  ) async {
    await _pumpFromHome(tester, [_exerciseChange(7)]);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('review-list'))),
    );
    container.read(adminProvider.notifier).updateNode('airline', name: 'Sửa');
    await tester.tap(find.byKey(const Key('change-7')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('preview-button')));
    await tester.tap(find.byKey(const Key('preview-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-dirty-warning')), findsOneWidget);
    expect(find.textContaining('sửa chưa gửi của bạn'), findsOneWidget);
    await tester.tap(find.byKey(const Key('preview-dirty-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-banner')), findsNothing);

    await tester.tap(find.byKey(const Key('preview-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-dirty-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-banner')), findsOneWidget);
  });

  testWidgets('chi tiết: duyệt lỗi 404 -> dialog, tải lại, báo không còn', (
    tester,
  ) async {
    final h = await _pumpFromHome(tester, [sampleChange(id: 1)]);
    await tester.tap(find.byKey(const Key('change-1')));
    await tester.pumpAndSettle();
    h.failApprove[1] = (404, {'detail': 'not_found', 'message': 'Không thấy'});
    h.pending.clear(); // mục đã bị người khác xử lý
    await tester.tap(find.byKey(const Key('detail-approve')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-error-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-missing')), findsOneWidget);
    expect(find.text('Mục này không còn trong hàng chờ'), findsOneWidget);
  });
}
