/// Chi tiết một mục chờ duyệt: bảng so sánh trước / sau theo từng trường, nút
/// "Xem như học viên" (bài) và Duyệt / Bỏ.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/admin_repository.dart';
import '../../domain/content.dart';
import '../../shared/widgets.dart';
import '../exercise/exercise_screen.dart';
import 'admin_controller.dart';
import 'review_screen.dart';

const _segmentLabels = {
  'title': 'Tiêu đề',
  'name': 'Tên',
  'description': 'Mô tả',
  'template': 'Template',
  'challenge': 'Đề bài',
  'judge': 'Judge',
  'cases': 'Cases',
  'solution': 'Lời giải',
  'accepted_answers': 'Đáp án chấp nhận',
  'hints': 'Gợi ý',
  'blocks': 'Ô',
  'class_name': 'Tên class',
  'function_name': 'Tên hàm',
  'params': 'Tham số',
  'theme_id': 'Chuyển sang project',
  'parent_id': 'Chuyển sang module cha',
  'module_id': 'Chuyển sang module',
};

/// Nhãn khi mục mới tạo (không có "chuyển" từ đâu sang).
const _createParentLabels = {
  'theme_id': 'Thuộc project',
  'parent_id': 'Thuộc module cha',
  'module_id': 'Thuộc module',
};

/// Dàn phẳng JSON thành path -> chuỗi. List scalar nối bằng xuống dòng; list
/// object lấy `label` (ô) làm khoá nếu có, không thì số thứ tự.
void flattenJson(Object? v, String path, Map<String, String> out) {
  if (v is Map) {
    for (final e in v.entries) {
      flattenJson(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}', out);
    }
  } else if (v is List) {
    final scalars = v.every((e) => e is! Map && e is! List);
    if (scalars) {
      out[path] = v.join('\n');
    } else {
      for (var i = 0; i < v.length; i++) {
        final e = v[i];
        final label = e is Map && e['label'] is String ? e['label'] : null;
        flattenJson(
          e,
          '$path.${label != null ? 'ô $label' : '[${i + 1}]'}',
          out,
        );
      }
    }
  } else {
    out[path] = v?.toString() ?? '';
  }
}

String _labelOf(DiffRow r) {
  if (r.label != null) return r.label!;
  final p = r.path.startsWith('fields.') ? r.path.substring(7) : r.path;
  return p.split('.').map((s) => _segmentLabels[s] ?? s).join(' › ');
}

class DiffRow {
  const DiffRow(this.path, this.before, this.after, {this.label});
  final String path;
  final String? before;
  final String? after;

  /// Nhãn đã dựng sẵn (hàng vị trí); null thì suy từ [path].
  final String? label;
}

List<String> _ids(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is String) e,
];

/// "Đứng sau (anh em ngay trước)" hoặc "Đứng đầu".
String _after(List<String> order, String id, String Function(String) nameOf) {
  final i = order.indexOf(id);
  return i <= 0 ? 'Đứng đầu' : 'Đứng sau ${nameOf(order[i - 1])}';
}

/// Mục [id] có đổi chỗ không: tập anh em đứng trước nó (chỉ tính anh em có ở
/// cả hai bên) khác nhau. Thêm/bớt anh em, hoặc anh em khác đổi chỗ với nhau,
/// không làm mục này đổi chỗ.
bool _moved(List<String> before, List<String> after, String id) {
  if (!before.contains(id) || !after.contains(id)) return false;
  final common = before.toSet().intersection(after.toSet());
  Set<String> preds(List<String> o) =>
      o.sublist(0, o.indexOf(id)).where(common.contains).toSet();
  final a = preds(before), b = preds(after);
  return a.length != b.length || !a.containsAll(b);
}

