/// Lộ trình một tài liệu System Design kiểu Duolingo: Phase 1 (đọc theo
/// chapter) rồi Phase 2 (bối cảnh + task thực chiến).
///
/// INV-04: khoá/mở của MỌI node lấy hoàn toàn từ server (`unlocked`, `done`,
/// `phase2Unlocked`); client không đếm thẻ để tự quyết khoá.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/sd_repository.dart';
import '../../domain/sd_models.dart';
import '../../shared/widgets.dart';
import 'duo_path.dart';
import 'sd_docs_screen.dart' show SdErrorView;

/// Id node "Bối cảnh" ở đầu Phase 2.
const _kContextId = 'context';

/// Một nhóm node của lộ trình: banner + danh sách node (đã có trạng thái).
class _PathGroup {
  _PathGroup(this.eyebrow, this.title, this.nodes);
  final String eyebrow;
  final String title;
  final List<DuoNode> nodes;
}

/// Trạng thái node thô từ server (chưa nâng `current`).
DuoNodeState _fromServer({required bool done, required bool unlocked}) => done
    ? DuoNodeState.done
    : unlocked
    ? DuoNodeState.open
    : DuoNodeState.locked;

/// Dựng các nhóm Phase 1 + Phase 2 từ [doc], rồi nâng đúng MỘT node `open`
/// đầu tiên (theo thứ tự section..., context, task...) thành `current`.
List<_PathGroup> _buildGroups(SdDoc doc) {
  // Nhóm section theo chapterPosition, giữ thứ tự xuất hiện.
  final chapters = <int, List<SdSection>>{};
  for (final s in doc.sections) {
    chapters.putIfAbsent(s.chapterPosition, () => []).add(s);
  }

  final groups = <_PathGroup>[];
  var chapterNo = 0;
  for (final list in chapters.values) {
    chapterNo++;
    final done = list.where((s) => s.done).length;
    groups.add(
      _PathGroup(
        'CHAPTER $chapterNo · $done/${list.length} SECTION',
        list.first.chapter,
        [
          for (final s in list)
            DuoNode(
              id: s.id,
              label: s.title,
              sublabel: '${s.read.length}/${s.cards.length} card',
              state: _fromServer(done: s.done, unlocked: s.unlocked),
            ),
        ],
      ),
    );
  }

  final tasksDone = doc.tasks.where((t) => t.done).length;
  groups.add(
    _PathGroup(
      'PHASE 2 · THỰC CHIẾN · $tasksDone/${doc.tasks.length} TASK',
      'Thiết kế thật',
      [
        // Server không có trường "đã đọc bối cảnh" riêng, nên done suy từ
        // `tasks.any(done)` (dữ liệu của server, client không tự tính khoá).
        DuoNode(
          id: _kContextId,
          label: 'Bối cảnh',
          state: !doc.phase2Unlocked
              ? DuoNodeState.locked
              : tasksDone > 0
              ? DuoNodeState.done
              : DuoNodeState.open,
        ),
        for (final t in doc.tasks)
          DuoNode(
            id: t.id,
            label: t.name,
            state: _fromServer(done: t.done, unlocked: t.unlocked),
          ),
      ],
    ),
  );

  // Nâng node open đầu tiên trong toàn màn hình thành current.
  var promoted = false;
  return [
    for (final g in groups)
      _PathGroup(g.eyebrow, g.title, [
        for (final n in g.nodes)
          if (!promoted && n.state == DuoNodeState.open)
            () {
              promoted = true;
              return DuoNode(
                id: n.id,
                label: n.label,
                sublabel: n.sublabel,
                state: DuoNodeState.current,
              );
            }()
          else
            n,
      ]),
  ];
}

class SdPathScreen extends ConsumerWidget {
  const SdPathScreen({super.key, required this.docId});

