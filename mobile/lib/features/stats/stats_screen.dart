/// Tab Tiến độ: số liệu tổng, heatmap hoạt động 4 tuần và mức thành thạo
/// theo chủ đề nhỏ (topic).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/theme_mode.dart';
import '../../data/seed.dart';
import '../../shared/widgets.dart';
import '../browse/home_screen.dart' show completedBlocksIn, totalBlocksIn;
import '../exercise/session_providers.dart';
import '../review/review_controller.dart';
import 'activity.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final activity = ref.watch(activityProvider);
    final dueCount = ref.watch(dueCardsProvider).length;
    final today = dayOf(ref.read(clockProvider)());

    final exercises = uniqueExercises();
    final doneBlocks = completedBlocksIn(exercises, progress);
    var noHint = 0;
    for (final exercise in exercises) {
      final p = progress[exercise.id];
      final completed = (p?.completedBlocks ?? 0).clamp(
        0,
        exercise.blocks.length,
      );
      for (var i = 0; i < completed; i++) {
        if ((p?.hintsUsed[exercise.blocks[i].id] ?? 0) == 0) noHint++;
      }
    }
    final noHintPct = doneBlocks == 0 ? 0 : (noHint * 100 / doneBlocks).round();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Tiến độ', trailing: ThemeModeButton()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpace.s2,
                    crossAxisSpacing: AppSpace.s2,
                    childAspectRatio: 1.9,
                    children: [
                      _StatTile(
                        key: const Key('stat-blocks'),
                        value: '$doneBlocks',
                        label: 'Block đã xong',
                      ),
                      _StatTile(
                        key: const Key('stat-streak'),
                        value: '${currentStreak(activity, today)}',
                        label: 'Ngày liên tiếp',
                      ),
                      _StatTile(
                        key: const Key('stat-no-hint'),
                        value: '$noHintPct%',
                        label: 'Không cần gợi ý',
                      ),
                      _StatTile(
                        key: const Key('stat-due'),
                        value: '$dueCount',
                        label: 'Thẻ cần ôn',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s6),
                  const SectionLabel('Hoạt động 4 tuần'),
                  _Heatmap(activity: activity, today: today),
                  const SizedBox(height: AppSpace.s6),
                  const SectionLabel('Mức thành thạo theo chủ đề nhỏ'),
                  for (final theme in seedThemes)
                    for (final topic in theme.topics) ...[
                      _MasteryRow(
                        label: topic.name,
                        caption: theme.name,
                        done: completedBlocksIn([
                          for (final f in topic.files) ...f.exercises,
                        ], progress),
                        total: totalBlocksIn([
                          for (final f in topic.files) ...f.exercises,
                        ]),
                      ),
                      const SizedBox(height: AppSpace.s4),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s2 + AppSpace.s1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: AppText.display.copyWith(
                color: p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(label, style: AppText.caption.copyWith(color: p.inkMuted)),
          ],
        ),
      ),
    );
  }
}

/// Lưới 4 tuần × 7 ngày, mỗi hàng một tuần (cũ → mới), ô cuối là hôm nay.
/// Độ đậm theo số hoạt động: 0 / 1 / 2–3 / 4+.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.activity, required this.today});

  final Map<DateTime, int> activity;
  final DateTime today;

  static const _weeks = 4;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final days = [for (var i = _weeks * 7 - 1; i >= 0; i--) addDays(today, -i)];
    final activeDays = days.where((d) => (activity[d] ?? 0) > 0).length;

    Color cellColor(int count) => switch (count) {
      0 => p.surface,
      1 => p.primary.withValues(alpha: 0.35),
      2 || 3 => p.primary.withValues(alpha: 0.65),
      _ => p.primary,
    };

    return Semantics(
      label: '$activeDays trên ${days.length} ngày có hoạt động',
      excludeSemantics: true,
      child: SurfaceCard(
        key: const Key('stats-heatmap'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 4.0;
                  final size = ((constraints.maxWidth - gap * 6) / 7).clamp(
                    8.0,
                    28.0,
                  );
                  return Column(
                    children: [
                      for (var w = 0; w < _weeks; w++) ...[
                        if (w > 0) const SizedBox(height: gap),
                        Row(
                          children: [
                            for (var d = 0; d < 7; d++) ...[
                              if (d > 0) const SizedBox(width: gap),
                              _HeatCell(
                                size: size,
                                color: cellColor(
                                  activity[days[w * 7 + d]] ?? 0,
                                ),
                                isToday: w * 7 + d == days.length - 1,
                                outline: p.outline,
                                todayColor: p.ink,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpace.s2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$activeDays/${days.length} ngày có hoạt động',
                      style: AppText.caption.copyWith(color: p.inkMuted),
                    ),
                  ),
                  Text(
                    'Ít',
                    style: AppText.caption.copyWith(color: p.inkMuted),
                  ),
                  for (final c in [0, 1, 2, 4]) ...[
                    const SizedBox(width: 3),
                    _HeatCell(
                      size: 10,
                      color: cellColor(c),
                      isToday: false,
                      outline: p.outline,
                      todayColor: p.ink,
                    ),
                  ],
                  const SizedBox(width: 3),
                  Text(
                    'Nhiều',
                    style: AppText.caption.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.size,
    required this.color,
    required this.isToday,
    required this.outline,
    required this.todayColor,
  });

  final double size;
  final Color color;
  final bool isToday;
  final Color outline;
  final Color todayColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isToday ? todayColor : outline.withValues(alpha: 0.5),
          width: isToday ? 1.5 : 1,
        ),
      ),
    );
  }
}

class _MasteryRow extends StatelessWidget {
  const _MasteryRow({
    required this.label,
    required this.caption,
    required this.done,
    required this.total,
  });

  final String label;
  final String caption;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ratio = total == 0 ? 0.0 : done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: AppText.label.copyWith(color: p.ink),
                    ),
                    TextSpan(
                      text: '  $caption',
                      style: AppText.caption.copyWith(color: p.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              '${(ratio * 100).round()}%',
              style: AppText.label.copyWith(
                color: p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s1),
        ThinProgressBar(value: ratio),
      ],
    );
  }
}
