/// Màn Admin: soạn nội dung (theme → module → file → bài tập) và lưu lên server.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/admin_repository.dart';
import '../../shared/widgets.dart';
import 'admin_controller.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(adminProvider);
    final ctl = ref.read(adminProvider.notifier);
    final p = context.palette;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Soạn nội dung',
              subtitle: s.version == null ? null : 'Phiên bản ${s.version}',
              onBack: () => context.pop(),
            ),
            if (s.status == AdminStatus.loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (s.status == AdminStatus.failed)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.failure == AdminErrorKind.forbidden
                            ? 'Bạn không có quyền admin.'
                            : s.failure == AdminErrorKind.server
                            ? (s.failureMessage ?? 'Lỗi máy chủ')
                            : 'Không tải được nội dung.',
                        key: const Key('admin-load-failed'),
                        style: AppText.body.copyWith(color: p.danger),
                      ),
                      const SizedBox(height: AppSpace.s2),
                      OutlinedButton(
                        key: const Key('admin-retry'),
                        onPressed: ctl.load,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _TopBar(state: s),
              if (s.conflict) const _ConflictBanner(),
              if (s.errors.isNotEmpty || s.failure != null || s.notice != null)
                _MessagePanel(state: s),
              Expanded(child: _Tree(state: s)),
            ],
          ],
        ),
      ),
    );
  }
}

final _compact = ButtonStyle(
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
  visualDensity: VisualDensity.compact,
);

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.state});
  final AdminState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final ctl = ref.read(adminProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s4,
        vertical: AppSpace.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              state.dirty ? 'Chưa lưu' : 'Đã đồng bộ',
              key: const Key('admin-dirty'),
              style: AppText.label.copyWith(
                color: state.dirty ? p.danger : p.inkMuted,
              ),
            ),
          ),
          if (state.dirty)
            TextButton(
              key: const Key('admin-discard'),
              onPressed: state.busy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Hủy mọi sửa chưa lưu?'),
                          content: const Text(
                            'Sẽ tải lại bản trên server, các sửa chưa lưu bị mất.',
                          ),
                          actions: [
                            TextButton(
                              key: const Key('discard-cancel'),
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Giữ lại'),
                            ),
                            TextButton(
                              key: const Key('discard-confirm'),
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Hủy sửa'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) ctl.discardChanges();
                    },
              child: const Text('Hủy sửa'),
            ),
          OutlinedButton(
            key: const Key('admin-validate'),
            style: _compact,
            onPressed: state.busy ? null : ctl.validate,
            child: const Text('Kiểm tra'),
          ),
          const SizedBox(width: AppSpace.s1),
          FilledButton(
            key: const Key('admin-save'),
            style: _compact,
            onPressed: state.busy ? null : ctl.save,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

class _ConflictBanner extends ConsumerWidget {
  const _ConflictBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Container(
      key: const Key('admin-conflict'),
      width: double.infinity,
      color: p.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(AppSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Nội dung trên server đã đổi. Tải lại sẽ mất các sửa chưa lưu.',
              style: AppText.body.copyWith(color: p.danger),
            ),
          ),
          TextButton(
            key: const Key('admin-reload'),
            onPressed: ref.read(adminProvider.notifier).load,
            child: const Text('Tải lại'),
          ),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.state});
  final AdminState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final failure = switch (state.failure) {
      AdminErrorKind.forbidden => 'Không có quyền hoặc phiên đã hết hạn.',
      AdminErrorKind.network => 'Lỗi mạng, thử lại sau.',
      AdminErrorKind.server => state.failureMessage ?? 'Lỗi máy chủ',
      _ => null,
    };
    return Container(
      key: const Key('admin-errors'),
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s4,
        vertical: AppSpace.s2,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          if (state.notice != null)
            Text(
              state.notice!,
              style: AppText.label.copyWith(color: p.primary),
            ),
          if (failure != null)
            Text(failure, style: AppText.body.copyWith(color: p.danger)),
          for (final e in state.errors)
            Text('• $e', style: AppText.body.copyWith(color: p.danger)),
        ],
      ),
    );
  }
}

// ---- cây ------------------------------------------------------------------

class _Row {
  const _Row(this.depth, this.build);
  final int depth;
  final Widget Function(BuildContext) build;
}

class _Tree extends ConsumerWidget {
  const _Tree({required this.state});
  final AdminState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <_Row>[];
    final exercises = state.exercises;

    void addModule(Json m, int depth) {
      rows.add(_Row(depth, (c) => _ModuleRow(module: m)));
      for (final f in (m['files'] as List? ?? const [])) {
        f as Json;
        rows.add(_Row(depth + 1, (c) => _FileRow(file: f)));
        for (final id in (f['exercise_ids'] as List? ?? const [])) {
          final ex = exercises[id];
          final title = ex is Json ? (ex['title'] as String? ?? '') : '';
          rows.add(
            _Row(
              depth + 2,
              (c) => _ExerciseRow(id: id as String, title: title),
            ),
          );
        }
      }
      for (final sub in (m['modules'] as List? ?? const [])) {
        addModule(sub as Json, depth + 1);
      }
    }

    for (final t in state.themes) {
      rows.add(_Row(0, (c) => _ThemeRow(theme: t)));
      for (final topic in (t['topics'] as List? ?? const [])) {
        addModule(topic as Json, 1);
      }
    }

    return ListView.builder(
      key: const Key('admin-tree'),
      padding: const EdgeInsets.all(AppSpace.s4),
      itemCount: rows.length,
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.only(left: rows[i].depth * 16.0),
        child: rows[i].build(context),
      ),
    );
  }
}