/// Các trường khác nhau giữa before và after (create: before rỗng; delete:
/// after rỗng). `order`/`placements` (thứ tự đầy đủ của anh em) không dàn
/// phẳng mà đổi thành hàng "Vị trí" / "Thêm vào file …" chỉ khi mục thật sự
/// đổi chỗ. [nameOf] đổi id thành tên cho dễ đọc (mặc định giữ id).
List<DiffRow> diffOf(ContentChange c, {String Function(String id)? nameOf}) {
  final name = nameOf ?? (String id) => id;
  Map<String, dynamic>? strip(Map<String, dynamic>? m) => m == null
      ? null
      : {
          for (final e in m.entries)
            if (e.key != 'order' && e.key != 'placements') e.key: e.value,
        };
  final b = <String, String>{};
  final a = <String, String>{};
  flattenJson(strip(c.before), '', b);
  flattenJson(strip(c.after), '', a);
  final creating = c.before == null;
  String show(String path, String? v) {
    final key = path.split('.').last;
    if (v == null || v.isEmpty) return '';
    return _segmentLabels.containsKey(key) && key.endsWith('_id') ? name(v) : v;
  }

  final rows = <DiffRow>[];
  for (final k in {...b.keys, ...a.keys}) {
    if ((b[k] ?? '') == (a[k] ?? '')) continue;
    rows.add(
      DiffRow(
        k,
        b.containsKey(k) ? show(k, b[k]) : null,
        a.containsKey(k) ? show(k, a[k]) : null,
        label: creating ? _createParentLabels[k] : null,
      ),
    );
  }

  final id = c.itemId;
  final bo = _ids(c.before?['order']), ao = _ids(c.after?['order']);
  if (creating) {
    if (ao.contains(id) && ao.indexOf(id) > 0) {
      rows.add(DiffRow('order', null, _after(ao, id, name), label: 'Vị trí'));
    }
  } else if (c.after != null && _moved(bo, ao, id)) {
    rows.add(
      DiffRow(
        'order',
        _after(bo, id, name),
        _after(ao, id, name),
        label: 'Vị trí',
      ),
    );
  }

  final bp = c.before?['placements'], ap = c.after?['placements'];
  final files = <String>{
    if (bp is Map) ...bp.keys.cast<String>(),
    if (ap is Map) ...ap.keys.cast<String>(),
  };
  for (final f in files) {
    final fb = _ids(bp is Map ? bp[f] : null);
    final fa = _ids(ap is Map ? ap[f] : null);
    final inB = fb.contains(id), inA = fa.contains(id);
    final fn = name(f);
    if (inA && !inB) {
      rows.add(
        DiffRow(
          'placements.$f',
          null,
          _after(fa, id, name),
          label: 'Thêm vào file $fn',
        ),
      );
    } else if (inB && !inA) {
      rows.add(
        DiffRow(
          'placements.$f',
          _after(fb, id, name),
          null,
          label: 'Bỏ khỏi file $fn',
        ),
      );
    } else if (_moved(fb, fa, id)) {
      rows.add(
        DiffRow(
          'placements.$f',
          _after(fb, id, name),
          _after(fa, id, name),
          label: 'Đổi chỗ trong file $fn',
        ),
      );
    }
  }
  return rows;
}

/// id -> tên/tiêu đề, duyệt mọi map có `id` và `name`/`title` trong bản nháp.
Map<String, String> namesOfDoc(Object? doc) {
  final out = <String, String>{};
  void walk(Object? v) {
    if (v is Map) {
      final id = v['id'], n = v['name'] ?? v['title'];
      if (id is String && n is String && n.isNotEmpty) out[id] = n;
      v.values.forEach(walk);
    } else if (v is List) {
      v.forEach(walk);
    }
  }

  walk(doc);
  return out;
}

class AdminReviewDetailScreen extends ConsumerStatefulWidget {
  const AdminReviewDetailScreen({super.key, required this.changeId});
  final int changeId;

  @override
  ConsumerState<AdminReviewDetailScreen> createState() => _DetailState();
}

