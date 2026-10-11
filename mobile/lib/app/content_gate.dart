/// Cổng nội dung: chỉ dựng giao diện app khi đã có nội dung (mạng hoặc cache).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_providers.dart';
import '../data/content_repository.dart';
import 'theme.dart';
import 'theme_mode.dart';

class ContentGate extends ConsumerWidget {
  const ContentGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contentProvider);
    final load = async.value; // giữ giá trị cũ khi đang refresh
    if (load == null) {
      final error = async.error;
      if (error != null) {
        return _Shell(
          child: _ErrorView(
            message: error is ContentUnavailable
                ? error.reason
                : 'Không tải được nội dung.',
            onRetry: () => ref.read(contentProvider.notifier).refresh(),
          ),
        );
      }
      return const _Shell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang tải nội dung'),
          ],
        ),
      );
    }
    // Cấu trúc cây CỐ ĐỊNH ở cả hai nguồn: `child` luôn ở cùng vị trí (ô thứ 2 của Column),
    // chỉ ô banner đổi giữa banner và SizedBox. Nhờ vậy "Thử lại" thành công (cache →
    // network) không unmount app, người học không mất chữ đang gõ.
    final fromCache = load.source == ContentSource.cache;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery.fromView(
        view: View.of(context),
        child: Column(
          children: [
            fromCache
                ? _CacheBanner(
                    loading: async.isLoading,
                    onRetry: () => ref.read(contentProvider.notifier).refresh(),
                  )
                : const SizedBox.shrink(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                // Banner đã chiếm vùng status bar; app bên dưới không chừa thêm.
                removeTop: fromCache,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Palette theo lựa chọn sáng/tối của app; "theo hệ thống" thì theo độ sáng nền tảng.
AppPalette _paletteFor(BuildContext context, ThemeMode mode) {
  final dark = switch (mode) {
    ThemeMode.light => false,
    ThemeMode.dark => true,
    ThemeMode.system =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark,
  };
  return dark ? AppPalette.dark : AppPalette.light;
}

class _CacheBanner extends ConsumerWidget {
  const _CacheBanner({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final palette = _paletteFor(context, mode);
    final theme = buildAppTheme(
      brightness: palette == AppPalette.dark
          ? Brightness.dark
          : Brightness.light,
    );
    return Theme(
      data: theme,
      child: Material(
        // accent + onAccent: cặp màu đã đạt tương phản của palette.
        color: palette.accent,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Đang dùng nội dung đã lưu — không kết nối được máy chủ',
                    style: TextStyle(color: palette.onAccent, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: loading ? null : onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.onAccent,
                    disabledForegroundColor: palette.onAccent,
                  ),
                  child: loading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.onAccent,
                          ),
                        )
                      : const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// MaterialApp riêng cho màn chờ/lỗi (chưa có router của app).
class _Shell extends ConsumerWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(brightness: Brightness.light),
    darkTheme: buildAppTheme(),
    themeMode: ref.watch(themeModeProvider),
    home: Scaffold(
      body: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
    ],
  );
}
