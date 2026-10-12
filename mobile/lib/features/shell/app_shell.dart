/// Khung 4 tab (Home / Luyện / Ôn tập / Tiến độ). Dưới [AppBreakpoint.nav]:
/// bottom nav; từ ngưỡng đó: không bottom nav, có top bar ☰ + drawer. Màn chi
/// tiết (theme, topic, bài tập, cell, admin) mở toàn màn, che bottom nav.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../review/review_controller.dart';
import 'app_drawer.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueCardsProvider).length;
    if (MediaQuery.sizeOf(context).width >= AppBreakpoint.nav) {
      return InAppShell(
        child: Scaffold(
          body: Column(
            children: [
              const SafeArea(bottom: false, child: _TopBar()),
              Expanded(child: shell),
            ],
          ),
        ),
      );
    }
    return InAppShell(
      child: Scaffold(
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
      ),
    );
  }
}

/// Thanh mỏng cho màn rộng: ☰ mở drawer + tên app. Đổi sáng/tối nằm ở drawer.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('shell-top-bar'),
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: AppSpace.s2),
          const AppMenuButton(),
          const SizedBox(width: AppSpace.s2),
          Text('Smart Coding Study', style: AppText.label),
        ],
      ),
    );
  }
}
