/// Cổng đăng nhập: chưa có phiên → LoginScreen; có phiên → app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/progress_api.dart';
import '../features/account/login_screen.dart';
import 'theme.dart';
import 'theme_mode.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final session = auth.value;
    if (session == null) {
      if (auth.isLoading) return const _Shell(home: _Splash());
      return const _Shell(home: LoginScreen());
    }
    // Chỉ vào app khi tiến độ của ĐÚNG phiên hiện tại đã tải xong. Đang tải
    // (kể cả tải lại, khi `value` còn là của phiên trước) → spinner.
    final snapshot = ref.watch(progressSnapshotProvider);
    if (snapshot.isLoading) return const _Shell(home: _Splash());
    if (snapshot.hasError) return const _Shell(home: _ProgressLoadError());
    if (snapshot.value?.token != session.token) {
      return const _Shell(home: _Splash());
    }
    return child;
  }
}

/// Tải tiến độ lỗi: không mở app rỗng (sẽ tắt đồng bộ âm thầm) mà cho thử lại
/// hoặc đăng xuất.
class _ProgressLoadError extends ConsumerWidget {
  const _ProgressLoadError();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      key: const Key('progress-load-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Không tải được tiến độ học'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('progress-retry'),
              onPressed: () => ref.invalidate(progressSnapshotProvider),
              child: const Text('Thử lại'),
            ),
            TextButton(
              key: const Key('progress-logout'),
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              child: const Text('Đăng xuất'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// MaterialApp riêng cho màn chờ/đăng nhập (chưa có router của app).
class _Shell extends ConsumerWidget {
  const _Shell({required this.home});
  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(brightness: Brightness.light),
    darkTheme: buildAppTheme(),
    themeMode: ref.watch(themeModeProvider),
    home: home,
  );
}