class _DetailState extends ConsumerState<AdminReviewDetailScreen> {
  ContentChange? _change;
  AdminError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(adminProvider.notifier).changes();
      if (!mounted) return;
      setState(() {
        _change = list.where((c) => c.id == widget.changeId).firstOrNull;
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

  void _back() =>
      context.canPop() ? context.pop() : context.go('/admin/review');

  Future<void> _decide(ContentChange c, {required bool approve}) async {
    final done = await decideChange(context, ref, c, approve: approve);
    if (!mounted) return;
    if (done) {
      _back();
    } else {
      // 404/409/422: danh sách có thể đã cũ; tải lại, mục không còn thì báo.
      await _load();
    }
  }

  Future<void> _preview(ContentChange c) async {
    final ctl = ref.read(adminProvider.notifier);
    if (ref.read(adminProvider).doc == null) await ctl.load();
    if (!mounted) return;
    final s = ref.read(adminProvider);
    final doc = s.doc;
    if (doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tải được bản nháp để xem trước')),
      );
      return;
    }
    if (s.dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          key: const Key('preview-dirty-warning'),
          title: const Text('Có sửa chưa gửi'),
          content: const Text(
            'Bản xem trước gồm cả sửa chưa gửi của bạn, không chỉ mục này.',
          ),
          actions: [
            TextButton(
              key: const Key('preview-dirty-cancel'),
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Huỷ'),
            ),
            TextButton(
              key: const Key('preview-dirty-continue'),
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Vẫn xem'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final Content content;
    try {
      content = Content.fromJson({...doc, 'version': s.version});
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bản nháp chưa hợp lệ để xem trước')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExercisePreview(content: content, exerciseId: c.itemId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(adminProvider.select((s) => s.busy));
    final p = context.palette;
    final c = _change;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!.message ?? 'Không tải được mục này.',
              key: const Key('detail-load-failed'),
              style: AppText.body.copyWith(color: p.danger),
            ),
            const SizedBox(height: AppSpace.s2),
            GhostButton(label: 'Thử lại', onPressed: _load),
          ],
        ),
      );
    } else if (c == null) {
      body = Center(
        child: Text(
          'Mục này không còn trong hàng chờ',
          key: const Key('detail-missing'),
          style: AppText.body.copyWith(color: p.inkMuted),
        ),
      );
    } else {
      body = _content(context, c, busy);
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: 'Chi tiết thay đổi', onBack: _back),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ContentChange c, bool busy) {
    final p = context.palette;
    final names = namesOfDoc(ref.watch(adminProvider.select((s) => s.doc)));
    final rows = diffOf(c, nameOf: (id) => names[id] ?? id);
    final meta = [
      if (c.author != null) c.author!,
      shortTime(c.createdAt),
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListView(
      key: const Key('detail-list'),
      padding: const EdgeInsets.all(AppSpace.s4),
      children: [
        Text(
          '${actionLabel(c.action)} · ${kindLabel(c.kind)}',
          style: AppText.label.copyWith(color: p.primary),
        ),
        Text(
          changeTitle(c),
          key: const Key('detail-title'),
          style: AppText.title,
        ),
        if (meta.isNotEmpty)
          Text(meta, style: AppText.caption.copyWith(color: p.inkMuted)),
        const SizedBox(height: AppSpace.s4),
        if (rows.isEmpty)
          Text(
            'Không có trường nào khác biệt.',
            style: AppText.body.copyWith(color: p.inkMuted),
          ),
        for (final r in rows) ...[
          _DiffTile(row: r),
          const SizedBox(height: AppSpace.s2),
        ],
        const SizedBox(height: AppSpace.s2),
        if (c.kind == 'exercise' && c.action != 'delete') ...[
          GhostButton(
            key: const Key('preview-button'),
            label: 'Xem như học viên',
            onPressed: () => _preview(c),
          ),
          const SizedBox(height: AppSpace.s2),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('detail-reject'),
                onPressed: busy ? null : () => _decide(c, approve: false),
                child: const Text('Bỏ'),
              ),
            ),
            const SizedBox(width: AppSpace.s2),
            Expanded(
              child: FilledButton(
                key: const Key('detail-approve'),
                onPressed: busy ? null : () => _decide(c, approve: true),
                child: const Text('Duyệt'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DiffTile extends StatelessWidget {
  const _DiffTile({required this.row});
  final DiffRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget side(String label, String? v, Key key, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption.copyWith(color: p.inkMuted)),
          Text(
            v == null || v.isEmpty ? '—' : v,
            key: key,
            style: AppText.code.copyWith(color: color),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpace.s2),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _labelOf(row),
            key: Key('diff-${row.path}'),
            style: AppText.label,
          ),
          const SizedBox(height: AppSpace.s1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side(
                'Trước',
                row.before,
                Key('diff-before-${row.path}'),
                p.danger,
              ),
              const SizedBox(width: AppSpace.s2),
              side('Sau', row.after, Key('diff-after-${row.path}'), p.primary),
            ],
          ),
        ],
      ),
    );
  }
}
