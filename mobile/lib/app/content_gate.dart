/// Cổng nội dung: chỉ dựng giao diện app khi đã có nội dung (mạng hoặc cache).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/content_providers.dart';
import '../data/content_repository.dart';
import 'theme.dart';

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
    if (load.source != ContentSource.cache) return child;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData.fromView(View.of(context)),
        child: Column(
          children: [
            Theme(
              data: buildAppTheme(),
              child: Material(
                color: Colors.amber.shade800,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Đang dùng nội dung đã lưu — không kết nối được máy chủ',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(contentProvider.notifier).refresh(),
                          child: const Text(
                            'Thử lại',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// MaterialApp riêng cho màn chờ/lỗi (chưa có router của app).
class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(brightness: Brightness.light),
    darkTheme: buildAppTheme(),
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
