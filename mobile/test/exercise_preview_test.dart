import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/api_client.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'package:smart_coding_study/features/exercise/exercise_screen.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';

import 'support/content_fixture.dart';

const _draftId = 'draft-only-exercise';

/// Content có thêm một bài nháp (clone split-chunks, đổi id/tiêu đề) mà
/// testContent không có.
Content _draftContent() {
  final json = jsonDecode(jsonEncode(contentJson)) as Map<String, dynamic>;
  final ex = Map<String, dynamic>.from(
    (json['exercises'] as Map<String, dynamic>)['split-chunks'] as Map,
  );
  ex['id'] = _draftId;
  ex['title'] = 'Bài nháp chưa duyệt';
  ex['blocks'] = [
    for (final b in ex['blocks'] as List)
      {...(b as Map<String, dynamic>), 'id': '$_draftId-${b['label']}'},
  ];
  (json['exercises'] as Map<String, dynamic>)[_draftId] = ex;
  final themes = json['themes'] as List;
  final file =
      (((themes.firstWhere((t) => t['id'] == 'rag')['topics'] as List).first
                      as Map)['files']
                  as List)
              .first
          as Map<String, dynamic>;
  (file['exercise_ids'] as List).add(_draftId);
  return Content.fromJson(json);
}

const _passedBody = {
  'status': 'passed',
  'tests': [
    {'call': 'f()', 'expected': '1', 'actual': '1', 'passed': true},
  ],
};

class _Harness {
  _Harness(this.requests);
  final List<http.Request> requests;
}

Future<_Harness> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(375, 667);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final requests = <http.Request>[];
  final client = MockClient((req) async {
    requests.add(req);
    return http.Response(
      jsonEncode(_passedBody),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...contentOverrides,
        apiClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: ExercisePreview(content: _draftContent(), exerciseId: _draftId),
      ),
    ),
  );
  await t.pump();
  return _Harness(requests);
}

void main() {
  testWidgets('hiện bài nháp, banner, không khoá', (t) async {
    await _pump(t);
    expect(find.byKey(const Key('preview-banner')), findsOneWidget);
    expect(find.text('Xem trước — chưa duyệt'), findsOneWidget);
    expect(find.text('Bài nháp chưa duyệt'), findsOneWidget);
    expect(find.byKey(const Key('locked-title')), findsNothing);
    expect(find.text('Code 0/3'), findsOneWidget);
  });

  testWidgets('Run gọi /api/admin/run; không có request progress; '
      'passed không có nút bài tiếp; tiến độ thật không bị đụng', (t) async {
    final h = await _pump(t);
    final previewContainer = ProviderScope.containerOf(
      t.element(find.byType(ExerciseScreen)),
    );
    final root = ProviderScope.containerOf(
      t.element(find.byType(ExercisePreview)),
    );
    final ex = _draftContent().exerciseById(_draftId);
    for (final b in ex.blocks) {
      previewContainer
          .read(progressProvider.notifier)
          .saveDraft(_draftId, b.label, b.acceptedAnswers.first);
    }
    await t.pump(const Duration(seconds: 2)); // quá draftSyncDelay
    await t.tap(find.text('Code 3/3'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('run-button')));
    await t.pumpAndSettle();

    final runs = h.requests.where((r) => r.url.path.endsWith('/run')).toList();
    expect(runs, hasLength(1));
    expect(runs.single.url.path, '/api/admin/run');
    expect(runs.single.method, 'POST');
    final body = jsonDecode(runs.single.body) as Map<String, dynamic>;
    expect(body['exercise_id'], _draftId);
    expect(body['code'], isNotEmpty);

    expect(find.byKey(const Key('edit-again')), findsOneWidget);
    expect(find.byKey(const Key('next-exercise')), findsNothing);
    expect(find.byKey(const Key('back-to-list')), findsNothing);

    expect(
      h.requests.where((r) => r.url.path.contains('/api/progress')),
      isEmpty,
    );
    expect(h.requests, hasLength(1)); // chỉ đúng một request: run
    expect(previewContainer.read(progressProvider)[_draftId]!.passed, isTrue);
    expect(root.read(progressProvider).containsKey(_draftId), isFalse);
  });

  testWidgets('editor mở từ preview dùng scope preview: Gợi ý không đụng '
      'tiến độ thật, không gọi /api/progress', (t) async {
    final h = await _pump(t);
    final previewContainer = ProviderScope.containerOf(
      t.element(find.byType(ExerciseScreen)),
    );
    final root = ProviderScope.containerOf(
      t.element(find.byType(ExercisePreview)),
    );
    final rootBefore = root.read(progressProvider);

    await t.tap(find.text('Code 0/3'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cell-A-field')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('editor-hint')), findsOneWidget);
    await t.tap(find.byKey(const Key('editor-hint')));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('editor-hint-0')), findsOneWidget);
    expect(root.read(progressProvider), rootBefore);
    expect(root.read(progressProvider).containsKey(_draftId), isFalse);
    expect(
      previewContainer.read(progressProvider)[_draftId]!.hintsUsed['A'],
      1,
    );
    await t.pump(const Duration(seconds: 2));
    expect(
      h.requests.where((r) => r.url.path.contains('/api/progress')),
      isEmpty,
    );
  });
}
