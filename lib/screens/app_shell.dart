import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../models/learning_models.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'practice_session_screen.dart';
import 'review_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.appState,
  });

  final AppState appState;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  LearningTrackType _catalogType = LearningTrackType.project;

  @override
  Widget build(BuildContext context) {
    final session = widget.appState.activeSession;

    final pages = <Widget>[
      HomeScreen(
        appState: widget.appState,
        onOpenLane: _openLane,
        onOpenReview: () => setState(() => _index = 2),
      ),
      CatalogScreen(
        appState: widget.appState,
        initialType: _catalogType,
        onStartSession: _startSession,
      ),
      ReviewScreen(
        appState: widget.appState,
        onStartReviewTask: (task) {
          final started = widget.appState.startReviewTask(task);
          if (started) {
            setState(() => _index = 3);
          }
        },
      ),
      PracticeSessionScreen(
        appState: widget.appState,
        onBackToCatalog: () {
          widget.appState.closeSession();
          setState(() => _index = 1);
        },
      ),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFFF7F3EA),
              Color(0xFFF3F6F2),
              Color(0xFFEDE7DA)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(child: pages[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          if (value == 3 && session == null) {
            setState(() => _index = 1);
            return;
          }
          setState(() => _index = value);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Practice',
          ),
          NavigationDestination(
            icon: Icon(Icons.flash_on_outlined),
            selectedIcon: Icon(Icons.flash_on_rounded),
            label: 'Review',
          ),
          NavigationDestination(
            icon: Icon(Icons.code_outlined),
            selectedIcon: Icon(Icons.code_rounded),
            label: 'Session',
          ),
        ],
      ),
    );
  }

  void _openLane(LearningTrackType type) {
    setState(() {
      _catalogType = type;
      _index = 1;
    });
  }

  void _startSession({
    LearningTrack? track,
    required LearningExercise exercise,
    required PracticeMode mode,
    String? languageId,
  }) {
    widget.appState.startSession(
      track: track,
      exercise: exercise,
      mode: mode,
      languageId: languageId,
    );
    setState(() => _index = 3);
  }
}
