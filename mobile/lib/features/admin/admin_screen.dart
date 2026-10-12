/// Màn Admin cấp 1: danh sách project (theme). Chạm một project để xuống cấp
/// module; mọi thao tác lưu nằm ở thanh lưu ghim đáy (admin_widgets.dart).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/widgets.dart';
import 'admin_controller.dart';
import 'admin_widgets.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(adminProvider.notifier);
    return AdminLevelScaffold(
      crumbsOf: (_) => const [Crumb('projects', 'Projects', '/admin')],
      body: (context, s) {
        final withErrors = exerciseIdsWithErrors(s.errors);
        return AdminList(
          key: const Key('admin-tree'),
          children: [
            GhostButton(
              key: const Key('admin-review-button'),
              label: 'Chờ duyệt (${s.pendingCount})',
              onPressed: () => context.push('/admin/review'),
            ),
            for (final t in s.themes)
              _themeCard(context, ref, t, withErrors, s),
            AdminAddButton(
              key: const Key('add-theme'),
              label: 'Thêm project',
              onPressed: () async {
                final r = await adminEditDialog(
                  context,
                  withDesc: true,
                  nameLabel: 'Tên project',
                );
                if (r != null && r.name.isNotEmpty) {
                  ctl.addTheme(r.name, description: r.description ?? '');
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _themeCard(
    BuildContext context,
    WidgetRef ref,
    Json theme,
    Set<String> withErrors,
    AdminState s,
  ) {
    final id = theme['id'] as String;
    final ctl = ref.read(adminProvider.notifier);
    final topics = topicsOf(theme);
    final exerciseIds = {for (final m in topics) ...moduleExerciseIds(m)};
    return AdminLevelCard(
      key: Key('theme-$id-card'),
      title: nameOf(theme),
      description: theme['description'] as String?,
      meta: '${topics.length} module · ${exerciseIds.length} bài',
      hasError: exerciseIds.any(withErrors.contains),
      errorKey: Key('theme-$id-error'),
      badge: s.isPending('project', id)
          ? PendingBadge(key: Key('theme-$id-pending'))
          : null,
      onTap: () => context.push('/admin/theme/$id'),
      trailing: [
        IconButton(
          key: Key('theme-$id-diagram'),
          icon: const Icon(Icons.account_tree_outlined),
          tooltip: 'Sơ đồ class',
          onPressed: () => _diagramDialog(context, ref, theme),
        ),
        AdminActionMenu(
          menuKey: 'theme-$id-menu',
          entries: [
            AdminMenuEntry('rename', 'Đổi tên / mô tả', () async {
              final r = await adminEditDialog(
                context,
                node: theme,
                withDesc: true,
              );
              if (r != null && r.name.isNotEmpty) {
                ctl.updateNode(id, name: r.name, description: r.description);
              }
            }),
          ],
        ),
      ],
    );
  }
}

Future<void> _diagramDialog(BuildContext context, WidgetRef ref, Json theme) {
  final id = theme['id'] as String;
  final text = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert(theme['diagram'] ?? {}),
  );
  return showDialog<void>(
    context: context,
    builder: (c) {
      String? error;
      return StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('Sơ đồ class · ${theme['name']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              key: Key('theme-$id-diagram-field'),
              controller: text,
              maxLines: 14,
              style: AppText.code,
              decoration: InputDecoration(errorText: error),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Đóng'),
            ),
            TextButton(
              key: Key('theme-$id-diagram-apply'),
              onPressed: () {
                try {
                  final v = jsonDecode(text.text);
                  if (v is! Map<String, dynamic>) {
                    throw const FormatException('Phải là một object JSON');
                  }
                  ref.read(adminProvider.notifier).replaceDiagram(id, v);
                  Navigator.pop(c);
                } on FormatException catch (e) {
                  setState(() => error = 'JSON lỗi: ${e.message}');
                }
              },
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      );
    },
  );
}
