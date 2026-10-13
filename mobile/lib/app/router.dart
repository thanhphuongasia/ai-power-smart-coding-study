/// Router của app: 5 tab trong shell (Home / Luyện / Ôn tập / Tiến độ / Design); các
/// màn chi tiết Theme → Topic → Exercise, File cross-cut và Admin
/// mở trên navigator gốc (toàn màn, không có bottom nav).
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/account/change_password_screen.dart';
import '../features/admin/admin_module_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/admin/admin_theme_screen.dart';
import '../features/admin/exercise_editor.dart';
import '../features/admin/review_detail_screen.dart';
import '../features/admin/review_screen.dart' as admin_review;
import '../features/browse/file_crosscut_screen.dart';
import '../features/browse/home_screen.dart';
import '../features/browse/theme_detail_screen.dart';
import '../features/browse/topic_detail_screen.dart';
import '../features/exercise/exercise_screen.dart';
import '../features/practice/practice_screen.dart';
import '../features/review/review_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/stats/stats_screen.dart';
import '../features/system_design/context_screen.dart';
import '../features/system_design/reader_screen.dart';
import '../features/system_design/sd_docs_screen.dart';
import '../features/system_design/sd_path_screen.dart';
import '../features/system_design/task_screen.dart';

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
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/design',
              builder: (context, state) => const SdDocsScreen(),
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
      path: '/design/:docId',
      builder: (context, state) =>
          SdPathScreen(docId: state.pathParameters['docId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/design/:docId/read',
      builder: (context, state) => SdReaderScreen(
        docId: state.pathParameters['docId']!,
        sectionId: state.uri.queryParameters['section'],
      ),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/design/:docId/context',
      builder: (context, state) =>
          SdContextScreen(docId: state.pathParameters['docId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/design/:docId/tasks/:taskId',
      builder: (context, state) => SdTaskScreen(
        docId: state.pathParameters['docId']!,
        taskId: state.pathParameters['taskId']!,
      ),
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
      path: '/account/password',
      builder: (context, state) => const ChangePasswordScreen(),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/admin',
      builder: (context, state) => const AdminScreen(),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/admin/review',
      builder: (context, state) => const admin_review.AdminReviewScreen(),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/admin/review/:id',
      builder: (context, state) => AdminReviewDetailScreen(
        changeId: int.tryParse(state.pathParameters['id']!) ?? -1,
      ),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/admin/theme/:themeId',
      builder: (context, state) =>
          AdminThemeScreen(themeId: state.pathParameters['themeId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/admin/module/:moduleId',
      builder: (context, state) =>
          AdminModuleScreen(moduleId: state.pathParameters['moduleId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/admin/exercise/:id',
      builder: (context, state) =>
          ExerciseEditorScreen(exerciseId: state.pathParameters['id']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootKey,
      path: '/exercise/:exerciseId',
      builder: (context, state) =>
          ExerciseScreen(exerciseId: state.pathParameters['exerciseId']!),
    ),
  ],
);
