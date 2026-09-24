/// Tab Ôn tập: flashcard từ các block đã làm đúng. Ba cách ôn — Thẻ (lật
/// xem đáp án), Gõ lại (gõ cả dòng), Điền (điền từ bị ẩn) — rồi tự đánh
/// giá Khó / Được / Dễ để xếp lịch ôn tiếp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/theme_mode.dart';
import '../../domain/answer_checker.dart';
import '../../shared/widgets.dart';
import '../exercise/session_providers.dart';
import '../stats/activity.dart';
import 'review_controller.dart';

enum ReviewMode { card, retype, fill }

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  ReviewMode _mode = ReviewMode.card;

  @override
  Widget build(BuildContext context) {
    final due = ref.watch(dueCardsProvider);
    final upcoming = ref.watch(upcomingCardsProvider);
    final today = dayOf(ref.read(clockProvider)());

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Ôn tập',
              subtitle: due.isEmpty
                  ? 'Không còn thẻ đến hạn'
                  : 'Còn ${due.length} thẻ đến hạn',
              trailing: const ThemeModeButton(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  SegmentedButton<ReviewMode>(
                    key: const Key('review-mode'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ReviewMode.card, label: Text('Thẻ')),
                      ButtonSegment(
                        value: ReviewMode.retype,
                        label: Text('Gõ lại'),
                      ),
                      ButtonSegment(
                        value: ReviewMode.fill,
                        label: Text('Điền'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: AppSpace.s4),
                  if (due.isEmpty)
                    const _EmptyState()
                  else
                    _ReviewCardView(
                      // Đổi thẻ hoặc chế độ thì dựng lại từ đầu (ẩn đáp án,
                      // xoá ô nhập).
                      key: ValueKey('${due.first.card.id}-${_mode.name}'),
                      card: due.first.card,
                      mode: _mode,
                    ),
                  const SizedBox(height: AppSpace.s6),
                  if (upcoming.isNotEmpty) ...[
                    const SectionLabel('Sắp đến hạn'),
                    for (final s in upcoming.take(5)) ...[
                      _UpcomingRow(scheduled: s, today: today),
                      const SizedBox(height: AppSpace.s2),
                    ],
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      key: const Key('review-empty'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s6),
        child: Column(
          children: [
            Icon(Icons.task_alt, size: 32, color: p.primary),
            const SizedBox(height: AppSpace.s2),
            const Text('Đã ôn hết thẻ hôm nay', style: AppText.title),
            const SizedBox(height: AppSpace.s1),
            Text(
              'Làm thêm block mới để có thêm thẻ ôn.',
              style: AppText.body.copyWith(color: p.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCardView extends ConsumerStatefulWidget {
  const _ReviewCardView({super.key, required this.card, required this.mode});

  final ReviewCard card;
  final ReviewMode mode;

  @override
  ConsumerState<_ReviewCardView> createState() => _ReviewCardViewState();
}

class _ReviewCardViewState extends ConsumerState<_ReviewCardView> {
  final _input = TextEditingController();
  bool _revealed = false;
  bool? _correct;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _check() {
    final block = widget.card.block;
    final bool ok;
    if (widget.mode == ReviewMode.fill) {
      ok = _input.text.trim() == fillBlank(block)?.missing;
    } else {
      ok = runBlock(_input.text, block).passed;
    }
    setState(() {
      _correct = ok;
      _revealed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = widget.card;
    final block = card.block;
    final answer = block.acceptedAnswers.first;
    final blank = fillBlank(block);
    // Block không có từ nào để ẩn thì chế độ Điền quay về kiểu Thẻ.
    final mode = widget.mode == ReviewMode.fill && blank == null
        ? ReviewMode.card
        : widget.mode;

    return SurfaceCard(
      key: Key('review-card-${card.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${card.exercise.functionName}() · B${card.blockIndex + 1}',
              style: AppText.code.copyWith(color: p.inkMuted, fontSize: 12),
            ),
            const SizedBox(height: AppSpace.s2),
            Text(block.prompt, style: AppText.title),
            const SizedBox(height: AppSpace.s4),
            if (mode == ReviewMode.fill) ...[
              _CodeBox(text: blank!.masked),
              const SizedBox(height: AppSpace.s2),
            ],
            if (mode != ReviewMode.card && !_revealed) ...[
              TextField(
                key: const Key('review-input'),
                controller: _input,
                autocorrect: false,
                enableSuggestions: false,
                style: AppText.code.copyWith(color: p.ink),
                decoration: InputDecoration(
                  hintText: mode == ReviewMode.fill
                      ? 'Từ còn thiếu'
                      : 'Gõ lại dòng code',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _check(),
              ),
              const SizedBox(height: AppSpace.s2),
              PrimaryButton(
                key: const Key('review-check'),
                label: 'Kiểm tra',
                onPressed: _check,
              ),
            ],
            if (mode == ReviewMode.card && !_revealed)
              GhostButton(
                key: const Key('review-reveal'),
                label: 'Hiện đáp án',
                onPressed: () => setState(() => _revealed = true),
              ),
            if (_revealed) ...[
              if (_correct != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: ResultBadge(passed: _correct!),
                ),
                const SizedBox(height: AppSpace.s2),
              ],
              const SectionLabel('Đáp án'),
              _CodeBox(text: answer),
              const SizedBox(height: AppSpace.s4),
              Text(
                'Bạn nhớ bài này thế nào?',
                style: AppText.label.copyWith(color: p.inkMuted),
              ),
              const SizedBox(height: AppSpace.s2),
              Row(
                children: [
                  for (final (rating, label) in const [
                    (ReviewRating.hard, 'Khó'),
                    (ReviewRating.ok, 'Được'),
                    (ReviewRating.easy, 'Dễ'),
                  ]) ...[
                    if (rating != ReviewRating.hard)
                      const SizedBox(width: AppSpace.s2),
                    Expanded(
                      child: _RateButton(
                        rating: rating,
                        label: label,
                        onPressed: () => ref
                            .read(reviewScheduleProvider.notifier)
                            .rate(card.id, rating),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton({
    required this.rating,
    required this.label,
    required this.onPressed,
  });

  final ReviewRating rating;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = switch (rating) {
      ReviewRating.hard => p.danger,
      ReviewRating.ok => p.ink,
      ReviewRating.easy => p.primary,
    };
    return OutlinedButton(
      key: Key('rate-${rating.name}'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: Text(label),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s2 + AppSpace.s1),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.outline),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SelectableText(text, style: AppText.code.copyWith(color: p.ink)),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.scheduled, required this.today});

  final ScheduledCard scheduled;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final days = (scheduled.due.difference(today).inHours / 24).round();
    final when = days <= 1 ? 'Ngày mai' : 'Sau $days ngày';
    final card = scheduled.card;
    return SurfaceCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s4,
          vertical: AppSpace.s2 + AppSpace.s1,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.block.title, style: AppText.label),
                  Text(
                    '${card.exercise.functionName}() · B${card.blockIndex + 1}',
                    style: AppText.caption.copyWith(color: p.inkMuted),
                  ),
                ],
              ),
            ),
            Text(when, style: AppText.caption.copyWith(color: p.inkMuted)),
          ],
        ),
      ),
    );
  }
}
