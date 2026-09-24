/// Router của app: 4 tab trong shell (Home / Luyện / Ôn tập / Tiến độ); các
/// màn chi tiết Theme → Topic → Block list → Cell, File cross-cut và Admin
/// mở trên navigator gốc (toàn màn, không có bottom nav).
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_screen.dart';
import '../features/browse/file_crosscut_screen.dart';
import '../features/browse/home_screen.dart';
import '../features/browse/theme_detail_screen.dart';
import '../features/browse/topic_detail_screen.dart';
import '../features/exercise/block_list_screen.dart';
import '../features/exercise/cell_screen.dart';
import '../features/practice/practice_screen.dart';
import '../features/review/review_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/stats/stats_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/practice',
              builder: (context, state) => const PracticeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/review',
              builder: (context, state) => const ReviewScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/stats',
              builder: (context, state) => const StatsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/theme/:themeId',
      builder: (context, state) =>
          ThemeDetailScreen(state.pathParameters['themeId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/topic/:topicId',
      builder: (context, state) =>
          TopicDetailScreen(state.pathParameters['topicId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/file/:fileName',
      builder: (context, state) =>
          FileCrossCutScreen(state.pathParameters['fileName']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/admin',
      builder: (context, state) => const AdminScreen(),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/exercise/:exerciseId',
      builder: (context, state) =>
          BlockListScreen(exerciseId: state.pathParameters['exerciseId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/exercise/:exerciseId/block/:index',
      builder: (context, state) => CellScreen(
        exerciseId: state.pathParameters['exerciseId']!,
        blockIndex: int.parse(state.pathParameters['index']!),
      ),
    ),
  ],
);
