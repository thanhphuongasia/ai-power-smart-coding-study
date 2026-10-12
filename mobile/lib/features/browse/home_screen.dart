/// Màn Home: điểm vào chính — tiếp tục bài đang dở (nếu có) và danh sách
/// theme để chọn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/theme_mode.dart';
import '../../data/api_client.dart';
import '../../data/content_providers.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../exercise/session_controller.dart';
import '../exercise/session_providers.dart';
import '../review/review_controller.dart';
import '../stats/activity.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentIndexProvider);
    final progress = ref.watch(progressProvider);
    final inProgress = ref.watch(inProgressExerciseProvider);
    final dueCount = ref.watch(dueCardsProvider).length;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.s4),
          children: [
            Row(
              children: [
                _StreakChip(
                  activity: ref.watch(activityProvider),
                  today: dayOf(ref.read(clockProvider)()),
                ),
                const Spacer(),
                if (ref.watch(currentUserProvider)?.isAdmin ?? false)
                  IconButton(
                    key: const Key('admin-button'),
                    icon: const Icon(Icons.fact_check_outlined),
                    tooltip: 'Duyệt nội dung',
                    onPressed: () => context.push('/admin'),
                  ),
                PopupMenuButton<String>(
                  key: const Key('account-button'),
                  icon: const Icon(Icons.account_circle_outlined),
                  tooltip: 'Tài khoản',
                  onSelected: (value) {
                    if (value == 'password') {
                      context.push('/account/password');
                    } else {
                      ref.read(authControllerProvider.notifier).logout();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Text(
                        ref.read(currentUserProvider)?.email ?? '',
                        key: const Key('account-email'),
                      ),
                    ),
                    if (ref.read(authControllerProvider).value?.open ?? false)
                      const PopupMenuItem<String>(
                        enabled: false,
                        key: Key('account-open-mode'),
                        child: Text('Chế độ mở'),
                      )
                    else ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'password',
                        key: Key('account-change-password'),
                        child: Text('Đổi mật khẩu'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'logout',
                        key: Key('account-logout'),
                        child: Text('Đăng xuất'),
                      ),
                    ],
                  ],
                ),
                const ThemeModeButton(),
              ],
            ),
            const SizedBox(height: AppSpace.s2),
            const Text('Luyện tập hôm nay', style: AppText.display),
            const SizedBox(height: AppSpace.s6),
            if (inProgress != null) ...[
              _ContinueCard(exercise: inProgress, progress: progress),
              const SizedBox(height: AppSpace.s6),
            ],
            if (dueCount > 0) ...[
              _DueCard(count: dueCount),
              const SizedBox(height: AppSpace.s6),
            ],
            const SectionLabel('Chủ đề'),
            _ThemeGrid(themes: content.themes, progress: progress),
          ],
        ),
      ),
    );
  }
}

