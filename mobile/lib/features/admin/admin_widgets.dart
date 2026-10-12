/// Phần dùng chung của 3 cấp màn Admin (Projects → Module → …): thẻ cấp,
/// breadcrumb, menu ⋯, nút thêm, thanh lưu cố định, banner xung đột.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/admin_repository.dart';
import '../../shared/widgets.dart';
import 'admin_controller.dart';

// ---- dữ liệu thuần --------------------------------------------------------

/// Đầu dòng: `bài <id>: …` hoặc `bài <id> ô <X>: …`.
final _errorIdPattern = RegExp(
  r'^\s*bài\s+([^\s:]+)(?:\s+ô\s+[^\s:]+)?\s*:',
  caseSensitive: false,
);

/// Cuối dòng: `… (bài <id>)` (lỗi sơ đồ class của theme).
final _errorTrailingIdPattern = RegExp(
  r'\(bài\s+([^\s)]+)\)\s*$',
  caseSensitive: false,
);

/// Lấy id bài từ lỗi server: `bài <id>: …`, `bài <id> ô <X>: …`, `… (bài <id>)`.
/// Lỗi không đúng dạng nào bị bỏ qua.
Set<String> exerciseIdsWithErrors(List<String> errors) => {
  for (final e in errors) ...[
    if (_errorIdPattern.firstMatch(e) case final m?) m.group(1)!,
    if (_errorTrailingIdPattern.firstMatch(e) case final m?) m.group(1)!,
  ],
};

/// Mọi id bài nằm trong [module], kể cả module con.
Set<String> moduleExerciseIds(Json module) {
  final out = <String>{};
  void walk(Json m) {
    for (final f in (m['files'] as List? ?? const [])) {
      for (final id in ((f as Json)['exercise_ids'] as List? ?? const [])) {
        out.add(id as String);
      }
    }
    for (final s in (m['modules'] as List? ?? const [])) {
      walk(s as Json);
    }
  }

  walk(module);
  return out;
}

int moduleFileCount(Json module) {
  var n = (module['files'] as List? ?? const []).length;
  for (final s in (module['modules'] as List? ?? const [])) {
    n += moduleFileCount(s as Json);
  }
  return n;
}

List<Json> topicsOf(Json theme) => [
  for (final t in (theme['topics'] as List? ?? const [])) t as Json,
];

Json? findTheme(AdminState s, String id) {
  for (final t in s.themes) {
    if (t['id'] == id) return t;
  }
  return null;
}

/// Vị trí của một module: theme chứa nó và chuỗi module từ gốc tới nó.
class ModuleLoc {
  const ModuleLoc(this.theme, this.chain);
  final Json theme;
  final List<Json> chain;
  Json get module => chain.last;
}

ModuleLoc? locateModule(AdminState s, String id) {
  List<Json>? walk(Json m) {
    if (m['id'] == id) return [m];
    for (final sub in (m['modules'] as List? ?? const [])) {
      final hit = walk(sub as Json);
      if (hit != null) return [m, ...hit];
    }
    return null;
  }

  for (final t in s.themes) {
    for (final topic in topicsOf(t)) {
      final hit = walk(topic);
      if (hit != null) return ModuleLoc(t, hit);
    }
  }
  return null;
}

String nameOf(Json node) =>
    (node['name'] as String?) ?? (node['id'] as String? ?? '');

// ---- breadcrumb -----------------------------------------------------------

class Crumb {
  const Crumb(this.level, this.label, this.route);

  /// Dùng cho key `breadcrumb-<level>`.
  final String level;
  final String label;

  /// Route của cấp này (`/admin`, `/admin/theme/<id>`, `/admin/module/<id>`).
  final String route;
}

/// Về cấp [route] cách [steps] màn: pop nếu stack đúng là chuỗi đã đi xuống,
/// ngược lại (deep link, refresh web) `go` thẳng tới route.
void adminGoToLevel(BuildContext context, String route, int steps) {
  final router = GoRouter.of(context);
  final matches = router.routerDelegate.currentConfiguration.matches;
  final idx = matches.length - 1 - steps;
  if (steps > 0 && idx >= 0 && matches[idx].matchedLocation == route) {
    for (var k = 0; k < steps; k++) {
      router.pop();
    }
  } else {
    router.go(route);
  }
}

