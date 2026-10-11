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
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/domain/content.dart';
import 'support/content_fixture.dart';

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
      overrides: contentOverrides,
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
        find.descendant(
          of: splitChunksRow,
          matching: find.byKey(const Key('state-started')),
        ),
        findsOneWidget,
      );

      final cleanTextRow = find.byKey(const Key('exercise-clean-text'));
      expect(
        find.descendant(
          of: cleanTextRow,
          matching: find.byKey(const Key('state-done')),
        ),
        findsOneWidget,
      );

      // overlap-chunks đứng sau split-chunks (chưa pass) trong chunker.py.
      final overlapChunksRow = find.byKey(const Key('exercise-overlap-chunks'));
      expect(
        find.descendant(
          of: overlapChunksRow,
          matching: find.byKey(const Key('state-locked')),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Lộ trình module: thanh tiến độ chia đoạn, START ở bài kế tiếp', (
    tester,
  ) async {
    final container = await _pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-rag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-rag-chunking')));
    await tester.pumpAndSettle();

    // Seed: clean-text đã xong, split-chunks đang dở, overlap-chunks khoá.
    final bar = find.byKey(const Key('module-progress'));
    expect(
      find.descendant(of: bar, matching: find.text('1/3')),
      findsOneWidget,
    );
    // START ở bài đầu tiên đã mở mà chưa xong, không ở bài khoá/đã xong.
    expect(find.byKey(const Key('start-split-chunks')), findsOneWidget);
    expect(find.byKey(const Key('start-overlap-chunks')), findsNothing);
    expect(find.byKey(const Key('start-clean-text')), findsNothing);

    // Xong split-chunks → START dời sang overlap-chunks (vừa mở khoá).
    container.read(progressProvider.notifier).markPassed('split-chunks');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: bar, matching: find.text('2/3')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('start-split-chunks')), findsNothing);
    expect(find.byKey(const Key('start-overlap-chunks')), findsOneWidget);

    container.read(progressProvider.notifier).markPassed('overlap-chunks');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: bar, matching: find.text('Hoàn thành')),
      findsOneWidget,
    );
  });

  testWidgets('Lộ trình: sub-module là chặng SAU các file của module', (
    tester,
  ) async {
    await _pumpApp(tester, initialLocation: '/topic/airline-flight');
    await tester.pumpAndSettle();
    final controller = find.byKey(
      const Key('module-airline-flight-controller'),
    );
    // Đầu màn là bài đầu tiên của models/flight.py, chưa thấy chặng sub-module.
    expect(
      find.byKey(const Key('exercise-flight-init')).hitTestable(),
      findsOneWidget,
    );
    expect(controller.hitTestable(), findsNothing);
    // START ở bài kế tiếp; bài đầu file sau đã mở nhưng chưa tới lượt → JUMP.
    expect(find.byKey(const Key('start-flight-init')), findsOneWidget);
    expect(find.byKey(const Key('jump-flight-init')), findsNothing);
    expect(
      find.byKey(const Key('jump-flight-seats-left')),
      findsNothing,
    ); // khoá
    await tester.scrollUntilVisible(
      find.byKey(const Key('jump-flight-service-add')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('JUMP HERE?'), findsWidgets);
    await tester.scrollUntilVisible(
      controller,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(controller, findsOneWidget);
    expect(
      find.byKey(const Key('module-airline-flight-schedule')),
      findsOneWidget,
    );
  });

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
    // Bài khoá: thẻ chỉ báo cần làm bài trước, không có nút mở.
    expect(find.byKey(const Key('exercise-page-overlap-chunks')), findsNothing);
    expect(find.text('Hoàn thành bài trước để mở'), findsOneWidget);
    expect(find.byKey(const Key('lesson-go-overlap-chunks')), findsNothing);

    container.read(progressProvider.notifier).markPassed('split-chunks');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('exercise-split-chunks')),
        matching: find.byKey(const Key('state-done')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: locked, matching: find.byKey(const Key('state-new'))),
      findsOneWidget,
    );
    // Đã mở: thẻ có nút "Bắt đầu" → vào bài.
    expect(find.byKey(const Key('lesson-go-overlap-chunks')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('lesson-go-overlap-chunks')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lesson-go-overlap-chunks')));
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
    // Mục "Đã xong" nằm cuối danh sách lazy (sau mọi bài mới) → cuộn tới.
    await tester.scrollUntilVisible(
      find.byKey(const Key('practice-split-chunks')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('practice-split-chunks')),
        matching: find.text('Đã xong'),
      ),
      findsOneWidget,
    );
  });

  group('module lồng nhau', () {
    Map<String, dynamic> ex(String id, String? cls) => {
      'id': id,
      'title': id,
      'function_name': 'search',
      'class_name': cls,
      'params': <String>[],
      'template': '',
      'challenge': {
        'statement': '',
        'motivation': '',
        'small': {'caption': '', 'input': '', 'output': '', 'note': null},
        'project': {'caption': '', 'input': '', 'output': '', 'note': null},
      },
      'blocks': <Map<String, dynamic>>[],
    };

    final nested = Content.fromJson({
      'version': 'n1',
      'themes': [
        {
          'id': 'th',
          'name': 'Airline',
          'description': '',
          'tags': <String>[],
          'topics': [
            {
              'id': 'booking',
              'name': 'Booking',
              'description': '',
              'files': <Map<String, dynamic>>[],
              'modules': [
                {
                  'id': 'search-mod',
                  'name': 'Search',
                  'description': 'Tìm chuyến bay',
                  'files': [
                    {
                      'id': 'f-svc',
                      'name': 'service.py',
                      'exercise_ids': ['e1', 'e2'],
                    },
                  ],
                  'modules': <Map<String, dynamic>>[],
                },
              ],
            },
          ],
        },
      ],
      'exercises': {
        'e1': ex('e1', 'FlightService'),
        'e2': ex('e2', 'FlightService'),
      },
    });

    Future<void> pumpNested(WidgetTester tester, String location) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [contentIndexProvider.overrideWithValue(nested)],
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: _buildTestRouter(location),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Theme card đếm cả bài trong module con', (tester) async {
      await pumpNested(tester, '/theme/th');
      expect(
        find.descendant(
          of: find.byKey(const Key('topic-booking')),
          matching: find.text('2 bài tập'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Topic -> module con: breadcrumb, header class, tên đầy đủ', (
      tester,
    ) async {
      await pumpNested(tester, '/topic/booking');
      final card = find.byKey(const Key('module-search-mod'));
      expect(card, findsOneWidget);

      expect(
        find.descendant(of: card, matching: find.text('2 bài tập')),
        findsOneWidget,
      );

      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(find.text('Airline › Booking › Search'), findsOneWidget);
      // Hai bài liên tiếp cùng class -> một header duy nhất.
      expect(
        find.byKey(const Key('class-f-svc-FlightService')),
        findsOneWidget,
      );
      expect(find.text('class FlightService'), findsOneWidget);
      // Hai bài là hai nút trên lộ trình; chạm nút → thẻ hiện tên đầy đủ.
      expect(find.byKey(const Key('exercise-e1')), findsOneWidget);
      expect(find.byKey(const Key('exercise-e2')), findsOneWidget);
      await tester.tap(find.byKey(const Key('exercise-e1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('FlightService.search() · '), findsOneWidget);
    });
  });
}
