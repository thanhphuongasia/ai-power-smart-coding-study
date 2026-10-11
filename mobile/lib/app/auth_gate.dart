/// Cổng đăng nhập: chưa có phiên → LoginScreen; có phiên → app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../features/account/login_screen.dart';
import 'theme.dart';
import 'theme_mode.dart';

/// HOOK SAU ĐĂNG NHẬP: việc cần xong trước khi hiện app (vd tải tiến độ).
/// Mặc định no-op. Task khác override/thay thân provider này; nó có thể
/// `ref.watch(authControllerProvider)` để chạy lại theo phiên. AuthGate chỉ
/// hiện spinner lúc nó đang tải LẦN ĐẦU; về sau (refresh) giữ nguyên app,
/// nên không remount. Lỗi ở đây không chặn app.
final postLoginLoaderProvider = FutureProvider<void>((ref) async {});

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
    final loader = ref.watch(postLoginLoaderProvider);
    if (loader.isLoading && !loader.hasValue && !loader.hasError) {
      return const _Shell(home: _Splash());
    }
    return child;
  }
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