  final String docId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(sdDocProvider(docId));
    try {
      await ref.read(sdDocProvider(docId).future);
    } catch (_) {}
  }

  /// Hỏi xác nhận rồi xoá tiến độ đọc; xong tải lại màn này và danh sách.
  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Đặt lại tiến độ?'),
        content: const Text(
          'Tiến độ đọc của tài liệu này sẽ về 0. '
          'Các bài đã nộp vẫn được giữ.',
        ),
        actions: [
          TextButton(
            key: const Key('sd-reset-cancel'),
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            key: const Key('sd-reset-confirm'),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Đặt lại'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Lấy container trước await: server đã xoá tiến độ thì phải invalidate
    // dù người dùng đã rời màn (context không còn mounted).
    final container = ProviderScope.containerOf(context, listen: false);
    String message;
    try {
      await ref.read(sdRepositoryProvider).resetProgress(docId);
      container.invalidate(sdDocProvider(docId));
      container.invalidate(sdDocsProvider);
      message = 'Đã đặt lại tiến độ';
    } on SdApiException catch (e) {
      message = 'Không đặt lại được (mã ${e.statusCode})';
    } catch (_) {
      message = 'Không đặt lại được, thử lại sau';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(sdDocProvider(docId));
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: doc.asData?.value.title ?? 'System Design',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/design'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('sd-preview'),
                    icon: const Icon(Icons.visibility_outlined),
                    tooltip: 'Xem trước (không tính tiến độ)',
                    onPressed: () => context.push(
                      '/design/${Uri.encodeComponent(docId)}/read?preview=1',
                    ),
                  ),
                  IconButton(
                    key: const Key('sd-reset'),
                    icon: const Icon(Icons.restart_alt),
                    tooltip: 'Đặt lại tiến độ',
                    onPressed: () => _reset(context, ref),
                  ),
                ],
              ),
            ),
            Expanded(
              child: doc.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => SdErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(sdDocProvider(docId)),
                ),
                data: (d) => RefreshIndicator(
                  onRefresh: () => _refresh(ref),
                  child: _PathBody(docId: docId, doc: d),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathBody extends ConsumerStatefulWidget {
  const _PathBody({required this.docId, required this.doc});

  final String docId;
  final SdDoc doc;

  @override
  ConsumerState<_PathBody> createState() => _PathBodyState();
}

class _PathBodyState extends ConsumerState<_PathBody> {
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    // Sau frame đầu: đưa node current vào tầm nhìn (một lần mỗi lần mở màn).
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  void _scrollToCurrent() {
    if (_scrolled || !mounted) return;
    _scrolled = true;
    final current = [
      for (final g in _buildGroups(widget.doc))
        for (final n in g.nodes)
          if (n.state == DuoNodeState.current) n.id,
    ].firstOrNull;
    if (current == null) return;
    Element? target;
    void visit(Element e) {
      if (target != null) return;
      if (e.widget.key == Key('duo-node-$current')) {
        target = e;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    final t = target;
    if (t == null) return;
    Scrollable.ensureVisible(t, alignment: 0.4);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  /// Mở màn đích; khi quay lại tải lại tiến độ (server là nguồn sự thật).
  Future<void> _open(String location) async {
    await context.push(location);
    if (!mounted) return;
    ref.invalidate(sdDocProvider(widget.docId));
    ref.invalidate(sdDocsProvider);
  }

  void _onSection(DuoNode n) {
    if (n.state == DuoNodeState.locked) {
      _toast('Hoàn thành section trước để mở khoá');
      return;
    }
    _open(
      '/design/${Uri.encodeComponent(widget.docId)}/read'
      '?section=${Uri.encodeQueryComponent(n.id)}',
    );
  }

  void _onPhase2(DuoNode n) {
    if (n.state == DuoNodeState.locked) {
      // Task chỉ khoá khi Phase 2 chưa mở (server mở mọi task cùng lúc).
      _toast('Đọc xong Phase 1 để mở Thực chiến');
      return;
    }
    _open(
      n.id == _kContextId
          ? '/design/${Uri.encodeComponent(widget.docId)}/context'
          : '/design/${Uri.encodeComponent(widget.docId)}'
                '/tasks/${Uri.encodeComponent(n.id)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups(widget.doc);
    // Dựng TOÀN BỘ (không dùng ListView lười): tài liệu tối đa 200 section nên
    // chấp nhận được, và node current ở rất xa vẫn có element để cuộn tới.
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.s6),
            DuoBanner(eyebrow: groups[i].eyebrow, title: groups[i].title),
            const SizedBox(height: AppSpace.s6),
            // Nhóm cuối là Phase 2, các nhóm trước là chapter của Phase 1.
            DuoPath(
              nodes: groups[i].nodes,
              onTap: i == groups.length - 1 ? _onPhase2 : _onSection,
            ),
          ],
          const SizedBox(height: AppSpace.s6),
        ],
      ),
    );
  }
}
