import 'package:flutter/material.dart';

import '../screens/app_shell.dart';
import '../theme/app_theme.dart';
import 'app_state.dart';

class AICodingCoachApp extends StatefulWidget {
  const AICodingCoachApp({super.key});

  @override
  State<AICodingCoachApp> createState() => _AICodingCoachAppState();
}

class _AICodingCoachAppState extends State<AICodingCoachApp> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = AppState.seeded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'Pocket Coding Coach',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: AppShell(appState: _appState),
        );
      },
    );
  }
}
