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

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
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
Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _buildTestRouter(),
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

      final overlapChunksRow = find.byKey(const Key('exercise-overlap-chunks'));
      expect(
        find.descendant(of: overlapChunksRow, matching: find.text('Mới')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'INV-02: markBlockPassed cập nhật UI Home ngay (ref.watch, không cần rebuild thủ công)',
    (tester) async {
      final container = await _pumpApp(tester);
      await tester.pumpAndSettle();

      // Trạng thái ban đầu: split-chunks 2/5 block; theme rag tổng 11 block,
      // đã xong 4 (split-chunks 2 + clean-text 2 + overlap-chunks 0).
      expect(find.text('Tiếp tục Block 3/5'), findsOneWidget);
      expect(find.text('Đã xong 2/5'), findsOneWidget);
      expect(find.text('4/11 block'), findsOneWidget);

      container.read(progressProvider.notifier).markBlockPassed(
        'split-chunks',
        2,
      );
      await tester.pump();

      expect(find.text('Tiếp tục Block 4/5'), findsOneWidget);
      expect(find.text('Đã xong 3/5'), findsOneWidget);
      expect(find.text('5/11 block'), findsOneWidget);
    },
  );
}
