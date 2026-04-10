import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/cs.dart' as highlight_cs;
import 'package:highlight/languages/dart.dart' as highlight_dart;
import 'package:highlight/languages/java.dart' as highlight_java;
import 'package:highlight/languages/python.dart' as highlight_python;

import '../app/app_state.dart';
import '../models/learning_models.dart';

typedef SessionExecutionCallback = Future<ValidationResult> Function();
typedef SessionFileChangedCallback = void Function(
    String filePath, String code);

class PracticeSessionScreen extends StatefulWidget {
  const PracticeSessionScreen({
    super.key,
    required this.appState,
    required this.onBackToCatalog,
  });

  final AppState appState;
  final VoidCallback onBackToCatalog;

  @override
  State<PracticeSessionScreen> createState() => _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends State<PracticeSessionScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant PracticeSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  void _syncController() {
    final session = widget.appState.activeSession;
    final nextText =
        session == null ? '' : session.fileContentFor(session.activeFilePath);
    if (_controller.text != nextText) {
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.appState.activeSession;
    if (session == null) {
      return _EmptySession(onBackToCatalog: widget.onBackToCatalog);
    }

    final theme = Theme.of(context);
    final result = session.validationResult;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: widget.onBackToCatalog,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(session.milestone.title,
                        style: theme.textTheme.titleLarge),
                    Text(
                      '${session.track.title} · ${session.mode.label} · ${session.milestone.languageLabel}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: _showProblemSheet,
                child: const Text('Prompt'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              140 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            children: <Widget>[
              _SessionBanner(session: session),
              const SizedBox(height: 12),
              _EditorPanel(
                controller: _controller,
                activeFile: session.activeFilePath,
                onOpenSourceTree: _openSourceTreeSidebar,
                onOpenFullscreen: _openFullscreenEditor,
              ),
              const SizedBox(height: 12),
              _QuickActionRow(
                onHint: _openHint,
                onBuild: () async {
                  final validation = await widget.appState.buildSession();
                  if (!mounted) {
                    return;
                  }
                  _showResultSheet(validation);
                },
                onRun: () async {
                  final validation = await widget.appState.runSession();
                  if (!mounted) {
                    return;
                  }
                  _showResultSheet(validation);
                },
                onCheck: () {
                  final validation = widget.appState.checkSession();
                  _showTextSheet(validation.summary, validation.output);
                },
                onExplain: _showReflectionSheet,
              ),
              const SizedBox(height: 12),
              _ValidationCard(
                result: result,
                milestone: session.milestone,
              ),
              const SizedBox(height: 12),
              _ExecutionHistoryCard(history: session.executionHistory),
              const SizedBox(height: 12),
              _SessionLogCard(log: session.sessionLog),
            ],
          ),
        ),
      ],
    );
  }

  void _openHint() {
    final hint = widget.appState.revealNextHint();
    final session = widget.appState.activeSession;
    if (!mounted || session == null) {
      return;
    }
    final level = session.revealedHintLevel?.label ?? 'Hint';
    _showTextSheet(level, hint);
  }

  void _showProblemSheet() {
    final session = widget.appState.activeSession;
    if (session == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(session.milestone.objective,
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(session.milestone.problemStatement,
                      style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 18),
                  Text('Acceptance criteria',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...session.milestone.acceptanceCriteria.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Icon(Icons.check_circle_outline_rounded,
                                size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Guided milestones', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...session.milestone.taskSteps.map(
                    (step) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(step.title,
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(step.description),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Sandbox test cases',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (session.milestone.testCases.isEmpty) ...<Widget>[
                    Text('Input: ${session.milestone.exampleInput}'),
                    const SizedBox(height: 4),
                    Text('Expected: ${session.milestone.exampleOutput}'),
                  ] else
                    ...session.milestone.testCases.map(
                      (testCase) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(testCase.label,
                                  style: theme.textTheme.titleMedium),
                              const SizedBox(height: 6),
                              SelectableText(
                                testCase.expectedOutput,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showReflectionSheet() {
    final session = widget.appState.activeSession;
    if (session == null) {
      return;
    }
    _showTextSheet(
      'Post-solve reflection',
      '- ${session.milestone.reflectionPrompts.join('\n- ')}',
    );
  }

  void _showTextSheet(String title, String content) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: ListView(
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 14),
                  SelectableText(content, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showResultSheet(ValidationResult result) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ExecutionResultSheet(result: result),
    );
  }

  Future<void> _openFullscreenEditor() async {
    final session = widget.appState.activeSession;
    if (session == null) {
      return;
    }

    final activeFile = session.activeFilePath;

    final selectedFile = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (context) => _FullscreenEditorPage(
          initialCode: session.fileContentFor(activeFile),
          activeFile: activeFile,
          fileContents: session.fileContents,
          languageLabel: session.milestone.languageLabel,
          files: session.milestone.relatedFiles,
          onBuild: widget.appState.buildSession,
          onRun: widget.appState.runSession,
          onChanged: (filePath, code) => widget.appState.updateSessionFileCode(
            filePath: filePath,
            code: code,
          ),
          onFileSelected: widget.appState.selectSessionFile,
        ),
      ),
    );

    if (selectedFile != null) {
      widget.appState.selectSessionFile(selectedFile);
    }
  }

  Future<void> _openSourceTreeSidebar() async {
    final session = widget.appState.activeSession;
    if (session == null) {
      return;
    }

    final selected = await _showSourceTreeSidebar(
      context: context,
      files: session.milestone.relatedFiles,
      activeFile: session.activeFilePath,
      title: 'Source tree',
    );

    if (selected != null) {
      widget.appState.selectSessionFile(selected);
    }
  }
}

class _EmptySession extends StatelessWidget {
  const _EmptySession({
    required this.onBackToCatalog,
  });

  final VoidCallback onBackToCatalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.code_rounded,
                    size: 44, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('No active session yet',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(
                  'Pick a project slice, data structure drill, or LeetCode problem to start practicing.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: onBackToCatalog,
                  child: const Text('Open practice library'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionBanner extends StatelessWidget {
  const _SessionBanner({
    required this.session,
  });

  final PracticeSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0F5B6E), Color(0xFF3D8D7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Chip(
                label: Text(session.track.type.label),
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                labelStyle: const TextStyle(color: Colors.white),
              ),
              Chip(
                label: Text(session.milestone.languageLabel),
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                labelStyle: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            session.milestone.objective,
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            session.milestone.problemStatement,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Files: ${session.milestone.relatedFiles.join(', ')}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.controller,
    required this.activeFile,
    required this.onOpenSourceTree,
    required this.onOpenFullscreen,
  });

  final TextEditingController controller;
  final String activeFile;
  final VoidCallback onOpenSourceTree;
  final VoidCallback onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF162634),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.code_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Code editor',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeFile,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onOpenSourceTree,
                tooltip: 'Source tree',
                icon: const Icon(Icons.account_tree_rounded),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onOpenFullscreen,
                icon: const Icon(Icons.open_in_full_rounded),
                label: const Text('Full screen'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onOpenFullscreen,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F1923),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 300,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: SingleChildScrollView(
                          child: Text(
                            controller.text,
                            style: const TextStyle(
                              color: Color(0xFFF4F5F7),
                              fontFamily: 'monospace',
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2B3A),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Text(
                              'Tap to edit full screen',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Inline panel is now a preview. Open full screen to type reliably and focus the editor.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileTreeNodeView extends StatelessWidget {
  const _FileTreeNodeView({
    required this.node,
    required this.depth,
    required this.activeFile,
    required this.onSelect,
  });

  final _FileTreeNode node;
  final int depth;
  final String? activeFile;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (node.isFile) {
      final isActive = activeFile == node.path;
      return Padding(
        padding: EdgeInsets.only(left: 8.0 + (depth * 14), bottom: 6),
        child: Material(
          color: isActive
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSelect(node.path!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: isActive ? Colors.white : Colors.white70,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      node.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isActive)
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * 10.0),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: EdgeInsets.zero,
        leading:
            const Icon(Icons.folder_open_rounded, size: 20, color: Colors.white70),
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        title: Text(node.name, style: const TextStyle(color: Colors.white)),
        children: node.children
            .map((child) => _FileTreeNodeView(
                  node: child,
                  depth: depth + 1,
                  activeFile: activeFile,
                  onSelect: onSelect,
                ))
            .toList(),
      ),
    );
  }
}

class _FileTreeNode {
  _FileTreeNode.file({
    required this.name,
    required this.path,
  })  : isFile = true,
        children = const <_FileTreeNode>[];

  _FileTreeNode.folder({
    required this.name,
    this.path,
  })  : isFile = false,
        children = <_FileTreeNode>[];

  final String name;
  final String? path;
  final bool isFile;
  final List<_FileTreeNode> children;
}

class _FullscreenEditorPage extends StatefulWidget {
  const _FullscreenEditorPage({
    required this.initialCode,
    required this.activeFile,
    required this.fileContents,
    required this.languageLabel,
    required this.files,
    required this.onBuild,
    required this.onRun,
    required this.onFileSelected,
    required this.onChanged,
  });

  final String initialCode;
  final String activeFile;
  final Map<String, String> fileContents;
  final String languageLabel;
  final List<String> files;
  final SessionExecutionCallback onBuild;
  final SessionExecutionCallback onRun;
  final ValueChanged<String> onFileSelected;
  final SessionFileChangedCallback onChanged;

  @override
  State<_FullscreenEditorPage> createState() => _FullscreenEditorPageState();
}

class _FullscreenEditorPageState extends State<_FullscreenEditorPage> {
  late final CodeController _controller;
  final FocusNode _focusNode = FocusNode();
  late String _activeFile;
  late final Map<String, String> _fileContents;

  static const List<_EditorSnippet> _snippets = <_EditorSnippet>[
    _EditorSnippet(label: 'Space', value: '    '),
    _EditorSnippet(label: '()', value: '()'),
    _EditorSnippet(label: '{}', value: '{}'),
    _EditorSnippet(label: '[]', value: '[]'),
    _EditorSnippet(label: ':', value: ':'),
    _EditorSnippet(label: '=>', value: '=>'),
    _EditorSnippet(label: '.', value: '.'),
  ];

  @override
  void initState() {
    super.initState();
    _activeFile = widget.activeFile;
    _fileContents = Map<String, String>.from(widget.fileContents);
    _controller = CodeController(
      text: _fileContents[_activeFile] ?? widget.initialCode,
      language: _resolveLanguage(widget.languageLabel, _activeFile),
    );
    _controller.popupController.enabled = true;
    _syncAutocompleteWords();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        backgroundColor: const Color(0xFF162634),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _activeFile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              widget.languageLabel,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _openSourceTreeSidebar,
            tooltip: 'Source tree',
            icon: const Icon(Icons.account_tree_rounded),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(_activeFile),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: Column(
            children: <Widget>[
              _EditorActionToolbar(
                onBuild: _handleBuild,
                onRun: _handleRun,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF162634),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.fullscreen_rounded,
                                color: Colors.white70, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Full-screen editor',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F1923),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: CodeTheme(
                              data: CodeThemeData(styles: atomOneDarkTheme),
                              child: CodeField(
                                controller: _controller,
                                focusNode: _focusNode,
                                expands: true,
                                wrap: false,
                                onChanged: _handleEditorChanged,
                                background: const Color(0xFF0F1923),
                                gutterStyle: const GutterStyle(
                                  width: 52,
                                  margin: 12,
                                  textStyle: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                                textStyle: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                  fontSize: 15,
                                  height: 1.45,
                                ),
                                cursorColor: const Color(0xFFFFD4C6),
                                padding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _snippets
                              .map(
                                (snippet) => _AccessoryChip(
                                  label: snippet.label,
                                  onTap: () => _insertSnippet(snippet.value),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _insertSnippet(String snippet) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final safeStart = start < 0 ? text.length : start;
    final safeEnd = end < 0 ? text.length : end;
    final nextText = text.replaceRange(safeStart, safeEnd, snippet);
    final nextOffset = safeStart + snippet.length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _handleEditorChanged(nextText);
    _focusNode.requestFocus();
  }

  Future<void> _openSourceTreeSidebar() async {
    final selected = await _showSourceTreeSidebar(
      context: context,
      files: widget.files,
      activeFile: _activeFile,
      title: 'Source tree',
    );

    if (selected != null && mounted) {
      widget.onFileSelected(selected);
      setState(() => _activeFile = selected);
      _replaceEditorText(_fileContents[selected] ?? '');
      _controller.setLanguage(
        _resolveLanguage(widget.languageLabel, selected),
        analyzer: const DefaultLocalAnalyzer(),
      );
      _syncAutocompleteWords();
    }
  }

  Future<void> _handleBuild() async {
    final result = await widget.onBuild();
    if (!mounted) {
      return;
    }
    _showResultSheet(result);
  }

  Future<void> _handleRun() async {
    final result = await widget.onRun();
    if (!mounted) {
      return;
    }
    _showResultSheet(result);
  }

  void _showResultSheet(ValidationResult result) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ExecutionResultSheet(result: result),
    );
  }

  void _handleEditorChanged(String code) {
    _fileContents[_activeFile] = code;
    widget.onChanged(_activeFile, code);
  }

  List<String> _autocompleteCatalog({
    required String languageLabel,
    required String activeFile,
  }) {
    final parts = activeFile.split('.');
    final extension = parts.isEmpty ? '' : parts.last;
    final normalizedLanguage = languageLabel.toLowerCase();

    if (normalizedLanguage.contains('python') || extension == 'py') {
      return const <String>[
        'def ',
        'return ',
        'if ',
        'elif ',
        'else:',
        'for ',
        'while ',
        'in ',
        'len(',
        'range(',
        'dict',
        'set()',
        'last_seen',
        'best = 0',
      ];
    }

    if (normalizedLanguage.contains('c#') || extension == 'cs') {
      return const <String>[
        'public ',
        'private ',
        'class ',
        'void ',
        'string ',
        'int ',
        'bool ',
        'return ',
        'if ',
        'else',
        'List<',
        'Task ',
      ];
    }

    return const <String>[
      'class ',
      'function ',
      'return ',
      'if ',
      'else ',
      'for ',
      'while ',
    ];
  }

  void _syncAutocompleteWords() {
    _controller.autocompleter.setCustomWords(
      _autocompleteCatalog(
        languageLabel: widget.languageLabel,
        activeFile: _activeFile,
      ),
    );
  }

  void _replaceEditorText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Mode? _resolveLanguage(String languageLabel, String activeFile) {
    final extension =
        activeFile.contains('.') ? activeFile.split('.').last : '';
    final normalizedLanguage = languageLabel.toLowerCase();

    if (normalizedLanguage.contains('python') || extension == 'py') {
      return highlight_python.python;
    }
    if (normalizedLanguage.contains('c#') || extension == 'cs') {
      return highlight_cs.cs;
    }
    if (normalizedLanguage.contains('dart') || extension == 'dart') {
      return highlight_dart.dart;
    }
    if (normalizedLanguage.contains('java') || extension == 'java') {
      return highlight_java.java;
    }

    return null;
  }
}

class _EditorActionToolbar extends StatelessWidget {
  const _EditorActionToolbar({
    required this.onBuild,
    required this.onRun,
  });

  final Future<void> Function() onBuild;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => onBuild(),
            icon: const Icon(Icons.build_circle_outlined),
            label: const Text('Build'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => onRun(),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Run'),
          ),
        ),
      ],
    );
  }
}

Future<String?> _showSourceTreeSidebar({
  required BuildContext context,
  required List<String> files,
  required String? activeFile,
  required String title,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierLabel: title,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => _SourceTreeSidebar(
      files: files,
      activeFile: activeFile,
      title: title,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _SourceTreeSidebar extends StatelessWidget {
  const _SourceTreeSidebar({
    required this.files,
    required this.activeFile,
    required this.title,
  });

  final List<String> files;
  final String? activeFile;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = _buildFileTree(files);
    final width = MediaQuery.sizeOf(context).width * 0.82;

    return SafeArea(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: const Color(0xFF162634),
          elevation: 16,
          child: SizedBox(
            width: width,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 12, 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.account_tree_rounded,
                          color: Colors.white70),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      activeFile ?? 'Select a file',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 20),
                    children: root.children
                        .map(
                          (node) => _FileTreeNodeView(
                            node: node,
                            depth: 0,
                            activeFile: activeFile,
                            onSelect: (path) => Navigator.of(context).pop(path),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _FileTreeNode _buildFileTree(List<String> files) {
    final root = _FileTreeNode.folder(name: '');
    for (final path in files) {
      final segments = path.split('/');
      var current = root;
      for (var i = 0; i < segments.length; i += 1) {
        final segment = segments[i];
        final isFile = i == segments.length - 1;
        final existingIndex =
            current.children.indexWhere((child) => child.name == segment);
        if (existingIndex == -1) {
          final nextPath = segments.take(i + 1).join('/');
          final nextNode = isFile
              ? _FileTreeNode.file(name: segment, path: nextPath)
              : _FileTreeNode.folder(name: segment, path: nextPath);
          current.children.add(nextNode);
          current = nextNode;
        } else {
          current = current.children[existingIndex];
        }
      }
    }
    _sortTree(root);
    return root;
  }

  void _sortTree(_FileTreeNode node) {
    if (node.isFile) {
      return;
    }
    node.children.sort((a, b) {
      if (a.isFile == b.isFile) {
        return a.name.compareTo(b.name);
      }
      return a.isFile ? 1 : -1;
    });
    for (final child in node.children) {
      _sortTree(child);
    }
  }
}

class _AccessoryChip extends StatelessWidget {
  const _AccessoryChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            label,
            style:
                const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }
}

class _EditorSnippet {
  const _EditorSnippet({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.onHint,
    required this.onBuild,
    required this.onRun,
    required this.onCheck,
    required this.onExplain,
  });

  final VoidCallback onHint;
  final Future<void> Function() onBuild;
  final Future<void> Function() onRun;
  final VoidCallback onCheck;
  final VoidCallback onExplain;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        FilledButton.icon(
          onPressed: onHint,
          icon: const Icon(Icons.lightbulb_outline_rounded),
          label: const Text('Hint'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => onBuild(),
          icon: const Icon(Icons.build_circle_outlined),
          label: const Text('Build'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => onRun(),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Run'),
        ),
        FilledButton.tonalIcon(
          onPressed: onCheck,
          icon: const Icon(Icons.task_alt_rounded),
          label: const Text('Check'),
        ),
        FilledButton.tonalIcon(
          onPressed: onExplain,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('Explain'),
        ),
      ],
    );
  }
}

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({
    required this.result,
    required this.milestone,
  });

  final ValidationResult result;
  final Milestone milestone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = switch (result.status) {
      ValidationStatus.passed => theme.colorScheme.tertiary,
      ValidationStatus.needsWork => theme.colorScheme.secondary,
      ValidationStatus.running => theme.colorScheme.primary,
      ValidationStatus.idle => theme.colorScheme.outline,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        border:
            Border.all(color: borderColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Coach feedback', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(result.summary),
          if (result.executionReport case final report?) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.55),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Sandbox execution', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '${report.engineLabel} · ${report.statusLabel}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (report.totalCaseCount > 0) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'Passed ${report.passedCaseCount}/${report.totalCaseCount} test cases',
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (result.matchedRequirements.isNotEmpty) ...<Widget>[
            Text('Matched checks', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            ...result.matchedRequirements.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.check_circle_rounded,
                        color: theme.colorScheme.tertiary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (result.missingRequirements.isNotEmpty) ...<Widget>[
            Text('Still missing', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            ...result.missingRequirements.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.radio_button_unchecked_rounded,
                        color: theme.colorScheme.secondary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            ),
          ] else ...<Widget>[
            Text('Reflection prompts', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            ...milestone.reflectionPrompts.map(
              (prompt) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $prompt'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExecutionResultSheet extends StatelessWidget {
  const _ExecutionResultSheet({
    required this.result,
  });

  final ValidationResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = result.executionReport;
    if (report == null) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ListView(
              children: <Widget>[
                Text(result.summary, style: theme.textTheme.titleLarge),
                const SizedBox(height: 14),
                SelectableText(result.output, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
      );
    }

    final tabs = <ExecutionOutputSection>[
      if (report.caseResults.isNotEmpty)
        ExecutionOutputSection(
          id: 'cases',
          title: 'Cases',
          content: '',
        ),
      ...report.sections.where((section) => section.content.trim().isNotEmpty),
    ];

    return DefaultTabController(
      length: tabs.isEmpty ? 1 : tabs.length,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.84,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(result.summary, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${report.engineLabel} · ${report.statusLabel}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (report.totalCaseCount > 0) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'Passed ${report.passedCaseCount}/${report.totalCaseCount} test cases',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: 16),
                if (tabs.isEmpty)
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        SelectableText(
                          result.output,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  )
                else ...<Widget>[
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: tabs.map((tab) => Tab(text: tab.title)).toList(),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: tabs.map((tab) {
                        if (tab.id == 'cases') {
                          return _ExecutionCasesList(
                            caseResults: report.caseResults,
                          );
                        }
                        return ListView(
                          children: <Widget>[
                            SelectableText(
                              tab.content,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExecutionCasesList extends StatelessWidget {
  const _ExecutionCasesList({
    required this.caseResults,
  });

  final List<ExecutionCaseResult> caseResults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: caseResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final caseResult = caseResults[index];
        final accentColor = caseResult.passed
            ? theme.colorScheme.tertiary
            : theme.colorScheme.secondary;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    caseResult.passed
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: accentColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      caseResult.label,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(caseResult.statusLabel),
                ],
              ),
              const SizedBox(height: 10),
              Text('Expected', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(caseResult.expectedOutput),
              const SizedBox(height: 10),
              Text('Actual', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              SelectableText(caseResult.actualOutput),
              if (caseResult.stderr.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text('Stderr', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                SelectableText(caseResult.stderr),
              ],
              if (caseResult.compileOutput.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text('Compile output', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                SelectableText(caseResult.compileOutput),
              ],
              if (caseResult.message.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text('Message', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                SelectableText(caseResult.message),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SessionLogCard extends StatelessWidget {
  const _SessionLogCard({
    required this.log,
  });

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Progress tracking', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            ...log.reversed.take(6).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child:
                              Icon(Icons.fiber_manual_record_rounded, size: 10),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ExecutionHistoryCard extends StatelessWidget {
  const _ExecutionHistoryCard({
    required this.history,
  });

  final List<ExecutionAttempt> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (history.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Run history', style: theme.textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                'Your sandbox build and run attempts will appear here once you start executing code.',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Run history', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            ...history.map(
              (attempt) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(Icons.history_rounded, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${attempt.actionLabel} · ${attempt.statusLabel}',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(attempt.summary),
                          const SizedBox(height: 4),
                          Text(
                            [
                              _formatAttemptTime(context, attempt.timestamp),
                              if (attempt.totalCaseCount != null)
                                'Cases ${attempt.passedCaseCount ?? 0}/${attempt.totalCaseCount}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAttemptTime(BuildContext context, DateTime timestamp) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(timestamp),
      alwaysUse24HourFormat: true,
    );
  }
}
