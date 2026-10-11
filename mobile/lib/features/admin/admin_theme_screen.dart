/// Màn Admin cấp 2: module cấp trên cùng của một project.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import 'admin_controller.dart';
import 'admin_widgets.dart';

class AdminThemeScreen extends ConsumerWidget {
  const AdminThemeScreen({super.key, required this.themeId});
  final String themeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(adminProvider.notifier);
    return AdminLevelScaffold(
      crumbsOf: (s) {
        final t = findTheme(s, themeId);
        return [
          const Crumb('projects', 'Projects', '/admin'),
          Crumb(
            'theme',
            t == null ? themeId : nameOf(t),
            '/admin/theme/$themeId',
          ),
        ];
      },
      body: (context, s) {
        final theme = findTheme(s, themeId);
        if (theme == null) {
          return Center(
            key: const Key('admin-not-found'),
            child: Text(
              'Không tìm thấy project này.',
              style: AppText.body.copyWith(color: context.palette.inkMuted),
            ),
          );
        }
        final withErrors = exerciseIdsWithErrors(s.errors);
        return AdminList(
          children: [
            for (final m in topicsOf(theme))
              moduleCard(context, ref, m, withErrors),
            AdminAddButton(
              key: const Key('add-module'),
              label: 'Thêm module',
              onPressed: () async {
                final r = await adminEditDialog(
                  context,
                  withDesc: true,
                  nameLabel: 'Tên module',
                );
                if (r != null && r.name.isNotEmpty) {
                  ctl.addModule(
                    themeId,
                    r.name,
                    description: r.description ?? '',
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}

/// Thẻ module dùng ở cấp 2 và cho module con ở cấp 3.
Widget moduleCard(
  BuildContext context,
  WidgetRef ref,
  Json module,
  Set<String> withErrors,
) {
  final id = module['id'] as String;
  final ids = moduleExerciseIds(module);
  return AdminLevelCard(
    key: Key('module-$id-card'),
    title: nameOf(module),
    description: module['description'] as String?,
    meta: '${moduleFileCount(module)} file · ${ids.length} bài',
    hasError: ids.any(withErrors.contains),
    errorKey: Key('module-$id-error'),
    onTap: () => context.push('/admin/module/$id'),
    trailing: [
      AdminActionMenu(
        menuKey: 'module-$id-menu',
        entries: [
          AdminMenuEntry('rename', 'Đổi tên / mô tả', () async {
            final r = await adminEditDialog(
              context,
              node: module,
              withDesc: true,
            );
            if (r != null && r.name.isNotEmpty) {
              ref
                  .read(adminProvider.notifier)
                  .updateNode(id, name: r.name, description: r.description);
            }
          }),
        ],
      ),
    ],
  );
}
