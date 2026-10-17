/// Màn "Tài liệu System Design": publish / ẩn / khôi phục từng tài liệu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/admin_repository.dart';
import '../../shared/widgets.dart';

const _statusLabels = {
  'published': 'Đã publish',
  'draft': 'Bản nháp',
  'archived': 'Đã xoá mềm',
};

String _errorMessage(AdminError e) {
  final base =
      e.message ??
      switch (e.kind) {
        AdminErrorKind.forbidden => 'Bạn không có quyền admin.',
        AdminErrorKind.network => 'Không kết nối được máy chủ.',
        AdminErrorKind.conflict => 'Tài liệu đã đổi, hãy tải lại danh sách.',
        AdminErrorKind.invalid => 'Server từ chối thao tác này.',
        AdminErrorKind.server => 'Lỗi máy chủ.',
      };
  return e.errors.isEmpty ? base : '$base ${e.errors.join('; ')}';
}

class AdminSdDocsScreen extends ConsumerStatefulWidget {
  const AdminSdDocsScreen({super.key});

  @override
  ConsumerState<AdminSdDocsScreen> createState() => _AdminSdDocsScreenState();
}

class _AdminSdDocsScreenState extends ConsumerState<AdminSdDocsScreen> {
  List<AdminSdDoc>? _docs;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _docs == null;
    });
    try {
      final list = await ref.read(adminRepositoryProvider).sdDocs();
      if (!mounted) return;
      setState(() {
        _docs = list;
        _error = null;
        _loading = false;
      });
    } on AdminError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(AdminSdDoc d, String status) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    try {
      await ref.read(adminRepositoryProvider).setSdDocStatus(d.id, status);
    } on AdminError catch (e) {
      err = _errorMessage(e);
    }
    if (!mounted) return;
    // Tải lại cả khi lỗi: 404/409 thường do danh sách cũ.
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err != null) _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final docs = _docs;
    return Scaffold(
      key: const Key('admin-sd-docs'),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Tài liệu System Design',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/admin'),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        key: const Key('sd-docs-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpace.s4),
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpace.s2,
                              ),
                              child: Text(
                                _error!,
                                key: const Key('sd-docs-error'),
                                style: AppText.body.copyWith(color: p.danger),
                              ),
                            ),
                          if (docs == null)
                            GhostButton(
                              key: const Key('sd-docs-retry'),
                              label: 'Thử lại',
                              onPressed: _load,
                            )
                          else if (docs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.s6),
                              child: Center(
                                child: Text(
                                  'Chưa có tài liệu nào',
                                  key: const Key('sd-docs-empty'),
                                  style: AppText.body.copyWith(
                                    color: p.inkMuted,
                                  ),
                                ),
                              ),
                            )
                          else
                            for (final d in docs) ...[
                              _DocTile(
                                doc: d,
                                busy: _busy,
                                onSetStatus: (s) => _setStatus(d, s),
                              ),
                              const SizedBox(height: AppSpace.s2),
                            ],
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

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.doc,
    required this.busy,
    required this.onSetStatus,
  });

  final AdminSdDoc doc;
  final bool busy;
  final void Function(String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = doc;
    final (keyPrefix, label, target) = switch (d.status) {
      'published' => ('sd-unpublish', 'Ẩn', 'draft'),
      'archived' => ('sd-restore', 'Khôi phục', 'draft'),
      _ => ('sd-publish', 'Publish', 'published'),
    };
    return Material(
      color: p.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusLabels[d.status] ?? d.status,
              key: Key('sd-status-${d.id}'),
              style: AppText.label.copyWith(color: p.primary),
            ),
            const SizedBox(height: AppSpace.s1),
            Text(d.title, style: AppText.body),
            Text(
              '${d.sections} section · ${d.cards} card',
              style: AppText.caption.copyWith(color: p.inkMuted),
            ),
            const SizedBox(height: AppSpace.s2),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: Key('$keyPrefix-${d.id}'),
                onPressed: busy ? null : () => onSetStatus(target),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
