/// Màn Admin cấp 3: file và bài tập của một module (cùng module con).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../shared/widgets.dart';
import 'admin_controller.dart';
import 'admin_theme_screen.dart' show moduleCard;
import 'admin_widgets.dart';

class AdminModuleScreen extends ConsumerWidget {
  const AdminModuleScreen({super.key, required this.moduleId});
  final String moduleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(adminProvider.notifier);
    return AdminLevelScaffold(
      crumbsOf: (s) {
        final loc = locateModule(s, moduleId);
        if (loc == null) {
          return [
            const Crumb('projects', 'Projects', '/admin'),
            Crumb('module', moduleId, '/admin/module/$moduleId'),
          ];
        }
        return [
          const Crumb('projects', 'Projects', '/admin'),
          Crumb('theme', nameOf(loc.theme), '/admin/theme/${loc.theme['id']}'),
          for (final m in loc.chain)
            Crumb(
              m['id'] == moduleId ? 'module' : 'module-${m['id']}',
              nameOf(m),
              '/admin/module/${m['id']}',
            ),
        ];
      },
      body: (context, s) {
        final loc = locateModule(s, moduleId);
        if (loc == null) {
          return Center(
            key: const Key('admin-not-found'),
            child: Text(
              'Không tìm thấy module này.',
              style: AppText.body.copyWith(color: context.palette.inkMuted),
            ),
          );
        }
        final module = loc.module;
        final withErrors = exerciseIdsWithErrors(s.errors);
        final subs = [
          for (final m in (module['modules'] as List? ?? const [])) m as Json,
        ];
        return AdminList(
          children: [
            for (final f in (module['files'] as List? ?? const []))
              _FileGroup(file: f as Json, withErrors: withErrors),
            AdminAddButton(
              key: const Key('add-file'),
              label: 'Thêm file',
              onPressed: () async {
                final r = await adminEditDialog(
                  context,
                  withDesc: false,
                  nameLabel: 'Tên file',
                );
                if (r != null && r.name.isNotEmpty) {
                  ctl.addFile(moduleId, r.name);
                }
              },
            ),
            if (subs.isNotEmpty) const SectionLabel('Module con'),
            for (final m in subs) moduleCard(context, ref, m, withErrors),
            AdminAddButton(
              key: const Key('add-module'),
              label: 'Thêm module con',
              primary: false,
              onPressed: () async {
                final r = await adminEditDialog(
                  context,
                  withDesc: true,
                  nameLabel: 'Tên module',
                );
                if (r != null && r.name.isNotEmpty) {
                  ctl.addModule(
                    moduleId,
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

class _FileGroup extends ConsumerWidget {
  const _FileGroup({required this.file, required this.withErrors});
  final Json file;
  final Set<String> withErrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = file['id'] as String;
    final ctl = ref.read(adminProvider.notifier);
    final s = ref.watch(adminProvider);
    final p = context.palette;
    final ids = [
      for (final e in (file['exercise_ids'] as List? ?? const [])) e as String,
    ];
    return Column(
      key: Key('file-$id-group'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: p.inkMuted),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: Text(
                nameOf(file),
                style: AppText.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AdminActionMenu(
              menuKey: 'file-$id-menu',
              entries: [
                AdminMenuEntry('rename', 'Đổi tên', () async {
                  final r = await adminEditDialog(
                    context,
                    node: file,
                    withDesc: false,
                    nameLabel: 'Tên file',
                  );
                  if (r != null && r.name.isNotEmpty) {
                    ctl.updateNode(id, name: r.name);
                  }
                }),
              ],
            ),
          ],
        ),
        for (final eid in ids)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s2),
            child: _exerciseCard(context, ref, s, eid),
          ),
        AdminAddButton(
          key: Key('file-$id-add-exercise'),
          label: 'Thêm bài',
          primary: false,
          onPressed: () => _addExercise(context, ref, id),
        ),
      ],
    );
  }

  Widget _exerciseCard(
    BuildContext context,
    WidgetRef ref,
    AdminState s,
    String id,
  ) {
    final ex = s.exercises[id];
    final json = ex is Json ? ex : const <String, dynamic>{};
    final title = (json['title'] as String?) ?? '';
    final fn = json['function_name'] as String?;
    final cls = json['class_name'] as String?;
    final sig = fn == null || fn.isEmpty
        ? null
        : (cls == null || cls.isEmpty ? fn : '$cls.$fn');
    final blocks = (json['blocks'] as List? ?? const []).length;
    return AdminLevelCard(
      key: Key('exercise-$id-card'),
      title: title.isEmpty ? id : title,
      subtitle: sig,
      meta: '$blocks ô',
      hasError: withErrors.contains(id),
      errorKey: Key('exercise-$id-error'),
      onTap: () => context.push('/admin/exercise/$id'),
      trailing: [
        AdminActionMenu(
          menuKey: 'exercise-$id-menu',
          entries: [
            AdminMenuEntry('delete', 'Xoá', () async {
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
              if (ok == true) {
                ref.read(adminProvider.notifier).deleteExercise(id);
              }
            }),
          ],
        ),
      ],
    );
  }

  Future<void> _addExercise(
    BuildContext context,
    WidgetRef ref,
    String fileId,
  ) async {
    final r = await showDialog<_NewExercise>(
      context: context,
      builder: (_) => const _AddExerciseDialog(),
    );
    if (r == null) return;
    final id = ref
        .read(adminProvider.notifier)
        .addExercise(
          fileId,
          r.title,
          functionName: r.functionName,
          className: r.className,
        );
    if (!context.mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thêm được bài: file không còn tồn tại.'),
        ),
      );
      return;
    }
    context.push('/admin/exercise/$id');
  }
}

typedef _NewExercise = ({String title, String functionName, String className});

final _pyIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Dialog thêm bài: controller nằm trong State (dispose sau animation đóng),
/// lỗi hiện inline thay vì đóng im lặng.
class _AddExerciseDialog extends StatefulWidget {
  const _AddExerciseDialog();

  @override
  State<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<_AddExerciseDialog> {
  final _title = TextEditingController();
  final _fn = TextEditingController();
  final _cls = TextEditingController();
  String? _titleError;
  String? _fnError;
  String? _clsError;

  @override
  void dispose() {
    _title.dispose();
    _fn.dispose();
    _cls.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    final fn = _fn.text.trim();
    final cls = _cls.text.trim();
    setState(() {
      _titleError = title.isEmpty ? 'Cần nhập tiêu đề' : null;
      _fnError = _pyIdentifier.hasMatch(fn)
          ? null
          : 'Tên hàm phải là định danh Python (chữ, số, _; không bắt đầu bằng số)';
      _clsError = cls.isEmpty || _pyIdentifier.hasMatch(cls)
          ? null
          : 'Tên class phải là định danh Python (chữ, số, _; không bắt đầu bằng số)';
    });
    if (_titleError != null || _fnError != null || _clsError != null) return;
    Navigator.pop<_NewExercise>(context, (
      title: title,
      functionName: fn,
      className: cls,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thêm bài'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('add-exercise-title'),
            controller: _title,
            decoration: InputDecoration(
              labelText: 'Tiêu đề',
              hintText: 'vd: Còn bao nhiêu ghế trống',
              errorText: _titleError,
            ),
          ),
          TextField(
            key: const Key('add-exercise-fn'),
            controller: _fn,
            decoration: InputDecoration(
              labelText: 'Tên hàm',
              hintText: 'vd: seats_left',
              errorText: _fnError,
            ),
          ),
          TextField(
            key: const Key('add-exercise-class'),
            controller: _cls,
            decoration: InputDecoration(
              labelText: 'Class (tuỳ chọn)',
              hintText: 'vd: Flight (để trống nếu là hàm rời)',
              errorText: _clsError,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      TextButton(
        key: const Key('add-exercise-ok'),
        onPressed: _submit,
        child: const Text('Thêm'),
      ),
    ],
  );
}
