import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/content_gate.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'app/theme_mode.dart';
import 'data/content_providers.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        contentIndexProvider.overrideWith(
          (ref) => ref.watch(contentProvider).requireValue.content,
        ),
      ],
      child: const ContentGate(child: SmartCodingStudyApp()),
    ),
  );
}

class SmartCodingStudyApp extends ConsumerWidget {
  const SmartCodingStudyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Smart coding study',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}
