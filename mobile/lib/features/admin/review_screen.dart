/// Màn "Chờ duyệt": danh sách mục admin đã gửi, duyệt hoặc bỏ từng mục.
/// Chạm một dòng để xem chi tiết (review_detail_screen.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/admin_repository.dart';
import '../../shared/widgets.dart';
import 'admin_controller.dart';

const _kindLabels = {
  'project': 'Project',
  'module': 'Module',
  'file': 'File',
  'exercise': 'Bài',
};

const _actionLabels = {'create': 'Thêm', 'update': 'Sửa', 'delete': 'Xoá'};

String kindLabel(String kind) => _kindLabels[kind] ?? kind;
String actionLabel(String action) => _actionLabels[action] ?? action;

/// Tên/tiêu đề để hiển thị: lấy từ after (hoặc before nếu xoá), rơi về id.
String changeTitle(ContentChange c) {
  for (final side in [c.after, c.before]) {
    final fields = side?['fields'];
    if (fields is Map) {
      final v = fields['name'] ?? fields['title'];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  return c.itemId;
}

/// "2026-10-11T00:00:00Z" -> "2026-10-11 00:00".
String shortTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final t = iso.replaceFirst('T', ' ');
  return t.length > 16 ? t.substring(0, 16) : t;
}

String _errorMessage(AdminError e) =>
    e.message ??
    switch (e.kind) {
      AdminErrorKind.forbidden => 'Bạn không có quyền admin.',
      AdminErrorKind.network => 'Không kết nối được máy chủ.',
      AdminErrorKind.conflict => 'Mục này đã đổi, hãy tải lại danh sách.',
      AdminErrorKind.invalid => 'Server từ chối nội dung.',
      AdminErrorKind.server => 'Lỗi máy chủ.',
    };

Future<void> showDecisionError(BuildContext context, AdminError e) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      key: const Key('review-error'),
      title: const Text('Không thực hiện được'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_errorMessage(e), key: const Key('review-error-message')),
            for (final line in e.errors)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s1),
                child: Text('• $line'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('review-error-close'),
          onPressed: () => Navigator.pop(c),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

/// Nội dung SnackBar sau khi duyệt/bỏ: ưu tiên notice của controller (vd reject
/// lúc đang có sửa chưa gửi), thêm "kèm N mục" nếu server duyệt/bỏ kèm.
String decisionMessage({
  required bool approve,
  ChangeResult? result,
  String? notice,
}) {
  final base = notice ?? (approve ? 'Đã duyệt' : 'Đã bỏ');
  final n = result?.also.length ?? 0;
  return n > 0 ? '$base (kèm $n mục)' : base;
}

/// Duyệt hoặc bỏ [c]. Bỏ thì hỏi xác nhận trước. Trả true khi server đã xử
/// lý xong; lỗi được hiện bằng dialog (không nuốt) và trả false.
Future<bool> decideChange(
  BuildContext context,
  WidgetRef ref,
  ContentChange c, {
  required bool approve,
}) async {
  final ctl = ref.read(adminProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  if (!approve) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Bỏ thay đổi này?'),
        content: Text(
          '${actionLabel(c.action)} ${kindLabel(c.kind).toLowerCase()} '
          '"${changeTitle(c)}" sẽ bị loại khỏi hàng chờ; nội dung học viên '
          'không đổi.',
        ),
        actions: [
          TextButton(
            key: const Key('reject-cancel'),
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Giữ lại'),
          ),
          TextButton(
            key: const Key('reject-confirm'),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Bỏ'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }
  final err = approve ? await ctl.approve(c.id) : await ctl.reject(c.id);
  if (err == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          decisionMessage(
            approve: approve,
            result: ctl.lastDecision,
            notice: ref.read(adminProvider).notice,
          ),
        ),
      ),
    );
    return true;
  }
  if (context.mounted) await showDecisionError(context, err);
  return false;
}

class AdminReviewScreen extends ConsumerStatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  ConsumerState<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends ConsumerState<AdminReviewScreen> {
  List<ContentChange>? _changes;
  AdminError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _changes == null;
      _error = null;
    });
    try {
      final list = await ref.read(adminProvider.notifier).changes();
      if (!mounted) return;
      setState(() {
        _changes = list;
        _loading = false;
      });
    } on AdminError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _decide(ContentChange c, {required bool approve}) async {
    await decideChange(context, ref, c, approve: approve);
    // Lỗi 404/409 thường do danh sách cũ: tải lại cho đúng thực tế.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(adminProvider.select((s) => s.busy));
    final p = context.palette;
    final changes = _changes;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Chờ duyệt',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/admin'),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        key: const Key('review-list'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpace.s4),
                        children: [
                          if (_error != null)
                            Column(
                              children: [
                                Text(
                                  _errorMessage(_error!),
                                  key: const Key('review-load-failed'),
                                  style: AppText.body.copyWith(color: p.danger),
                                ),
                                const SizedBox(height: AppSpace.s2),
                                GhostButton(
                                  key: const Key('review-retry'),
                                  label: 'Thử lại',
                                  onPressed: _load,
                                ),
                              ],
                            )
                          else if (changes == null || changes.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpace.s6),
                              child: Center(
                                child: Text(
                                  'Không có gì chờ duyệt',
                                  key: const Key('review-empty'),
                                  style: AppText.body.copyWith(
                                    color: p.inkMuted,
                                  ),
                                ),
                              ),
                            )
                          else
                            for (final c in changes) ...[
                              _ChangeTile(
                                change: c,
                                busy: busy,
                                onOpen: () async {
                                  await context.push('/admin/review/${c.id}');
                                  if (mounted) await _load();
                                },
                                onApprove: () => _decide(c, approve: true),
                                onReject: () => _decide(c, approve: false),
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

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({
    required this.change,
    required this.busy,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  final ContentChange change;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = change;
    final meta = [
      if (c.author != null) c.author!,
      shortTime(c.createdAt),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Material(
      color: p.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        key: Key('change-${c.id}'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${actionLabel(c.action)} · ${kindLabel(c.kind)}',
                style: AppText.label.copyWith(color: p.primary),
              ),
              const SizedBox(height: AppSpace.s1),
              Text(changeTitle(c), style: AppText.body),
              if (meta.isNotEmpty)
                Text(meta, style: AppText.caption.copyWith(color: p.inkMuted)),
              const SizedBox(height: AppSpace.s2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: Key('reject-${c.id}'),
                    onPressed: busy ? null : onReject,
                    child: const Text('Bỏ'),
                  ),
                  const SizedBox(width: AppSpace.s2),
                  FilledButton(
                    key: Key('approve-${c.id}'),
                    onPressed: busy ? null : onApprove,
                    child: const Text('Duyệt'),
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
