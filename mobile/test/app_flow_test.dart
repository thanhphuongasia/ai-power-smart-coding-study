/// Test luồng end-to-end qua mối nối (INV-06/08): bắt đầu từ Home (không mở
/// thẳng route) → vào split-chunks trong ≤2 chạm → tab Code → 3 ô → Run
/// (judge giả trả passed) → split-chunks "Đã xong", overlap-chunks hết khoá.
///
/// clockProvider bị override bằng đồng hồ giả: Timer.periodic của phiên chạy
/// trong FakeAsync của testWidgets, còn `DateTime.now()` thật thì không.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/router.dart';
import 'package:smart_coding_study/data/judge_client.dart';
import 'support/auth_fixture.dart';
import 'support/content_fixture.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/main.dart';

class _FakeJudge implements JudgeClient {
  final List<String> calls = [];

  @override
  Future<JudgeResult> run(String exerciseId, String code) async {
    calls.add(code);
    return const JudgeResult(
      status: JudgeStatus.passed,
      tests: [
        JudgeTest(
          call: "split_chunks('abcd', 2)",
          expected: "['ab', 'cd']",
          actual: "['ab', 'cd']",
          passed: true,
        ),
      ],
    );
  }
}

/// Trạng thái nút `id` trên lộ trình module (Đã xong / Đang dở / Mới / Khoá).
Finder _status(String id, String text) => find.descendant(
  of: find.byKey(Key('exercise-$id')),
  matching: find.byKey(
    Key(
      'state-${const {'Đã xong': 'done', 'Đang dở': 'started', 'Mới': 'new', 'Khoá': 'locked'}[text]}',
    ),
  ),
);

void main() {
  testWidgets('Home → continue-card → tab Code → gõ 3 ô → Run passed → '
      'split-chunks Đã xong, overlap-chunks mở khoá', (tester) async {
    final judge = _FakeJudge();
    final clock = DateTime(2024, 1, 1, 9);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    appRouter.go('/');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...contentOverrides,
          ...authOverrides(),
          clockProvider.overrideWithValue(() => clock),
          judgeClientProvider.overrideWithValue(judge),
        ],
        child: const SmartCodingStudyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Bắt đầu ở Home.
    expect(find.byKey(const Key('continue-card')), findsOneWidget);

    // Chạm 1: continue-card → ExerciseScreen. Bài có draft nên mở thẳng
    // tab Code.
    await tester.tap(find.byKey(const Key('continue-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-title')), findsOneWidget);
    expect(find.byKey(const Key('run-button')), findsOneWidget);

    // Draft seed đã có ô A đúng ⇒ A thu gọn, B mở. Chạm B → màn soạn toàn
    // màn hình; gõ B đúng thì màn tự sang C, gõ C đúng thì tự đóng.
    final exercise = testContent.exerciseById('split-chunks');
    expect(find.byKey(const Key('cell-A-collapsed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cell-B-field')));
    await tester.pumpAndSettle();
    for (final b in exercise.blocks.skip(1)) {
      await tester.enterText(
        find.byKey(const Key('editor-field')),
        b.acceptedAnswers.first,
      );
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('editor-field')), findsNothing);

    await tester.tap(find.byKey(const Key('run-button')));
    await tester.pumpAndSettle();
    expect(judge.calls, hasLength(1));
    expect(find.byKey(const Key('next-exercise')), findsOneWidget);

    // Về Home: bài đã xong nên không còn "đang dở".
    await tester.tap(find.byKey(const Key('exercise-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('continue-card')), findsNothing);

    // Topic Chunking: split-chunks Đã xong, overlap-chunks không còn khoá.
    await tester.tap(find.byKey(const Key('theme-rag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-rag-chunking')));
    await tester.pumpAndSettle();
    expect(_status('split-chunks', 'Đã xong'), findsOneWidget);
    expect(_status('overlap-chunks', 'Khoá'), findsNothing);
    expect(_status('overlap-chunks', 'Mới'), findsOneWidget);

    // Dọn timer debounce 5s của flutter_code_editor.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  });
}
