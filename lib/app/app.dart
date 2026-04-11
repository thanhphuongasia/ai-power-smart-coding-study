import 'package:flutter/material.dart';

import '../screens/app_shell.dart';
import '../theme/app_theme.dart';
import 'app_state.dart';

class AICodingCoachApp extends StatefulWidget {
  const AICodingCoachApp({
    super.key,
    this.appStateLoader = AppState.bootstrap,
  });

  final Future<AppState> Function() appStateLoader;

  @override
  State<AICodingCoachApp> createState() => _AICodingCoachAppState();
}

class _AICodingCoachAppState extends State<AICodingCoachApp> {
  late final Future<AppState> _appStateFuture;

  @override
  void initState() {
    super.initState();
    _appStateFuture = widget.appStateLoader();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _appStateFuture,
      builder: (context, snapshot) {
        final theme = AppTheme.light();
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            title: 'Pocket Coding Coach',
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: const _LoadingScreen(),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return MaterialApp(
            title: 'Pocket Coding Coach',
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: _BootstrapErrorScreen(
              error: snapshot.error,
            ),
          );
        }

        final appState = snapshot.data!;
        return AnimatedBuilder(
          animation: appState,
          builder: (context, _) {
            return MaterialApp(
              title: 'Pocket Coding Coach',
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: AppShell(appState: appState),
            );
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your synced coaching workspace...'),
          ],
        ),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({
    required this.error,
  });

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'The app could not load its local cache or remote data.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                error?.toString() ?? 'Unknown bootstrap error.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
