import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/data/admin_repository.dart';
import 'package:smart_coding_study/features/admin/admin_controller.dart';
import 'package:smart_coding_study/features/admin/admin_widgets.dart';
import 'package:smart_coding_study/main.dart';

import 'admin_controller_test.dart' show jsonResponse, sampleContent;
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';

/// Mở app thật ở Home (admin), trả danh sách request gửi tới server admin.
Future<List<http.Request>> pumpFromHome(
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
  await tester.tap(find.byKey(const Key('admin-button')));
  await tester.pumpAndSettle();
  return requests;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> toModule(WidgetTester tester) async {
  await tapKey(tester, 'theme-t1-card');
  await tapKey(tester, 'module-m1-card');
}

AdminState adminState(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MaterialApp)),
).read(adminProvider);

Future<void> renameTheme(WidgetTester tester, String name) async {
  await tapKey(tester, 'theme-t1-menu');
  await tapKey(tester, 'theme-t1-menu-rename');
  await tester.enterText(find.byKey(const Key('edit-name')), name);
  await tester.tap(find.byKey(const Key('edit-ok')));
  await tester.pumpAndSettle();
}

void main() {
  test('exerciseIdsWithErrors lấy id từ lỗi "bài <id>: …"', () {
    expect(
      exerciseIdsWithErrors([
        'bài e1: thiếu judge',
        'bài  e2 : sai case',
        'bài e1: lỗi khác',
        'theme t1: thiếu tên',
        'e3: không có tiền tố',
      ]),
      {'e1', 'e2'},
    );
    expect(exerciseIdsWithErrors(const []), isEmpty);
  });

  test('exerciseIdsWithErrors nhận lỗi cấp ô và hậu tố "(bài <id>)"', () {
    expect(exerciseIdsWithErrors(['bài e1 ô A: cần ít nhất 1 đáp án']), {'e1'});
    expect(exerciseIdsWithErrors(['theme t1: sơ đồ: thiếu class C (bài e2)']), {
      'e2',
    });
    expect(
      exerciseIdsWithErrors([
        'bài e1: lỗi',
        'bài e3 ô B: sai',
        'theme t1: sơ đồ: thiếu class D (bài e4)',
        'theme t1: sơ đồ: thiếu class D',
      ]),
      {'e1', 'e3', 'e4'},
    );
  });

  testWidgets('từ Home 1 chạm tới danh sách project; không hiện version', (
    tester,
  ) async {
    await pumpFromHome(tester);
    expect(find.byKey(const Key('admin-tree')), findsOneWidget);
    expect(find.byKey(const Key('theme-t1-card')), findsOneWidget);
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('1 module · 2 bài'), findsOneWidget);
    expect(find.textContaining('v1'), findsNothing);
    expect(find.byKey(const Key('breadcrumb-projects')), findsOneWidget);
    expect(find.text('Đã đồng bộ'), findsOneWidget);
  });

  testWidgets('đi xuống project → module: thấy nhóm file và thẻ bài', (
    tester,
  ) async {
    await pumpFromHome(tester);
    await tapKey(tester, 'theme-t1-card');
    expect(find.byKey(const Key('module-m1-card')), findsOneWidget);
    expect(find.text('1 file · 2 bài'), findsOneWidget);
    expect(find.byKey(const Key('breadcrumb-theme')), findsOneWidget);

    await tapKey(tester, 'module-m1-card');
    expect(find.byKey(const Key('file-f1-group')), findsOneWidget);
    expect(find.byKey(const Key('exercise-e1-card')), findsOneWidget);
    expect(find.byKey(const Key('exercise-e2-card')), findsOneWidget);
    expect(find.text('a.py'), findsOneWidget);
    expect(find.text('0 ô'), findsNWidgets(2));
    expect(find.byKey(const Key('add-file')), findsOneWidget);
  });

  testWidgets('đổi tên project → dirty → Lưu gửi base_version', (tester) async {
    final requests = await pumpFromHome(tester);
    await renameTheme(tester, 'Tên mới');
    expect(find.text('Tên mới'), findsOneWidget);
    expect(find.text('● Chưa lưu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-save')));
    await tester.pumpAndSettle();
    final put = requests.last;
    expect(put.method, 'PUT');
    expect((jsonDecode(put.body) as Map)['base_version'], 'v1');
    expect(find.text('Đã đồng bộ'), findsOneWidget);
    expect(find.text('Đã lưu'), findsOneWidget);
  });

  testWidgets('thêm project qua nút "+ Thêm project"', (tester) async {
    await pumpFromHome(tester);
    await tapKey(tester, 'add-theme');
    await tester.enterText(find.byKey(const Key('edit-name')), 'Airline');
    await tester.tap(find.byKey(const Key('edit-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-airline-card')), findsOneWidget);
    expect(find.text('● Chưa lưu'), findsOneWidget);
  });

  testWidgets(
    '422 lỗi "bài <id>": chấm đỏ ở project, module, bài; sheet liệt kê',
    (tester) async {
      await pumpFromHome(
        tester,
        validateBody: {
          'ok': false,
          'errors': ['bài e1: thiếu judge'],
        },
      );
      expect(find.byKey(const Key('theme-t1-error')), findsNothing);
      await tester.tap(find.byKey(const Key('admin-validate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme-t1-error')), findsOneWidget);

      await tapKey(tester, 'theme-t1-card');
      expect(find.byKey(const Key('module-m1-error')), findsOneWidget);

      await tapKey(tester, 'module-m1-card');
      expect(find.byKey(const Key('exercise-e1-error')), findsOneWidget);
      expect(find.byKey(const Key('exercise-e2-error')), findsNothing);

      expect(find.text('1 lỗi'), findsOneWidget);
      await tapKey(tester, 'admin-error-chip');
      expect(find.byKey(const Key('admin-errors')), findsOneWidget);
      expect(find.text('• bài e1: thiếu judge'), findsOneWidget);
    },
  );

  testWidgets('422 lỗi cấp ô "bài e1 ô A: …" vẫn chấm đỏ ở bài và module', (
    tester,
  ) async {
    await pumpFromHome(
      tester,
      validateBody: {
        'ok': false,
        'errors': ['bài e1 ô A: cần ít nhất 1 đáp án'],
      },
    );
    await tester.tap(find.byKey(const Key('admin-validate')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'theme-t1-card');
    expect(find.byKey(const Key('module-m1-error')), findsOneWidget);
    await tapKey(tester, 'module-m1-card');
    expect(find.byKey(const Key('exercise-e1-error')), findsOneWidget);
    expect(find.byKey(const Key('exercise-e2-error')), findsNothing);
  });

  testWidgets('409 hiện banner xung đột, Tải lại bỏ sửa chưa lưu', (
    tester,
  ) async {
    await pumpFromHome(tester, putStatus: 409);
    await renameTheme(tester, 'X');
    await tester.tap(find.byKey(const Key('admin-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-conflict')), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-reload')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-conflict')), findsNothing);
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('Đã đồng bộ'), findsOneWidget);
  });

  testWidgets('Hủy sửa (menu) hỏi xác nhận; Giữ lại không mất sửa', (
    tester,
  ) async {
    await pumpFromHome(tester);
    await renameTheme(tester, 'Tên mới');
    await tapKey(tester, 'admin-more');
    await tapKey(tester, 'admin-discard');
    expect(find.byKey(const Key('discard-confirm')), findsOneWidget);
    await tapKey(tester, 'discard-cancel');
    expect(find.text('Tên mới'), findsOneWidget);
    expect(find.text('● Chưa lưu'), findsOneWidget);

    await tapKey(tester, 'admin-more');
    await tapKey(tester, 'admin-discard');
    await tapKey(tester, 'discard-confirm');
    expect(find.text('Theme 1'), findsOneWidget);
    expect(find.text('Đã đồng bộ'), findsOneWidget);
  });

  testWidgets('thêm bài qua dialog (hàm + class) rồi mở editor', (
    tester,
  ) async {
    await pumpFromHome(tester);
    await toModule(tester);
    await tapKey(tester, 'file-f1-add-exercise');
    await tester.enterText(
      find.byKey(const Key('add-exercise-title')),
      'Bài nháp',
    );
    await tester.enterText(find.byKey(const Key('add-exercise-fn')), 'tinh');
    await tester.enterText(
      find.byKey(const Key('add-exercise-class')),
      'MayTinh',
    );
    await tester.tap(find.byKey(const Key('add-exercise-ok')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise-editor')), findsOneWidget);
    final ex = adminState(tester).exercises['bai-nhap'] as Map;
    expect(ex['function_name'], 'tinh');
    expect(ex['class_name'], 'MayTinh');
    expect(adminState(tester).dirty, isTrue);
  });

  testWidgets('thêm bài không class → hàm top-level', (tester) async {
    await pumpFromHome(tester);
    await toModule(tester);
    await tapKey(tester, 'file-f1-add-exercise');
    await tester.enterText(find.byKey(const Key('add-exercise-title')), 'Hai');
    await tester.enterText(find.byKey(const Key('add-exercise-fn')), 'go');
    await tester.tap(find.byKey(const Key('add-exercise-ok')));
    await tester.pumpAndSettle();
    final ex = adminState(tester).exercises['hai'] as Map;
    expect(ex['function_name'], 'go');
    expect(ex['class_name'], isNull);
  });

  testWidgets('xoá bài có xác nhận', (tester) async {
    await pumpFromHome(tester);
    await toModule(tester);
    await tapKey(tester, 'exercise-e1-menu');
    await tapKey(tester, 'exercise-e1-menu-delete');
    expect(find.byKey(const Key('delete-confirm')), findsOneWidget);
    await tapKey(tester, 'delete-confirm');
    expect(find.byKey(const Key('exercise-e1-card')), findsNothing);
    expect(find.byKey(const Key('exercise-e2-card')), findsOneWidget);
    expect(find.text('● Chưa lưu'), findsOneWidget);
  });

  testWidgets('thêm file và module con ở cấp module', (tester) async {
    await pumpFromHome(tester);
    await toModule(tester);
    await tapKey(tester, 'add-file');
    await tester.enterText(find.byKey(const Key('edit-name')), 'b.py');
    await tester.tap(find.byKey(const Key('edit-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('file-m1-b-py-group')), findsOneWidget);

    await tapKey(tester, 'add-module');
    await tester.enterText(find.byKey(const Key('edit-name')), 'Con');
    await tester.tap(find.byKey(const Key('edit-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('module-m1-con-card')), findsOneWidget);
    await tapKey(tester, 'module-m1-con-card');
    expect(find.byKey(const Key('breadcrumb-module-m1')), findsOneWidget);
  });

  testWidgets('sơ đồ class: JSON lỗi hiện inline, JSON đúng được áp dụng', (
    tester,
  ) async {
    await pumpFromHome(tester);
    await tapKey(tester, 'theme-t1-diagram');
    await tester.enterText(
      find.byKey(const Key('theme-t1-diagram-field')),
      '{oops',
    );
    await tester.tap(find.byKey(const Key('theme-t1-diagram-apply')));
    await tester.pumpAndSettle();
    expect(find.textContaining('JSON lỗi'), findsOneWidget);
    expect(find.text('● Chưa lưu'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('theme-t1-diagram-field')),
      '{"classes": [{"name": "A"}]}',
    );
    await tester.tap(find.byKey(const Key('theme-t1-diagram-apply')));
    await tester.pumpAndSettle();
    expect(find.text('● Chưa lưu'), findsOneWidget);
  });

  testWidgets('chạm thẻ bài mở form sửa, Áp dụng ghi lại tiêu đề', (
    tester,
  ) async {
    await pumpFromHome(tester);
    await toModule(tester);
    await tapKey(tester, 'exercise-e1-card');
    expect(find.byKey(const Key('exercise-editor')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ex-title')), 'Sửa');
    await tester.ensureVisible(find.byKey(const Key('exercise-apply')));
    await tester.tap(find.byKey(const Key('exercise-apply')));
    await tester.pumpAndSettle();
    expect(adminState(tester).dirty, isTrue);
    expect((adminState(tester).exercises['e1'] as Map)['title'], 'Sửa');
  });

  testWidgets('breadcrumb đưa về đúng cấp', (tester) async {
    await pumpFromHome(tester);
    await toModule(tester);
    expect(find.byKey(const Key('file-f1-group')), findsOneWidget);

    await tapKey(tester, 'breadcrumb-theme');
    expect(find.byKey(const Key('module-m1-card')), findsOneWidget);
    expect(find.byKey(const Key('file-f1-group')), findsNothing);

    await tapKey(tester, 'module-m1-card');
    await tapKey(tester, 'breadcrumb-projects');
    expect(find.byKey(const Key('admin-tree')), findsOneWidget);
    expect(find.byKey(const Key('theme-t1-card')), findsOneWidget);
    expect(find.byKey(const Key('module-m1-card')), findsNothing);
  });

  testWidgets('deep link module: breadcrumb theme/projects dùng go()', (
    tester,
  ) async {
    await pumpFromHome(tester);
    appRouter.go('/admin/module/m1');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('file-f1-group')), findsOneWidget);

    await tapKey(tester, 'breadcrumb-theme');
    expect(find.byKey(const Key('module-m1-card')), findsOneWidget);
    expect(find.byKey(const Key('file-f1-group')), findsNothing);

    appRouter.go('/admin/module/m1');
    await tester.pumpAndSettle();
    await tapKey(tester, 'breadcrumb-projects');
    expect(find.byKey(const Key('admin-tree')), findsOneWidget);
  });

  testWidgets('deep link module: nút back lên theme cha, không về Home', (
    tester,
  ) async {
    await pumpFromHome(tester);
    appRouter.go('/admin/module/m1');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('module-m1-card')), findsOneWidget);
    expect(find.byKey(const Key('admin-button')), findsNothing);

    // Deep link theme → back về danh sách project.
    appRouter.go('/admin/theme/t1');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-tree')), findsOneWidget);
  });

  testWidgets('breadcrumb cao tối thiểu 40px', (tester) async {
    await pumpFromHome(tester);
    await tapKey(tester, 'theme-t1-card');
    final size = tester.getSize(find.byKey(const Key('breadcrumb-projects')));
    expect(size.height, greaterThanOrEqualTo(40));
  });

  testWidgets('nút thêm không lặp dấu "+" trong label', (tester) async {
    await pumpFromHome(tester);
    expect(find.text('Thêm project'), findsOneWidget);
    expect(find.textContaining('+ '), findsNothing);
  });

  testWidgets('thêm bài: tiêu đề rỗng và tên không hợp lệ hiện lỗi inline', (
    tester,
  ) async {
    await pumpFromHome(tester);
    await toModule(tester);
    await tapKey(tester, 'file-f1-add-exercise');
    expect(find.text('vd: Còn bao nhiêu ghế trống'), findsOneWidget);
    await tapKey(tester, 'add-exercise-ok');
    expect(find.byKey(const Key('add-exercise-ok')), findsOneWidget);
    expect(find.text('Cần nhập tiêu đề'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('add-exercise-title')), 'X');
    await tester.enterText(find.byKey(const Key('add-exercise-fn')), '1abc');
    await tester.enterText(find.byKey(const Key('add-exercise-class')), 'a b');
    await tester.tap(find.byKey(const Key('add-exercise-ok')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tên hàm phải là'), findsOneWidget);
    expect(find.textContaining('Tên class phải là'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('add-exercise-fn')), 'ok_fn');
    await tester.enterText(find.byKey(const Key('add-exercise-class')), '');
    await tester.tap(find.byKey(const Key('add-exercise-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-editor')), findsOneWidget);
  });
}
