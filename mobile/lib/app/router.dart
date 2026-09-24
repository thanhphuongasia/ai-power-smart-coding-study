/// Router của app: Home → Theme detail → Topic detail → Block list → Cell.
library;

import 'package:go_router/go_router.dart';

import '../features/browse/home_screen.dart';
import '../features/browse/theme_detail_screen.dart';
import '../features/browse/topic_detail_screen.dart';
import '../features/exercise/block_list_screen.dart';
import '../features/exercise/cell_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
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
      builder: (context, state) =>
          BlockListScreen(exerciseId: state.pathParameters['exerciseId']!),
    ),
    GoRoute(
      path: '/exercise/:exerciseId/block/:index',
      builder: (context, state) => CellScreen(
        exerciseId: state.pathParameters['exerciseId']!,
        blockIndex: int.parse(state.pathParameters['index']!),
      ),
    ),
  ],
);
