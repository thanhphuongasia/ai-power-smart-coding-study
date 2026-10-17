/// Tab Design: danh sách tài liệu System Design + tiến độ mỗi tài liệu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/theme_mode.dart';
import '../../data/sd_repository.dart';
import '../../domain/sd_models.dart';
import '../../shared/widgets.dart';

/// Thông điệp ngắn cho lỗi tải; 401 → yêu cầu đăng nhập.
String sdErrorMessage(Object error) {
  if (error is SdApiException) {
    return error.statusCode == 401
        ? 'Cần đăng nhập'
        : 'Không tải được (mã ${error.statusCode})';
  }
  return 'Không tải được. Kiểm tra kết nối rồi thử lại.';
}

/// Khối lỗi dùng chung cho hai màn System Design: thông điệp + nút Thử lại.
class SdErrorView extends StatelessWidget {
  const SdErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('sd-error'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sdErrorMessage(error),
              textAlign: TextAlign.center,
              style: AppText.body,
            ),
            const SizedBox(height: AppSpace.s4),
            GhostButton(
              key: const Key('sd-retry'),
              label: 'Thử lại',
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class SdDocsScreen extends ConsumerWidget {
  const SdDocsScreen({super.key = const Key('sd-docs-screen')});

  /// Kéo để làm mới: chờ tải xong, lỗi thì để UI tự hiện (không ném ra ngoài).
  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(sdDocsProvider);
    try {
      await ref.read(sdDocsProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(sdDocsProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'System Design',
              subtitle: 'Đọc tài liệu rồi thiết kế thật',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RefreshButton(
                    key: const Key('refresh-button'),
                    loading: docs.isLoading,
                    onPressed: () => _refresh(ref),
                  ),
                  const ThemeModeButton(),
                ],
              ),
            ),
            Expanded(
              child: docs.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => SdErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(sdDocsProvider),
                ),
                data: (items) => RefreshIndicator(
                  onRefresh: () => _refresh(ref),
                  child: items.isEmpty
                      ? const _EmptyDocs()
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(AppSpace.s4),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpace.s4),
                          itemBuilder: (_, i) => _DocCard(doc: items[i]),
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

/// Rỗng vẫn cuộn được để kéo-làm-mới hoạt động.
class _EmptyDocs extends StatelessWidget {
  const _EmptyDocs();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('sd-empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.s6),
      children: [
        const SizedBox(height: AppSpace.s6),
        const Text(
          'Chưa có tài liệu nào',
          textAlign: TextAlign.center,
          style: AppText.title,
        ),
        const SizedBox(height: AppSpace.s2),
        Text(
          'Admin nhập file .md để bắt đầu',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: context.palette.inkMuted),
        ),
      ],
    );
  }
}

class _DocCard extends ConsumerWidget {
  const _DocCard({required this.doc});

  final SdDocSummary doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final progress = doc.cards == 0 ? 0.0 : doc.cardsRead / doc.cards;
    return SurfaceCard(
      key: Key('sd-doc-${doc.id}'),
      onTap: () async {
        await context.push('/design/${Uri.encodeComponent(doc.id)}');
        // Quay lại: tiến độ có thể đã đổi ở màn đọc/làm task → tải lại.
        if (!context.mounted) return;
        ref.invalidate(sdDocsProvider);
        ref.invalidate(sdDocProvider(doc.id));
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(doc.title, style: AppText.title)),
                if (doc.phase2Unlocked) ...[
                  const SizedBox(width: AppSpace.s2),
                  const TagChip('Thực chiến mở'),
                ],
              ],
            ),
            const SizedBox(height: AppSpace.s2),
            Text(
              '${doc.sectionsDone}/${doc.sections} section · '
              '${doc.cardsRead}/${doc.cards} card',
              style: AppText.body.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: AppSpace.s2),
            ThinProgressBar(value: progress),
          ],
        ),
      ),
    );
  }
}
