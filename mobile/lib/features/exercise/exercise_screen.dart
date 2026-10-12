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
import '../../data/api_client.dart';
import '../../data/content_providers.dart';
import '../../data/judge_client.dart';
import '../../data/progress_api.dart';
import '../../domain/content.dart';
import '../../domain/models.dart';
import '../review/review_controller.dart';
import '../shell/app_drawer.dart' show AppMenuButton;
import '../stats/activity.dart';
import '../../shared/widgets.dart';
import 'challenge_tab.dart';
import 'code_tab.dart';
import 'session_controller.dart';
import 'session_providers.dart';
import 'solution_tab.dart';

void _leave(BuildContext context, {bool preview = false}) {
  if (preview) {
    // Preview mở bằng Navigator thường (không phụ thuộc GoRouter).
    Navigator.of(context).maybePop();
  } else if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

/// Session không đếm giờ: preview không có idle/tự thoát.
class _PreviewSession extends SessionController {
  _PreviewSession(super.exerciseId);

  @override
  void start() {}
}

/// Admin xem trước bài [exerciseId] của [content] (bản nháp) đúng như học
/// viên thấy. Scope lồng cô lập hoàn toàn khỏi tiến độ thật: không đẩy
/// progress, draft/hint/solution không trộn, Run gọi `/api/admin/run`.
class ExercisePreview extends StatelessWidget {
  const ExercisePreview({
    super.key,
    required this.content,
    required this.exerciseId,
  });

  final Content content;
  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        contentIndexProvider.overrideWithValue(content),
        exerciseUnlockedProvider.overrideWith((ref, id) => true),
        progressSyncEnabledProvider.overrideWithValue(false),
        loadedProgressProvider.overrideWithValue(null),
        progressProvider.overrideWith(ProgressController.new),
        activityProvider.overrideWith(ActivityController.new),
        reviewScheduleProvider.overrideWith(ReviewController.new),
        sessionProvider.overrideWith2(_PreviewSession.new),
        judgeClientProvider.overrideWith(
          (ref) => JudgeClient(
            httpClient: ref.watch(apiClientProvider),
            path: '/api/admin/run',
          ),
        ),
      ],
      child: ExerciseScreen(exerciseId: exerciseId, preview: true),
    );
  }
}

class ExerciseScreen extends ConsumerWidget {
  const ExerciseScreen({
    super.key,
    required this.exerciseId,
    this.preview = false,
  });

  final String exerciseId;

  /// Chỉ [ExercisePreview] đặt true: banner, không có "bài tiếp", back bằng
  /// Navigator.
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(exerciseUnlockedProvider(exerciseId));
    if (!unlocked) return _LockedView(exerciseId: exerciseId);
    return _UnlockedView(exerciseId: exerciseId, preview: preview);
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
  const _UnlockedView({required this.exerciseId, required this.preview});

  final String exerciseId;
  final bool preview;

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
                    if (mounted) _leave(context, preview: widget.preview);
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
        _leave(context, preview: widget.preview);
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

    // Đo bề rộng cửa sổ: ≥ split chia đôi đề | editor, < split giữ ba tab.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= AppBreakpoint.split;
        return DefaultTabController(
          length: wide ? 2 : 3,
          initialIndex: wide ? 0 : initialIndex,
          // Mọi chạm/cuộn trên màn đều reset idle (kể cả chỉ đọc đề).
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => ref
                .read(sessionProvider(widget.exerciseId).notifier)
                .activity(),
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    if (widget.preview)
                      Container(
                        key: const Key('preview-banner'),
                        width: double.infinity,
                        color: p.accent,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpace.s1,
                          horizontal: AppSpace.s4,
                        ),
                        child: Text(
                          'Xem trước — chưa duyệt',
                          textAlign: TextAlign.center,
                          style: AppText.label.copyWith(color: p.onAccent),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.s2,
                        AppSpace.s2,
                        AppSpace.s4,
                        0,
                      ),
                      child: Row(
                        children: [
                          if (width >= AppBreakpoint.nav) const AppMenuButton(),
                          IconButton(
                            key: const Key('exercise-back'),
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Quay lại',
                            onPressed: () =>
                                _leave(context, preview: widget.preview),
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
                                  '${located.file.name} · ${exercise.qualifiedName}',
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
                    if (wide)
                      Expanded(child: _splitBody(p, exercise))
                    else ...[
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
                            Tab(
                              text:
                                  'Code $draftCount/${exercise.blocks.length}',
                            ),
                            const Tab(text: 'Solution'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            ChallengeTab(exercise: exercise),
                            CodeTab(
                              exercise: exercise,
                              preview: widget.preview,
                            ),
                            SolutionTab(exercise: exercise),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Bố cục ≥ [AppBreakpoint.split]: trái đề / lời giải (42%), phải editor
  /// inline (58%). Không có tab Code nên hai tab trái ẩn nút nhảy sang Code.
  Widget _splitBody(AppPalette p, Exercise exercise) {
    return Row(
      key: const Key('exercise-split'),
      children: [
        Expanded(
          flex: 42,
          child: Column(
            children: [
              TabBar(
                key: const Key('exercise-split-tabs'),
                labelColor: p.primary,
                unselectedLabelColor: p.inkMuted,
                indicatorColor: p.primary,
                dividerColor: p.outline.withValues(alpha: 0.4),
                labelStyle: AppText.label,
                tabs: const [
                  Tab(text: 'Đề'),
                  Tab(text: 'Lời giải'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ChallengeTab(exercise: exercise, showGoCode: false),
                    SolutionTab(exercise: exercise, showGoCode: false),
                  ],
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: p.outline.withValues(alpha: 0.4)),
        Expanded(
          flex: 58,
          child: CodeTab(
            exercise: exercise,
            preview: widget.preview,
            inlineEditor: true,
          ),
        ),
      ],
    );
  }
}
