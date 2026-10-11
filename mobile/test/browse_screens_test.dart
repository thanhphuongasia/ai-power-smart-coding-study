// Test cho 3 màn browse (Home, Theme detail, Topic detail). Dựng một
// GoRouter tối thiểu riêng cho test (route exercise chỉ là Placeholder có
// Key nhận diện) — T-06 (router thật của app) chạy song song, không phụ
// thuộc vào nó ở đây.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/browse/home_screen.dart';
import 'package:smart_coding_study/features/browse/theme_detail_screen.dart';
import 'package:smart_coding_study/features/browse/topic_detail_screen.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/practice/practice_screen.dart';

GoRouter _buildTestRouter([String initialLocation = '/']) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/practice',
        builder: (context, state) => const PracticeScreen(),
      ),
      GoRoute(
        path: '/theme/:themeId',
        builder: (context, state) =>
            ThemeDetailScreen(state.pathParameters['themeId']!),
      ),
      GoRoute(
        path: '/topic/:topicId',
        builder: (context, state) =>
            TopicDetailScreen(state.pathParameters['topicId']!),
      ),
      GoRoute(
        path: '/exercise/:exerciseId',
        builder: (context, state) => Placeholder(
          key: Key('exercise-page-${state.pathParameters['exerciseId']}'),
        ),
      ),
    ],
  );
}

/// Dựng app tối thiểu, trả về [ProviderContainer] thật (để test đổi
/// progress từ bên ngoài, giống việc quay lại từ block làm bài).
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  String initialLocation = '/',
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _buildTestRouter(initialLocation),
          );
        },
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('Home: continue-card chạm tới đúng trang exercise', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('continue-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue-card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise-page-split-chunks')), findsOneWidget);
  });

  testWidgets(
    'Home -> Theme detail -> Topic detail: trạng thái exercise hiện đúng chữ',
    (tester) async {
      await _pumpApp(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('theme-rag')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('topic-rag-chunking')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('exercise-split-chunks')), findsOneWidget);

      final splitChunksRow = find.byKey(const Key('exercise-split-chunks'));
      expect(
        find.descendant(of: splitChunksRow, matching: find.text('Đang dở')),
        findsOneWidget,
      );

      final cleanTextRow = find.byKey(const Key('exercise-clean-text'));
      expect(
        find.descendant(of: cleanTextRow, matching: find.text('Đã xong')),
        findsOneWidget,
      );

      // overlap-chunks đứng sau split-chunks (chưa pass) trong chunker.py.
      final overlapChunksRow = find.byKey(const Key('exercise-overlap-chunks'));
      expect(
        find.descendant(of: overlapChunksRow, matching: find.text('Khoá')),
        findsOneWidget,
      );
    },
  );

  testWidgets('INV-08: row khoá không điều hướng; pass bài trước thì mở', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-rag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-rag-chunking')));
    await tester.pumpAndSettle();

    final locked = find.byKey(const Key('exercise-overlap-chunks'));
    await tester.tap(locked);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-page-overlap-chunks')), findsNothing);
    expect(locked, findsOneWidget);
    expect(find.byTooltip('Hoàn thành bài trước để mở'), findsOneWidget);

    container.read(progressProvider.notifier).markPassed('split-chunks');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('exercise-split-chunks')),
        matching: find.text('Đã xong'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: locked, matching: find.text('Mới')),
      findsOneWidget,
    );
    await tester.tap(locked);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('exercise-page-overlap-chunks')),
      findsOneWidget,
    );
  });

  testWidgets(
    'INV-02/06: markPassed cập nhật UI Home ngay (ref.watch, không cần rebuild thủ công)',
    (tester) async {
      final container = await _pumpApp(tester);
      await tester.pumpAndSettle();

      // Ban đầu chỉ clean-text (1 ô) đã passed; theme rag tổng 7 ô
      // (split-chunks 3 + overlap-chunks 3 + clean-text 1).
      expect(find.byKey(const Key('continue-card')), findsOneWidget);
      expect(find.text('1/7 block'), findsOneWidget);

      container.read(progressProvider.notifier).markPassed('split-chunks');
      await tester.pump();

      // Pass cả bài: bài không còn "đang dở", cả 3 ô tính xong.
      expect(find.byKey(const Key('continue-card')), findsNothing);
      expect(find.text('4/7 block'), findsOneWidget);
    },
  );

  testWidgets('Home: continue card hiện tên bài + số ô đã viết, hết khi pass', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('continue-card'));
    expect(
      find.descendant(of: card, matching: find.textContaining('Tiếp tục: ')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('1/3 ô đã viết')),
      findsOneWidget,
    );
    expect(find.textContaining('Block '), findsNothing);

    container.read(progressProvider.notifier).markPassed('split-chunks');
    await tester.pump();
    expect(card, findsNothing);
  });

  testWidgets('Practice: draft -> Đang dở, passed -> Đã xong (INV-09)', (
    tester,
  ) async {
    final container = await _pumpApp(tester, initialLocation: '/practice');
    await tester.pumpAndSettle();

    final inProgress = find.textContaining('Đang dở · ');
    expect(inProgress, findsOneWidget);
    expect(find.byKey(const Key('practice-split-chunks')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-split-chunks')),
        matching: find.text('Đang dở'),
      ),
      findsOneWidget,
    );

    container.read(progressProvider.notifier).markPassed('split-chunks');
    await tester.pumpAndSettle();
    expect(find.textContaining('Đang dở · '), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-split-chunks')),
        matching: find.text('Đã xong'),
      ),
      findsOneWidget,
    );
  });
}
