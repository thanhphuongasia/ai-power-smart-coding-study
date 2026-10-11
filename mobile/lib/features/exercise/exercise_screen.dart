/// Màn bài tập `/exercise/:id`: header (tên bài, file · hàm, đồng hồ) và ba
/// tab Challenge / Code / Solution. Bài khoá (INV-08) mở thẳng route chỉ hiện
/// màn khoá, không dựng tab, không chạy đồng hồ.
///
/// Chuyển tab từ trong tab con: `DefaultTabController.of(context).animateTo(i)`
/// (Challenge=0, Code=[kCodeTabIndex]=1, Solution=2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../app/theme.dart';
import '../../data/content_providers.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import 'challenge_tab.dart';
import 'code_tab.dart';
import 'session_controller.dart';
import 'session_providers.dart';
import 'solution_tab.dart';

void _leave(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

class ExerciseScreen extends ConsumerWidget {
  const ExerciseScreen({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(exerciseUnlockedProvider(exerciseId));
    if (!unlocked) return _LockedView(exerciseId: exerciseId);
    return _UnlockedView(exerciseId: exerciseId);
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView({required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: const Key('locked-back'),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Quay lại',
                onPressed: () => _leave(context),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.s6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 48, color: p.inkMuted),
                      const SizedBox(height: AppSpace.s4),
                      const Text(
                        'Bài này chưa mở',
                        key: Key('locked-title'),
                        style: AppText.title,
                      ),
                      const SizedBox(height: AppSpace.s2),
                      Text(
                        'Hoàn thành bài trước trong file này để mở bài này.',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: p.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s4),
                      GhostButton(
                        label: 'Quay lại',
                        onPressed: () => _leave(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlockedView extends ConsumerStatefulWidget {
  const _UnlockedView({required this.exerciseId});

  final String exerciseId;

  @override
  ConsumerState<_UnlockedView> createState() => _UnlockedViewState();
}

class _UnlockedViewState extends ConsumerState<_UnlockedView> {
  bool _idleDialogOpen = false;

  Exercise get _exercise =>
      ref.read(contentIndexProvider).exerciseById(widget.exerciseId);

  @override
  void initState() {
    super.initState();
    // start() sau frame đầu, và build() phải watch sessionProvider suốt vòng
    // đời màn — nếu không autoDispose huỷ Timer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sessionProvider(widget.exerciseId).notifier).start();
    });
  }

  int _draftCount(ExerciseProgress? progress) {
    if (progress == null) return 0;
    var n = 0;
    for (final b in _exercise.blocks) {
      if ((progress.drafts[b.label] ?? '').trim().isNotEmpty) n++;
    }
    return n;
  }

  void _showIdleDialog() {
    if (_idleDialogOpen) return;
    _idleDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, _) {
            final session = ref.watch(sessionProvider(widget.exerciseId));
            return AlertDialog(
              title: const Text('Vẫn đang làm chứ?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Không có thao tác trong 2 phút. Code của bạn đã được lưu.',
                  ),
                  const SizedBox(height: AppSpace.s2),
                  Text(
                    'Tự thoát sau ${session.idleCountdownSeconds}s',
                    key: const Key('idle-countdown'),
                    style: AppText.caption.copyWith(
                      color: context.palette.danger,
                    ),
                  ),
                ],
              ),
              actions: [
                GhostButton(
                  key: const Key('idle-rest-button'),
                  label: 'Nghỉ',
                  onPressed: () {
                    _idleDialogOpen = false;
                    Navigator.of(dialogContext).pop();
                    if (mounted) _leave(context);
                  },
                ),
                PrimaryButton(
                  key: const Key('idle-resume-button'),
                  label: 'Tiếp tục',
                  onPressed: () {
                    ref
                        .read(sessionProvider(widget.exerciseId).notifier)
                        .resume();
                    _idleDialogOpen = false;
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((_) => _idleDialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = ref.watch(contentIndexProvider);
    final exercise = _exercise;
    final located = content.locateExercise(widget.exerciseId);
    final session = ref.watch(sessionProvider(widget.exerciseId));
    final draftCount = _draftCount(
      ref.watch(progressProvider.select((m) => m[widget.exerciseId])),
    );

    ref.listen(sessionProvider(widget.exerciseId), (previous, next) {
      if (next.phase == SessionPhase.timedOut &&
          previous?.phase != SessionPhase.timedOut) {
        if (_idleDialogOpen) {
          _idleDialogOpen = false;
          Navigator.of(context, rootNavigator: true).pop();
        }
        _leave(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã lưu tiến độ')));
      } else if (next.phase == SessionPhase.idle &&
          previous?.phase != SessionPhase.idle) {
        _showIdleDialog();
      }
    });

    // Mặc định: có draft → tab Code, chưa có → Challenge. Chỉ có tác dụng ở
    // lần dựng đầu (DefaultTabController giữ controller sau đó).
    final initialIndex = draftCount > 0 ? kCodeTabIndex : 0;

    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex,
      // Mọi chạm/cuộn trên màn đều reset idle (kể cả chỉ đọc đề).
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) =>
            ref.read(sessionProvider(widget.exerciseId).notifier).activity(),
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.s2,
                    AppSpace.s2,
                    AppSpace.s4,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('exercise-back'),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Quay lại',
                        onPressed: () => _leave(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exercise.title,
                              key: const Key('exercise-title'),
                              style: AppText.title.copyWith(fontSize: 18),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${located.file.name} · ${exercise.functionName}',
                              key: const Key('exercise-subtitle'),
                              style: AppText.caption.copyWith(
                                fontFamily: kMonoFamily,
                                color: p.inkMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpace.s2),
                      TimerPill(
                        session.elapsed,
                        warning: session.phase != SessionPhase.active,
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (context) => TabBar(
                    key: const Key('exercise-tabs'),
                    labelColor: p.primary,
                    unselectedLabelColor: p.inkMuted,
                    indicatorColor: p.primary,
                    dividerColor: p.outline.withValues(alpha: 0.4),
                    labelStyle: AppText.label,
                    tabs: [
                      const Tab(text: 'Challenge'),
                      Tab(text: 'Code $draftCount/${exercise.blocks.length}'),
                      const Tab(text: 'Solution'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ChallengeTab(exercise: exercise),
                      CodeTab(exercise: exercise),
                      SolutionTab(exercise: exercise),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