Widget _icon(Key key, IconData icon, String tip, VoidCallback onTap) =>
    IconButton(
      key: key,
      icon: Icon(icon, size: 20),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );

class _ThemeRow extends ConsumerWidget {
  const _ThemeRow({required this.theme});
  final Json theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = theme['id'] as String;
    final ctl = ref.read(adminProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.s2),
      child: SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpace.s4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  theme['name'] as String? ?? id,
                  style: AppText.title,
                ),
              ),
              _icon(Key('theme-$id-edit'), Icons.edit, 'Sửa theme', () async {
                final r = await _editDialog(context, theme, withDesc: true);
                if (r != null && r.name.isNotEmpty) {
                  ctl.updateNode(id, name: r.name, description: r.description);
                }
              }),
              _icon(
                Key('theme-$id-diagram'),
                Icons.account_tree_outlined,
                'Sơ đồ class',
                () => _diagramDialog(context, ref, theme),
              ),
              _icon(
                Key('theme-$id-add-module'),
                Icons.create_new_folder,
                'Thêm module',
                () async {
                  final r = await _editDialog(
                    context,
                    const {},
                    withDesc: true,
                  );
                  if (r != null && r.name.isNotEmpty) {
                    ctl.addModule(id, r.name, description: r.description ?? '');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleRow extends ConsumerWidget {
  const _ModuleRow({required this.module});
  final Json module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = module['id'] as String;
    final ctl = ref.read(adminProvider.notifier);
    return Row(
      children: [
        const Icon(Icons.folder_outlined, size: 18),
        const SizedBox(width: AppSpace.s2),
        Expanded(
          child: Text(module['name'] as String? ?? id, style: AppText.label),
        ),
        _icon(Key('module-$id-edit'), Icons.edit, 'Sửa module', () async {
          final r = await _editDialog(context, module, withDesc: true);
          if (r != null && r.name.isNotEmpty) {
            ctl.updateNode(id, name: r.name, description: r.description);
          }
        }),
        _icon(
          Key('module-$id-add-module'),
          Icons.create_new_folder,
          'Thêm module con',
          () async {
            final r = await _editDialog(context, const {}, withDesc: true);
            if (r != null && r.name.isNotEmpty) {
              ctl.addModule(id, r.name, description: r.description ?? '');
            }
          },
        ),
        _icon(
          Key('module-$id-add-file'),
          Icons.note_add,
          'Thêm file',
          () async {
            final r = await _editDialog(context, const {}, withDesc: false);
            if (r != null && r.name.isNotEmpty) ctl.addFile(id, r.name);
          },
        ),
      ],
    );
  }
}

class _FileRow extends ConsumerWidget {
  const _FileRow({required this.file});
  final Json file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = file['id'] as String;
    final ctl = ref.read(adminProvider.notifier);
    return Row(
      children: [
        const Icon(Icons.description_outlined, size: 18),
        const SizedBox(width: AppSpace.s2),
        Expanded(
          child: Text(file['name'] as String? ?? id, style: AppText.code),
        ),
        _icon(Key('file-$id-edit'), Icons.edit, 'Sửa file', () async {
          final r = await _editDialog(context, file, withDesc: false);
          if (r != null && r.name.isNotEmpty) {
            ctl.updateNode(id, name: r.name);
          }
        }),
        _icon(
          Key('file-$id-add-exercise'),
          Icons.add,
          'Thêm bài tập',
          () async {
            final r = await _editDialog(
              context,
              const {},
              withDesc: false,
              nameLabel: 'Tên bài tập',
            );
            if (r != null && r.name.isNotEmpty) ctl.addExercise(id, r.name);
          },
        ),
      ],
    );
  }
}

class _ExerciseRow extends ConsumerWidget {
  const _ExerciseRow({required this.id, required this.title});
  final String id;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: Key('exercise-$id-open'),
            onTap: () => context.push('/admin/exercise/$id'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
              child: Text(title.isEmpty ? id : title, style: AppText.body),
            ),
          ),
        ),
        _icon(
          Key('exercise-$id-delete'),
          Icons.delete_outline,
          'Xoá bài',
          () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('Xoá bài "$id"?'),
                content: const Text('Bài bị gỡ khỏi mọi file.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Hủy'),
                  ),
                  TextButton(
                    key: const Key('delete-confirm'),
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Xoá'),
                  ),
                ],
              ),
            );
            if (ok == true) ref.read(adminProvider.notifier).deleteExercise(id);
          },
        ),
      ],
    );
  }
}

// ---- dialog ---------------------------------------------------------------

class _EditResult {
  const _EditResult(this.name, this.description);
  final String name;
  final String? description;
}

Future<_EditResult?> _editDialog(
  BuildContext context,
  Map<String, dynamic> node, {
  required bool withDesc,
  String nameLabel = 'Tên',
}) {
  final name = TextEditingController(text: node['name'] as String? ?? '');
  final desc = TextEditingController(
    text: node['description'] as String? ?? '',
  );
  return showDialog<_EditResult>(
    context: context,
    builder: (c) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('edit-name'),
            controller: name,
            decoration: InputDecoration(labelText: nameLabel),
          ),
          if (withDesc)
            TextField(
              key: const Key('edit-description'),
              controller: desc,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Mô tả'),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
        TextButton(
          key: const Key('edit-ok'),
          onPressed: () => Navigator.pop(
            c,
            _EditResult(name.text.trim(), withDesc ? desc.text : null),
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
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
