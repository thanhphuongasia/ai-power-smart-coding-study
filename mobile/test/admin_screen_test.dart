import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/data/admin_repository.dart';
import 'package:smart_coding_study/features/admin/admin_screen.dart';
import 'package:smart_coding_study/features/admin/exercise_editor.dart';

import 'admin_controller_test.dart' show jsonResponse, sampleContent;

Future<List<http.Request>> pumpAdmin(
  WidgetTester tester, {
  int putStatus = 200,
  Map<String, dynamic>? validateBody,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final requests = <http.Request>[];
  final client = MockClient((r) async {
    requests.add(r);
    if (r.method == 'GET') {
      return jsonResponse(
        jsonEncode({'version': 'v1', 'content': sampleContent()}),
        200,
      );
    }
    if (r.url.path.endsWith('validate')) {
      return jsonResponse(
        jsonEncode(validateBody ?? {'ok': true, 'errors': <String>[]}),
        200,
      );
    }
    return jsonResponse(
      jsonEncode(
        putStatus == 200 ? {'version': 'v2'} : {'detail': 'version_conflict'},
      ),
      putStatus,
    );
  });
  final router = GoRouter(
    initialLocation: '/admin',
    routes: [
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
      GoRoute(
        path: '/admin/exercise/:id',
        builder: (_, s) =>
            ExerciseEditorScreen(exerciseId: s.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          AdminRepository(client, baseUrl: Uri.parse('http://x')),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  testWidgets('cây hiện theme → module → file → bài; chưa dirty', (
    tester,
  ) async {
    await pumpAdmin(tester);
    expect(find.byKey(const Key('admin-tree')), findsOneWidget);
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('Module 1'), findsOneWidget);
    expect(find.text('a.py'), findsOneWidget);
    expect(find.byKey(const Key('exercise-e1-open')), findsOneWidget);
    expect(find.text('Đã đồng bộ'), findsOneWidget);
  });

  testWidgets('đổi tên theme → dirty → Lưu gửi base_version', (tester) async {
    final requests = await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('theme-t1-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-name')), 'Tên mới');
    await tester.tap(find.byKey(const Key('edit-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Tên mới'), findsOneWidget);
    expect(find.text('Chưa lưu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-save')));
    await tester.pumpAndSettle();
    final put = requests.last;
    expect(put.method, 'PUT');
    expect((jsonDecode(put.body) as Map)['base_version'], 'v1');
    expect(find.text('Đã đồng bộ'), findsOneWidget);
    expect(find.text('Đã lưu'), findsOneWidget);
  });

  testWidgets('Kiểm tra hiện lỗi trong panel admin-errors', (tester) async {
    await pumpAdmin(
      tester,
      validateBody: {
        'ok': false,
        'errors': ['e1: thiếu judge'],
      },
    );
    await tester.tap(find.byKey(const Key('admin-validate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-errors')), findsOneWidget);
    expect(find.text('• e1: thiếu judge'), findsOneWidget);
  });

  testWidgets('409 hiện banner xung đột, Tải lại bỏ sửa chưa lưu', (
    tester,
  ) async {
    await pumpAdmin(tester, putStatus: 409);
    await tester.tap(find.byKey(const Key('theme-t1-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-name')), 'X');
    await tester.tap(find.byKey(const Key('edit-ok')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-conflict')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-reload')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-conflict')), findsNothing);
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('Đã đồng bộ'), findsOneWidget);
  });

  testWidgets('thêm file và bài tập; xoá bài có xác nhận', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('file-f1-add-exercise')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-name')), 'Bài nháp');
    await tester.tap(find.byKey(const Key('edit-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-bai-nhap-open')), findsOneWidget);

    await tester.tap(find.byKey(const Key('exercise-e1-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-e1-open')), findsNothing);
  });

  testWidgets('sơ đồ class: JSON lỗi hiện inline, JSON đúng được áp dụng', (
    tester,
  ) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('theme-t1-diagram')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('theme-t1-diagram-field')),
      '{oops',
    );
    await tester.tap(find.byKey(const Key('theme-t1-diagram-apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('JSON lỗi'), findsOneWidget);
    expect(find.text('Chưa lưu'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('theme-t1-diagram-field')),
      '{"classes": [{"name": "A"}]}',
    );
    await tester.tap(find.byKey(const Key('theme-t1-diagram-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Chưa lưu'), findsOneWidget);
  });

  testWidgets('chạm bài mở form sửa, Áp dụng ghi lại tiêu đề', (tester) async {
    await pumpAdmin(tester);
    await tester.tap(find.byKey(const Key('exercise-e1-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-editor')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ex-title')), 'Sửa');
    await tester.ensureVisible(find.byKey(const Key('exercise-apply')));
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.text('Chưa lưu'), findsOneWidget);
  });

  Future<void> renameTheme(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('theme-t1-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-name')), name);
    await tester.tap(find.byKey(const Key('edit-ok')));
    await tester.pumpAndSettle();
  }

  testWidgets('Hủy sửa khi dirty hỏi xác nhận; Giữ lại không mất sửa', (
    tester,
  ) async {
    await pumpAdmin(tester);
    await renameTheme(tester, 'Tên mới');
    await tester.tap(find.byKey(const Key('admin-discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discard-confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Tên mới'), findsOneWidget);
    expect(find.text('Chưa lưu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-discard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('Đã đồng bộ'), findsOneWidget);
  });

  testWidgets('sửa sau khi 409 vẫn giữ banner xung đột', (tester) async {
    await pumpAdmin(tester, putStatus: 409);
    await renameTheme(tester, 'X');
    await tester.tap(find.byKey(const Key('admin-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-conflict')), findsOneWidget);
    await renameTheme(tester, 'Y');
    expect(find.byKey(const Key('admin-conflict')), findsOneWidget);
  });

  testWidgets('đổi tên rỗng bị bỏ qua', (tester) async {
    await pumpAdmin(tester);
    await renameTheme(tester, '  ');
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('Đã đồng bộ'), findsOneWidget);
  });
}
