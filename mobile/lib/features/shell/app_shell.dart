/// Khung 4 tab (Home / Luyện / Ôn tập / Tiến độ) với bottom nav. Màn chi
/// tiết (theme, topic, bài tập, cell, admin) mở toàn màn, che bottom nav.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../review/review_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueCardsProvider).length;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        key: const Key('bottom-nav'),
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.code_outlined),
            selectedIcon: Icon(Icons.code),
            label: 'Luyện',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: due > 0,
              label: Text('$due'),
              child: const Icon(Icons.style_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: due > 0,
              label: Text('$due'),
              child: const Icon(Icons.style),
            ),
            label: 'Ôn tập',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Tiến độ',
          ),
        ],
      ),
    );
  }
}