/// Số ngày liên tiếp + ngọn lửa ở thanh đầu trang (kiểu Coddy/Duolingo).
/// Lửa xám khi hôm nay chưa làm gì — nhắc giữ chuỗi. Chạm để xem tuần này.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.activity, required this.today});

  final Map<DateTime, int> activity;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final streak = currentStreak(activity, today);
    final color = (activity[today] ?? 0) > 0 ? p.accent : p.outline;

    return Semantics(
      button: true,
      label: '$streak ngày liên tiếp',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('streak-chip'),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: p.surfaceRaised,
          builder: (_) => SafeArea(
            child: _StreakDetail(activity: activity, today: today),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.s2,
            vertical: AppSpace.s1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$streak',
                key: const Key('streak-count'),
                style: AppText.title.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppSpace.s1),
              Icon(Icons.local_fire_department, size: 28, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chi tiết chuỗi trong bottom sheet: ngọn lửa lớn + số ngày, và hàng 7 ngày
/// của tuần hiện tại (T2 → CN).
class _StreakDetail extends StatelessWidget {
  const _StreakDetail({required this.activity, required this.today});

  final Map<DateTime, int> activity;
  final DateTime today;

  static const _weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final streak = currentStreak(activity, today);
    final doneToday = (activity[today] ?? 0) > 0;
    final monday = addDays(today, -(today.weekday - 1));
    final flameColor = doneToday ? p.accent : p.outline;

    final String message;
    if (doneToday) {
      message = 'Hôm nay đã giữ chuỗi';
    } else if (streak > 0) {
      message = 'Làm 1 block hôm nay để giữ chuỗi';
    } else {
      message = 'Làm 1 block để bắt đầu chuỗi mới';
    }

    return Padding(
      key: const Key('streak-detail'),
      padding: const EdgeInsets.all(AppSpace.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 40, color: flameColor),
              const SizedBox(width: AppSpace.s2),
              Text(
                '$streak',
                style: AppText.display.copyWith(
                  color: doneToday ? p.accent : p.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppSpace.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ngày liên tiếp', style: AppText.label),
                    Text(
                      message,
                      style: AppText.caption.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                _StreakDay(
                  label: _weekdayLabels[i],
                  day: addDays(monday, i),
                  today: today,
                  active: (activity[addDays(monday, i)] ?? 0) > 0,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakDay extends StatelessWidget {
  const _StreakDay({
    required this.label,
    required this.day,
    required this.today,
    required this.active,
  });

  final String label;
  final DateTime day;
  final DateTime today;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isToday = day == today;
    final isFuture = day.isAfter(today);

    return Column(
      children: [
        Text(
          label,
          style: AppText.caption.copyWith(
            color: isToday ? p.ink : p.inkMuted,
            fontWeight: isToday ? FontWeight.w600 : null,
          ),
        ),
        const SizedBox(height: AppSpace.s1),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? p.accent : Colors.transparent,
            border: Border.all(
              color: isToday
                  ? p.accent
                  : p.outline.withValues(alpha: isFuture ? 0.3 : 0.6),
              width: isToday ? 2 : 1,
            ),
          ),
          child: active
              ? Icon(Icons.local_fire_department, size: 18, color: p.onAccent)
              : null,
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.exercise, required this.progress});

  final Exercise exercise;
  final Map<String, ExerciseProgress> progress;

  @override
  Widget build(BuildContext context) {
    final written =
        progress[exercise.id]?.drafts.values
            .where((code) => code.trim().isNotEmpty)
            .length ??
        0;
    final total = exercise.blocks.length;

    return SurfaceCard(
      key: const Key('continue-card'),
      onTap: () => context.push('/exercise/${exercise.id}'),
      highlighted: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tiếp tục: ${exercise.title}', style: AppText.title),
                  const SizedBox(height: AppSpace.s1),
                  Text(
                    '$written/$total ô đã viết',
                    style: AppText.body.copyWith(
                      color: context.palette.inkMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpace.s2),
                  ThinProgressBar(
                    value: total == 0 ? 0 : (written / total).clamp(0.0, 1.0),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.s4),
            Icon(Icons.arrow_forward, color: context.palette.ink),
          ],
        ),
      ),
    );
  }
}

/// Thẻ ôn tập đến hạn: chạm để sang tab Ôn tập.
class _DueCard extends StatelessWidget {
  const _DueCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      key: const Key('due-card'),
      onTap: () => context.go('/review'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Row(
          children: [
            Icon(Icons.style, color: p.accent),
            const SizedBox(width: AppSpace.s2),
            Expanded(child: Text('$count thẻ cần ôn', style: AppText.title)),
            Icon(Icons.arrow_forward, color: p.ink),
          ],
        ),
      ),
    );
  }
}

/// Thẻ chủ đề: 1 cột dưới [AppBreakpoint.nav], 2 cột từ nav, 3 cột từ split.
class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({required this.themes, required this.progress});

  final List<StudyTheme> themes;
  final Map<String, ExerciseProgress> progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= AppBreakpoint.split
            ? 3
            : w >= AppBreakpoint.nav
            ? 2
            : 1;
        const gap = AppSpace.s4;
        final cardWidth = (w - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < themes.length; i++)
              SizedBox(
                width: cardWidth,
                child: _ThemeCard(
                  theme: themes[i],
                  progress: progress,
                  gradient: AppGradients.all[i % AppGradients.all.length],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Số block đã xong / tổng số block trong một tập exercise. Dùng chung cho
/// tiến độ theme (Home) và tiến độ topic (Theme detail) — cùng đơn vị "block"
/// để người dùng không nhầm với "n/m bài tập".
int completedBlocksIn(
  Iterable<Exercise> exercises,
  Map<String, ExerciseProgress> progress,
) {
  var done = 0;
  for (final exercise in exercises) {
    final completed = progress[exercise.id]?.completedBlocks ?? 0;
    done += completed.clamp(0, exercise.blocks.length);
  }
  return done;
}

int totalBlocksIn(Iterable<Exercise> exercises) =>
    exercises.fold<int>(0, (sum, exercise) => sum + exercise.blocks.length);

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.progress,
    required this.gradient,
  });

  final StudyTheme theme;
  final Map<String, ExerciseProgress> progress;
  final AppGradientPair gradient;

  @override
  Widget build(BuildContext context) {
    final exercises = [for (final file in theme.allFiles) ...file.exercises];
    final total = totalBlocksIn(exercises);
    final done = completedBlocksIn(exercises, progress);
    final radius = BorderRadius.circular(AppRadius.xl);
    const white = Colors.white;
    const whiteMuted = Color(0xE6FFFFFF);

    return DecoratedBox(
      key: Key('theme-${theme.id}'),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: gradient.gradient,
        boxShadow: [
          BoxShadow(color: gradient.start, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/theme/${theme.id}'),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(theme.name, style: AppText.title.copyWith(color: white)),
                const SizedBox(height: AppSpace.s1),
                Text(
                  theme.description,
                  style: AppText.body.copyWith(color: whiteMuted),
                ),
                const SizedBox(height: AppSpace.s2),
                Wrap(
                  spacing: AppSpace.s2,
                  runSpacing: AppSpace.s2,
                  children: [for (final tag in theme.tags) TagChip(tag)],
                ),
                const SizedBox(height: AppSpace.s4),
                Row(
                  children: [
                    Expanded(
                      child: ThinProgressBar(
                        value: total == 0 ? 0 : done / total,
                        color: white,
                      ),
                    ),
                    const SizedBox(width: AppSpace.s2),
                    Text(
                      '$done/$total block',
                      style: AppText.caption.copyWith(color: whiteMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