/// Hàng breadcrumb. Chạm một mục = quay về cấp đó.
class Breadcrumb extends StatelessWidget {
  const Breadcrumb({super.key, required this.crumbs});
  final List<Crumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final last = crumbs.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s2, 0, AppSpace.s4, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i <= last; i++) ...[
              if (i > 0)
                Text(' / ', style: AppText.caption.copyWith(color: p.inkMuted)),
              Tooltip(
                message: i == last ? crumbs[i].label : 'Về ${crumbs[i].label}',
                child: Semantics(
                  button: i != last,
                  label: crumbs[i].label,
                  excludeSemantics: true,
                  child: InkWell(
                    key: Key('breadcrumb-${crumbs[i].level}'),
                    onTap: i == last
                        ? null
                        : () => adminGoToLevel(
                            context,
                            crumbs[i].route,
                            last - i,
                          ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 40,
                        minWidth: 40,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.s2,
                        ),
                        child: Align(
                          widthFactor: 1,
                          alignment: Alignment.center,
                          child: Text(
                            crumbs[i].label,
                            style: AppText.caption.copyWith(
                              color: i == last ? p.ink : p.primary,
                              fontWeight: i == last ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- thẻ, menu, nút thêm --------------------------------------------------

class ErrorDot extends StatelessWidget {
  const ErrorDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: context.palette.danger,
      shape: BoxShape.circle,
    ),
  );
}

/// Nhãn nhỏ "chờ duyệt" cho thẻ có mục đang nằm trong hàng chờ.
class PendingBadge extends StatelessWidget {
  const PendingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: 2),
      decoration: BoxDecoration(
        color: p.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        'chờ duyệt',
        style: AppText.caption.copyWith(
          color: p.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AdminMenuEntry {
  const AdminMenuEntry(this.id, this.label, this.onTap, {this.enabled = true});
  final String id;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
}

/// Menu ⋯. Mục có key `<key>-<id>`.
class AdminActionMenu extends StatelessWidget {
  const AdminActionMenu({
    super.key,
    required this.menuKey,
    required this.entries,
  });
  final String menuKey;
  final List<AdminMenuEntry> entries;

  @override
  Widget build(BuildContext context) => PopupMenuButton<AdminMenuEntry>(
    key: Key(menuKey),
    tooltip: 'Tuỳ chọn',
    icon: const Icon(Icons.more_horiz),
    onSelected: (e) => e.onTap(),
    itemBuilder: (_) => [
      for (final e in entries)
        PopupMenuItem(
          key: Key('$menuKey-${e.id}'),
          value: e,
          enabled: e.enabled,
          child: Text(e.label),
        ),
    ],
  );
}

/// Thẻ một cấp: tiêu đề, mô tả/dòng phụ, dòng đếm, chấm đỏ khi có lỗi.
class AdminLevelCard extends StatelessWidget {
  const AdminLevelCard({
    super.key,
    required this.title,
    this.description,
    this.subtitle,
    this.meta,
    this.hasError = false,
    this.errorKey,
    this.badge,
    this.onTap,
    this.trailing = const [],
  });

  final String title;
  final String? description;

  /// Dòng đơn sắc (vd `Class.fn`).
  final String? subtitle;
  final String? meta;
  final bool hasError;
  final Key? errorKey;

  /// Nhãn cạnh tiêu đề (vd [PendingBadge]).
  final Widget? badge;
  final VoidCallback? onTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpace.s4,
          top: AppSpace.s2,
          bottom: AppSpace.s2,
          right: AppSpace.s1,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppText.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasError) ...[
                        const SizedBox(width: AppSpace.s2),
                        ErrorDot(key: errorKey),
                      ],
                      if (badge != null) ...[
                        const SizedBox(width: AppSpace.s2),
                        badge!,
                      ],
                    ],
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!, style: AppText.code),
                  if (description != null && description!.isNotEmpty)
                    Text(
                      description!,
                      style: AppText.caption.copyWith(color: p.inkMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (meta != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.s1),
                      child: Text(
                        meta!,
                        style: AppText.caption.copyWith(color: p.primary),
                      ),
                    ),
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

/// Nút thêm to, full chiều ngang. Dấu "+" nằm ở icon, label không lặp lại.
class AdminAddButton extends StatelessWidget {
  const AdminAddButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
  });
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: double.infinity,
      child: primary
          ? PrimaryButton(label: label, icon: Icons.add, onPressed: onPressed)
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.ink,
                side: BorderSide(color: p.outline, width: 1),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.s4,
                  vertical: AppSpace.s2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
    );
  }
}

// ---- dialog dùng chung ----------------------------------------------------

class AdminEditResult {
  const AdminEditResult(this.name, this.description);
  final String name;
  final String? description;
}

/// Dialog nhập tên (+ mô tả). Trả null nếu huỷ.
Future<AdminEditResult?> adminEditDialog(
  BuildContext context, {
  Map<String, dynamic> node = const {},
  required bool withDesc,
  String nameLabel = 'Tên',
}) => showDialog<AdminEditResult>(
  context: context,
  builder: (_) =>
      _EditDialog(node: node, withDesc: withDesc, nameLabel: nameLabel),
);

/// Giữ controller trong State để dispose đúng lúc (sau animation đóng dialog).
class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.node,
    required this.withDesc,
    required this.nameLabel,
  });
  final Map<String, dynamic> node;
  final bool withDesc;
  final String nameLabel;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.node['name'] as String? ?? '',
  );
  late final TextEditingController _desc = TextEditingController(
    text: widget.node['description'] as String? ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('edit-name'),
          controller: _name,
          decoration: InputDecoration(labelText: widget.nameLabel),
        ),
        if (widget.withDesc)
          TextField(
            key: const Key('edit-description'),
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Mô tả'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      TextButton(
        key: const Key('edit-ok'),
        onPressed: () => Navigator.pop(
          context,
          AdminEditResult(
            _name.text.trim(),
            widget.withDesc ? _desc.text : null,
          ),
        ),
        child: const Text('OK'),
      ),
    ],
  );
}

