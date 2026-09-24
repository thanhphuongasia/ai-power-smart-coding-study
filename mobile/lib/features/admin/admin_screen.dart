/// Màn Admin: duyệt nội dung Claude sinh qua MCP trước khi người học thấy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import 'admin_controller.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(adminProvider);
    final pending = items
        .where((i) => i.status == ApprovalStatus.pending)
        .toList();
    final handled = items
        .where((i) => i.status != ApprovalStatus.pending)
        .toList();
    final approved = handled
        .where((i) => i.status == ApprovalStatus.approved)
        .length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Duyệt nội dung',
              subtitle:
                  '${pending.length} chờ duyệt · $approved đã duyệt · '
                  '${handled.length - approved} đã từ chối',
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s4),
                children: [
                  const SectionLabel('Claude tạo qua MCP · chờ duyệt'),
                  if (pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpace.s4,
                      ),
                      child: Text(
                        'Không còn nội dung chờ duyệt.',
                        key: const Key('admin-empty'),
                        style: AppText.body.copyWith(
                          color: context.palette.inkMuted,
                        ),
                      ),
                    ),
                  for (final item in pending) ...[
                    _PendingCard(item: item),
                    const SizedBox(height: AppSpace.s4),
                  ],
                  if (handled.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.s2),
                    const SectionLabel('Đã xử lý'),
                    for (final item in handled) ...[
                      _HandledRow(item: item),
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

class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.item});

  final PendingContent item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final isCode = item.kind == ContentKind.exercise;
    final kind = isCode ? 'Bài tập · ${item.target}' : item.target;

    return SurfaceCard(
      key: Key('pending-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    kind,
                    style: AppText.caption.copyWith(color: p.inkMuted),
                  ),
                ),
                Text(
                  item.size,
                  style: AppText.caption.copyWith(color: p.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s1),
            Text(
              item.title,
              style: isCode
                  ? AppText.code.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w500,
                    )
                  : AppText.title,
            ),
            const SizedBox(height: AppSpace.s1),
            Text(
              item.description,
              style: AppText.body.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: AppSpace.s2),
            Wrap(
              spacing: AppSpace.s2,
              runSpacing: AppSpace.s2,
              children: [for (final t in item.tags) TagChip(t)],
            ),
            if (item.hintPreview != null) ...[
              const SizedBox(height: AppSpace.s4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.s2 + AppSpace.s1),
                decoration: BoxDecoration(
                  border: Border.all(color: p.accent),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gợi ý mức 1 (mờ)',
                      style: AppText.caption.copyWith(color: p.inkMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(item.hintPreview!, style: AppText.body),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpace.s4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('reject-${item.id}'),
                    onPressed: () =>
                        ref.read(adminProvider.notifier).reject(item.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.danger,
                      side: BorderSide(color: p.danger),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Text('Từ chối'),
                  ),
                ),
                const SizedBox(width: AppSpace.s2),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    key: Key('approve-${item.id}'),
                    label: 'Duyệt',
                    icon: Icons.check,
                    onPressed: () =>
                        ref.read(adminProvider.notifier).approve(item.id),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HandledRow extends ConsumerWidget {
  const _HandledRow({required this.item});

  final PendingContent item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final approved = item.status == ApprovalStatus.approved;
    return SurfaceCard(
      key: Key('handled-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpace.s4, right: AppSpace.s1),
        child: Row(
          children: [
            Icon(
              approved ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: approved ? p.primary : p.danger,
            ),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: AppText.label),
                  Text(
                    approved ? 'Đã duyệt' : 'Đã từ chối',
                    style: AppText.caption.copyWith(
                      color: approved ? p.primary : p.danger,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: Key('undo-${item.id}'),
              onPressed: () => ref.read(adminProvider.notifier).undo(item.id),
              child: const Text('Hoàn tác'),
            ),
          ],
        ),
      ),
    );
  }
}
