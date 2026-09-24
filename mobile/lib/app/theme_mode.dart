/// Chế độ sáng/tối của app: theo hệ thống → sáng → tối → theo hệ thống.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Chuyển sang chế độ kế tiếp trong vòng system → light → dark.
  void cycle() {
    state = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Nút trên thanh tiêu đề để đổi chế độ sáng/tối. Icon cho biết chế độ
/// hiện tại, tooltip nói chế độ sẽ chuyển sang.
class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final (icon, current, next) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto, 'theo hệ thống', 'sáng'),
      ThemeMode.light => (Icons.light_mode, 'sáng', 'tối'),
      ThemeMode.dark => (Icons.dark_mode, 'tối', 'theo hệ thống'),
    };
    return IconButton(
      key: const Key('theme-mode-button'),
      icon: Icon(icon),
      tooltip: 'Giao diện $current · chạm để chuyển sang $next',
      onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
    );
  }
}
