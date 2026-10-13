/// Drawer điều hướng cho màn rộng (>= [AppBreakpoint.nav]): tìm bài, 5 mục
/// chính, mục lục chủ đề → bài, đổi sáng/tối. Mở bằng [showAppDrawer] trên
/// root navigator nên dùng được từ mọi màn (kể cả màn chi tiết không có
/// AppShell); chưa mở thì không có widget nào của drawer trong cây.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/theme_mode.dart';
import '../../data/content_providers.dart';
import '../../domain/models.dart';
import '../exercise/session_providers.dart';
import '../review/review_controller.dart';

// Drawer luôn tối ở cả hai theme (theo mockup).
const _bg = Color(0xFF0F1522);
const _ink = Color(0xFFE8EDF7);
const _inkMuted = Color(0xFF93A0B8);
const _line = Color(0xFF243049);

/// Mở drawer trượt từ trái. Bấm ra ngoài để đóng.
Future<void> showAppDrawer(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Đóng menu',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) =>
        const Align(alignment: Alignment.centerLeft, child: AppDrawer()),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Marker: widget con nằm trong [AppShell] (đã có top bar ☰ riêng), nên
/// `ScreenHeader` không được thêm ☰ thứ hai.
class InAppShell extends InheritedWidget {
  const InAppShell({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InAppShell>() != null;

  @override
  bool updateShouldNotify(InAppShell oldWidget) => false;
}

/// Nút ☰ mở [showAppDrawer].
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key = const Key('menu-button')});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: 'Menu',
      onPressed: () => showAppDrawer(context),
    );
  }
}

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  String _query = '';

  static const _nav = [
    (Icons.home_outlined, 'Home', '/'),
    (Icons.code_outlined, 'Luyện', '/practice'),
    (Icons.style_outlined, 'Ôn tập', '/review'),
    (Icons.insights_outlined, 'Tiến độ', '/stats'),
    (Icons.account_tree_outlined, 'Design', '/design'),
  ];

  /// Đóng drawer rồi chạy [go] bằng router lấy trước khi pop.
  void _navigate(void Function(GoRouter router) go) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    go(router);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final due = ref.watch(dueCardsProvider).length;
    final content = ref.watch(contentIndexProvider);
    final progress = ref.watch(progressProvider);
    final current = ref.watch(inProgressExerciseProvider);
    final query = _query.trim().toLowerCase();

    bool matches(String s) => s.toLowerCase().contains(query);

    final sections = <Widget>[];
    for (final theme in content.themes) {
      final themeHit = matches(theme.name);
      final topicWidgets = <Widget>[];
      for (final topic in theme.allTopics) {
        final topicHit = themeHit || matches(topic.name);
        final rows = [
          for (final file in topic.files)
            for (final e in file.exercises)
              if (query.isEmpty ||
                  topicHit ||
                  matches(e.title) ||
                  matches(e.qualifiedName))
                e,
        ];
        if (rows.isEmpty) continue;
        topicWidgets.add(_label(topic.name, indent: true));
        for (final e in rows) {
          topicWidgets.add(
            _ExerciseTile(
              exercise: e,
              done: progress[e.id]?.passed ?? false,
              current: current?.id == e.id,
              onTap: () => _navigate((r) => r.push('/exercise/${e.id}')),
            ),
          );
        }
      }
      if (topicWidgets.isEmpty) continue;
      sections
        ..add(_label(theme.name))
        ..addAll(topicWidgets);
    }

    return Material(
      color: _bg,
      child: SizedBox(
        width: width * 0.85 < 300 ? width * 0.85 : 300,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            key: const Key('app-drawer'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpace.s4),
                child: TextField(
                  key: const Key('drawer-search'),
                  style: const TextStyle(color: _ink),
                  decoration: InputDecoration(
                    hintText: 'Tìm bài…',
                    hintStyle: const TextStyle(color: _inkMuted),
                    prefixIcon: const Icon(Icons.search, color: _inkMuted),
                    filled: true,
                    fillColor: _line,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              for (var i = 0; i < _nav.length; i++)
                ListTile(
                  key: Key('drawer-nav-$i'),
                  dense: true,
                  leading: Icon(_nav[i].$1, color: _ink),
                  title: Text(
                    _nav[i].$2,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: i == 2 && due > 0
                      ? Badge(label: Text('$due'))
                      : null,
                  onTap: () => _navigate((r) => r.go(_nav[i].$3)),
                ),
              const Divider(color: _line, height: 1),
              Expanded(
                child: sections.isEmpty
                    ? const Center(
                        child: Text(
                          'Không có bài khớp',
                          style: TextStyle(color: _inkMuted),
                        ),
                      )
                    : ListView(children: sections),
              ),
              const Divider(color: _line, height: 1),
              _ThemeRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, {bool indent = false}) => Padding(
    padding: EdgeInsets.fromLTRB(
      indent ? AppSpace.s6 : AppSpace.s4,
      12,
      AppSpace.s4,
      AppSpace.s1,
    ),
    child: Text(
      text,
      style: TextStyle(
        color: _inkMuted,
        fontSize: indent ? 12 : 13,
        fontWeight: FontWeight.w800,
        letterSpacing: indent ? 0 : 0.6,
      ),
    ),
  );
}

class _ExerciseTile extends ConsumerWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.done,
    required this.current,
    required this.onTap,
  });

  final Exercise exercise;
  final bool done;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cùng luật khoá với ExerciseRow: bài đã passed luôn coi là mở.
    final locked = !done && !ref.watch(exerciseUnlockedProvider(exercise.id));
    final p = context.palette;
    return ListTile(
      key: Key('drawer-exercise-${exercise.id}'),
      dense: true,
      contentPadding: const EdgeInsets.only(left: AppSpace.s6 + 4, right: 16),
      selected: current,
      selectedTileColor: _line,
      enabled: !locked,
      leading: Icon(
        locked
            ? Icons.lock_outline
            : done
            ? Icons.check_circle
            : Icons.circle_outlined,
        size: 18,
        color: done ? p.success : _inkMuted,
      ),
      title: Text(
        exercise.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: locked ? _inkMuted : _ink,
          fontWeight: current ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      onTap: locked ? null : onTap,
    );
  }
}

/// Hàng đổi giao diện ở chân drawer. Không dùng [ThemeModeButton] để tránh
/// trùng Key `theme-mode-button` với nút ở top bar/Home.
class _ThemeRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final (icon, label) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto, 'Giao diện: theo hệ thống'),
      ThemeMode.light => (Icons.light_mode, 'Giao diện: sáng'),
      ThemeMode.dark => (Icons.dark_mode, 'Giao diện: tối'),
    };
    return ListTile(
      key: const Key('drawer-theme-toggle'),
      dense: true,
      leading: Icon(icon, color: _ink),
      title: Text(label, style: const TextStyle(color: _ink)),
      onTap: () => ref.read(themeModeProvider.notifier).cycle(),
    );
  }
}