Future<bool> confirmDiscard(BuildContext context) async {
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
  return ok == true;
}

// ---- banner + thanh lưu ---------------------------------------------------

class AdminConflictBanner extends ConsumerWidget {
  const AdminConflictBanner({super.key});

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

String? _failureText(AdminState s) => switch (s.failure) {
  AdminErrorKind.forbidden => 'Không có quyền hoặc phiên đã hết hạn.',
  AdminErrorKind.network => 'Lỗi mạng, thử lại sau.',
  AdminErrorKind.server => s.failureMessage ?? 'Lỗi máy chủ',
  _ => null,
};

void _showErrorsSheet(BuildContext context, List<String> errors) {
  final p = context.palette;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: ListView(
          key: const Key('admin-errors'),
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpace.s4),
          children: [
            SectionLabel('${errors.length} lỗi cần sửa'),
            for (final e in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s2),
                child: Text(
                  '• $e',
                  style: AppText.body.copyWith(color: p.danger),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Thanh lưu ghim đáy: trạng thái, chip lỗi, Kiểm tra / Gửi duyệt, menu Hủy sửa.
class AdminSaveBar extends ConsumerWidget {
  const AdminSaveBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(adminProvider);
    final ctl = ref.read(adminProvider.notifier);
    final p = context.palette;
    final failure = _failureText(s);
    final message = failure ?? s.notice;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.outline, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.s4,
        AppSpace.s2,
        AppSpace.s2,
        AppSpace.s2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                s.dirty ? '● Chưa lưu' : 'Đã đồng bộ',
                key: const Key('admin-dirty'),
                style: AppText.label.copyWith(
                  color: s.dirty ? p.danger : p.inkMuted,
                ),
              ),
              if (s.errors.isNotEmpty) ...[
                const SizedBox(width: AppSpace.s2),
                ActionChip(
                  key: const Key('admin-error-chip'),
                  label: Text('${s.errors.length} lỗi'),
                  visualDensity: VisualDensity.compact,
                  labelStyle: AppText.caption.copyWith(color: p.danger),
                  side: BorderSide(color: p.danger),
                  onPressed: () => _showErrorsSheet(context, s.errors),
                ),
              ],
              const Spacer(),
              PopupMenuButton<String>(
                key: const Key('admin-more'),
                tooltip: 'Tuỳ chọn',
                icon: const Icon(Icons.more_horiz),
                onSelected: (_) async {
                  if (await confirmDiscard(context)) ctl.discardChanges();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    key: const Key('admin-discard'),
                    value: 'discard',
                    enabled: s.dirty && !s.busy,
                    child: const Text('Hủy sửa'),
                  ),
                ],
              ),
            ],
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  key: const Key('admin-notice'),
                  style: AppText.caption.copyWith(
                    color: failure != null ? p.danger : p.primary,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.s2),
            child: Row(
              children: [
                Expanded(
                  child: GhostButton(
                    key: const Key('admin-validate'),
                    label: 'Kiểm tra',
                    onPressed: s.busy ? null : ctl.validate,
                  ),
                ),
                const SizedBox(width: AppSpace.s2),
                Expanded(
                  child: PrimaryButton(
                    key: const Key('admin-save'),
                    label: 'Gửi duyệt',
                    onPressed: s.busy ? null : ctl.save,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- khung chung cho mọi cấp ----------------------------------------------

/// Khung 3 cấp: header, breadcrumb, banner 409, nội dung, thanh lưu.
/// Lo luôn trạng thái đang tải / tải lỗi (+ Thử lại).
class AdminLevelScaffold extends ConsumerWidget {
  const AdminLevelScaffold({
    super.key,
    required this.crumbsOf,
    required this.body,
  });

  final List<Crumb> Function(AdminState s) crumbsOf;
  final Widget Function(BuildContext context, AdminState s) body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(adminProvider);
    final p = context.palette;
    final ready = s.status == AdminStatus.ready;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Soạn nội dung',
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  // Deep link (stack chỉ có 1 route): lên cấp cha, không về Home.
                  final crumbs = crumbsOf(s);
                  context.go(
                    crumbs.length >= 2 ? crumbs[crumbs.length - 2].route : '/',
                  );
                }
              },
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
                      GhostButton(
                        key: const Key('admin-retry'),
                        label: 'Thử lại',
                        onPressed: ref.read(adminProvider.notifier).load,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Breadcrumb(crumbs: crumbsOf(s)),
              if (s.conflict) const AdminConflictBanner(),
              Expanded(child: body(context, s)),
            ],
            if (ready) const AdminSaveBar(),
          ],
        ),
      ),
    );
  }
}

/// Danh sách cuộn chuẩn cho nội dung của một cấp.
class AdminList extends StatelessWidget {
  const AdminList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpace.s4),
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.s2),
        children[i],
      ],
    ],
  );
}
