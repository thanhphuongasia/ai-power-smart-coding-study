/// Màn module: lộ trình bài kiểu Duolingo theo từng file (nút lục giác zíc zắc,
/// đường nối xanh khi xong, START ở bài kế tiếp), sub-module là chặng sau.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/content_providers.dart';
import '../../domain/content.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import '../exercise/session_providers.dart';

class TopicDetailScreen extends ConsumerWidget {
  const TopicDetailScreen(this.topicId, {super.key});

  final String topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final content = ref.watch(contentIndexProvider);
    final located = content.locateTopic(topicId);
    if (located == null) {
      throw StateError('Không tìm thấy topic với id: $topicId');
    }
    final theme = located.theme;
    final topic = located.topic;
    final breadcrumb = [
      theme.name,
      for (final m in content.modulePath(topicId)) m.name,
    ].join(' › ');

    bool passed(Exercise e) => progress[e.id]?.passed ?? false;
    bool unlocked(Exercise e) =>
        passed(e) || ref.watch(exerciseUnlockedProvider(e.id));
    // Bài kế tiếp nên làm: bài đầu tiên (theo thứ tự học) đã mở mà chưa xong.
    final own = [for (final f in topic.files) ...f.exercises];
    final next = own.where((e) => !passed(e) && unlocked(e)).firstOrNull;
    final all = [for (final f in topic.allFiles) ...f.exercises];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: topic.name,
              subtitle: breadcrumb,
              onBack: () => context.pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.s4,
                0,
                AppSpace.s4,
                AppSpace.s2,
              ),
              child: SegmentedProgress(
                key: const Key('module-progress'),
                done: [for (final e in all) passed(e)],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.s4,
                  AppSpace.s2,
                  AppSpace.s4,
                  AppSpace.s6,
                ),
                children: [
                  // Thứ tự học: file của module trước, sub-module sau (khớp allFiles).
                  for (final file in topic.files) ...[
                    _FileHeader(file: file, content: content),
                    for (final cls in {
                      for (final e in file.exercises)
                        if (e.className != null) e.className!,
                    })
                      _ClassHeader(fileId: file.id, className: cls),
                    if (file.exercises.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.s2),
                      _LessonPath(
                        exercises: file.exercises,
                        passed: passed,
                        unlocked: unlocked,
                        inProgress: (e) => progress[e.id]?.inProgress ?? false,
                        next: next,
                      ),
                    ],
                    const SizedBox(height: AppSpace.s4),
                  ],
                  for (final module in topic.modules) ...[
                    _ModuleCard(module: module, passed: passed),
                    const SizedBox(height: AppSpace.s4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thanh tiến độ chia đoạn kiểu Duolingo: mỗi bài một đoạn, xanh khi xong.
class SegmentedProgress extends StatelessWidget {
  const SegmentedProgress({super.key, required this.done});

  final List<bool> done;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final count = done.where((d) => d).length;
    final complete = done.isNotEmpty && count == done.length;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s4,
        vertical: AppSpace.s2,
      ),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: p.outline.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.track_changes, size: 20, color: p.primary),
          const SizedBox(width: AppSpace.s2),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < done.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: done[i]
                            ? p.primary
                            : p.outline.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s2),
          Text(
            complete ? 'Hoàn thành' : '$count/${done.length}',
            style: AppText.label.copyWith(
              color: complete ? p.primary : p.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lộ trình bài trong một file kiểu Coddy/Duolingo: nút lục giác nổi khối xếp
/// zíc zắc, đường nối dày phía sau (xanh khi đã đi qua). Chạm nút → thẻ nhỏ
/// hiện tên bài + nút mở; bài khoá chỉ báo cần làm bài trước (INV-08).
class _LessonPath extends StatefulWidget {
  const _LessonPath({
    required this.exercises,
    required this.passed,
    required this.unlocked,
    required this.inProgress,
    required this.next,
  });

  final List<Exercise> exercises;
  final bool Function(Exercise) passed;
  final bool Function(Exercise) unlocked;
  final bool Function(Exercise) inProgress;
  final Exercise? next;

  static const rowHeight = 124.0;
  static const nodeTop = 38.0; // chỗ cho bong bóng START
  static const hexW = 84.0;
  static const hexH = 82.0;
  static const _zigzag = [0.0, -1.0, 0.0, 1.0];
  static const _popW = 260.0;
  static const _popH = 220.0; // trần chiều cao thẻ (tiêu đề 2 dòng + nút)

  @override
  State<_LessonPath> createState() => _LessonPathState();
}

class _LessonPathState extends State<_LessonPath> {
  String? _open; // id bài đang mở thẻ
  final _popoverKey = GlobalKey();

  void _toggle(String id) {
    setState(() => _open = _open == id ? null : id);
    if (_open == null) return;
    // Thẻ mở ở nút gần đáy màn hình → cuộn cho thấy đủ thẻ và nút mở bài.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _popoverKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final p = context.palette;
    final ex = w.exercises;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final swing = (width / 2 - 70).clamp(0.0, 80.0);
        double cx(int i) =>
            width / 2 +
            _LessonPath._zigzag[i % _LessonPath._zigzag.length] * swing;
        Offset center(int i) => Offset(
          cx(i),
          i * _LessonPath.rowHeight +
              _LessonPath.nodeTop +
              _LessonPath.hexH / 2,
        );
        final openIndex = ex.indexWhere((e) => e.id == _open);
        final popTop = openIndex < 0
            ? 0.0
            : openIndex * _LessonPath.rowHeight +
                  _LessonPath.nodeTop +
                  _LessonPath.hexH +
                  6;
        // Chạm chỉ nhận trong khung của Stack: nới chiều cao cho thẻ nằm trọn
        // bên trong, kể cả khi mở ở nút cuối file.
        final extra = openIndex < 0
            ? 0.0
            : (popTop + _LessonPath._popH - ex.length * _LessonPath.rowHeight)
                  .clamp(0.0, double.infinity);
        return SizedBox(
          height: ex.length * _LessonPath.rowHeight + extra,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PathPainter(
                    centers: [for (var i = 0; i < ex.length; i++) center(i)],
                    done: [for (final e in ex) w.passed(e)],
                    doneColor: p.primary,
                    todoColor: Color.alphaBlend(
                      p.ink.withValues(alpha: 0.08),
                      p.surface,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < ex.length; i++)
                Positioned(
                  left: center(i).dx - _LessonPath.hexW / 2 - 50,
                  top: i * _LessonPath.rowHeight,
                  width: _LessonPath.hexW + 100,
                  child: _PathNode(
                    exercise: ex[i],
                    state: _stateOf(ex[i]),
                    isNext: identical(ex[i], w.next),
                    iconIndex: i,
                    onTap: () => _toggle(ex[i].id),
                  ),
                ),
              if (openIndex >= 0)
                Positioned(
                  left: (center(openIndex).dx - _LessonPath._popW / 2).clamp(
                    0.0,
                    (width - _LessonPath._popW).clamp(0.0, double.infinity),
                  ),
                  top: popTop,
                  width: _LessonPath._popW,
                  child: _LessonPopover(
                    key: _popoverKey,
                    exercise: ex[openIndex],
                    state: _stateOf(ex[openIndex]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  _NodeState _stateOf(Exercise e) => !widget.unlocked(e)
      ? _NodeState.locked
      : widget.passed(e)
      ? _NodeState.done
      : widget.inProgress(e)
      ? _NodeState.started
      : _NodeState.fresh;
}

enum _NodeState {
  done('done', 'Đã xong'),
  started('started', 'Đang dở'),
  fresh('new', 'Mới'),
  locked('locked', 'Khoá');

  const _NodeState(this.key, this.label);
  final String key;
  final String label;
}

class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.centers,
    required this.done,
    required this.doneColor,
    required this.todoColor,
  });

  final List<Offset> centers;
  final List<bool> done;
  final Color doneColor;
  final Color todoColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i + 1 < centers.length; i++) {
      final a = centers[i];
      final b = centers[i + 1];
      final midY = (a.dy + b.dy) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, midY, b.dx, midY, b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = done[i] ? doneColor : todoColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.centers.toString() != centers.toString() ||
      old.done.toString() != done.toString() ||
      old.doneColor != doneColor ||
      old.todoColor != todoColor;
}

/// Một bài trên lộ trình: chỉ có nút lục giác (+ START nếu là bài kế tiếp).
class _PathNode extends StatelessWidget {
  const _PathNode({
    required this.exercise,
    required this.state,
    required this.isNext,
    required this.iconIndex,
    required this.onTap,
  });

  final Exercise exercise;
  final _NodeState state;
  final bool isNext;
  final int iconIndex;
  final VoidCallback onTap;

  static const _lessonIcons = [
    Icons.menu_book_outlined,
    Icons.psychology_outlined,
    Icons.lightbulb_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final grey = Color.alphaBlend(p.ink.withValues(alpha: 0.10), p.surface);
    final (Color face, Color iconColor) = switch (state) {
      _NodeState.done => (p.primary, Colors.white),
      // Bài kế tiếp / đang làm: xám đậm, icon trắng (giống Coddy).
      _ when isNext || state == _NodeState.started => (
        Color.alphaBlend(p.ink.withValues(alpha: 0.42), p.surface),
        Colors.white,
      ),
      _ => (grey, Color.alphaBlend(p.ink.withValues(alpha: 0.28), p.surface)),
    };
    final icon = state == _NodeState.done
        ? Icons.check_rounded
        : _lessonIcons[iconIndex % _lessonIcons.length];

    return Semantics(
      button: true,
      label: '${exercise.qualifiedName}() · ${state.label}',
      child: GestureDetector(
        key: Key('exercise-${exercise.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            SizedBox(
              height: _LessonPath.nodeTop,
              child: isNext
                  ? _StartBubble(key: Key('start-${exercise.id}'))
                  // Đã mở nhưng chưa tới lượt: mời nhảy cóc, chữ nhạt.
                  : state == _NodeState.fresh || state == _NodeState.started
                  ? _StartBubble(
                      key: Key('jump-${exercise.id}'),
                      text: 'JUMP HERE?',
                      faded: true,
                    )
                  : null,
            ),
            SizedBox(
              width: _LessonPath.hexW,
              height: _LessonPath.hexH,
              child: CustomPaint(
                painter: _HexPainter(face: face),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: _HexPainter.depth),
                  child: Icon(
                    icon,
                    size: state == _NodeState.done ? 38 : 30,
                    color: iconColor,
                  ),
                ),
              ),
            ),
            // Trạng thái cho test/trợ năng — không vẽ gì.
            SizedBox.shrink(key: Key('state-${state.key}')),
          ],
        ),
      ),
    );
  }
}

/// Thẻ hiện khi chạm một nút: tên bài, method, số ô và nút mở bài.
class _LessonPopover extends StatelessWidget {
  const _LessonPopover({
    super.key,
    required this.exercise,
    required this.state,
  });

  final Exercise exercise;
  final _NodeState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final locked = state == _NodeState.locked;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: locked ? p.surfaceRaised : p.primary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: locked ? p.outline.withValues(alpha: 0.5) : p.primary,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: p.ink.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            exercise.title,
            style: AppText.title.copyWith(color: locked ? p.ink : p.onPrimary),
          ),
          const SizedBox(height: AppSpace.s1),
          Text(
            '${exercise.qualifiedName}() · ${exercise.blocks.length} ô',
            style: AppText.code.copyWith(
              fontSize: 12,
              color: locked ? p.inkMuted : p.onPrimary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpace.s2),
          if (locked)
            Text(
              'Hoàn thành bài trước để mở',
              style: AppText.label.copyWith(color: p.inkMuted),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: Key('lesson-go-${exercise.id}'),
                onPressed: () => context.push('/exercise/${exercise.id}'),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: p.surfaceRaised,
                  foregroundColor: p.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: Text(switch (state) {
                  _NodeState.done => 'Ôn lại',
                  _NodeState.started => 'Tiếp tục',
                  _ => 'Bắt đầu',
                }, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bong bóng có đuôi nhọn chỉ xuống nút: START (bài kế tiếp) hoặc, chữ nhạt,
/// JUMP HERE? (bài đã mở nhưng chưa tới lượt).
class _StartBubble extends StatelessWidget {
  const _StartBubble({super.key, this.text = 'START', this.faded = false});

  final String text;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final border = p.outline.withValues(alpha: faded ? 0.25 : 0.4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 2),
          ),
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: AppText.label.copyWith(
              color: p.primary.withValues(alpha: faded ? 0.45 : 1),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(14, 7),
          painter: _TailPainter(fill: p.surfaceRaised, stroke: border),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, -2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, -2);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.fill != fill || old.stroke != stroke;
}

/// Lục giác đỉnh nhọn bo góc, nổi khối: thành dưới tối, mặt trên, rồi một mặt
/// trong nhỏ hơn có viền dưới tối — giống nút bài học của Coddy.
class _HexPainter extends CustomPainter {
  _HexPainter({required this.face});

  final Color face;

  static const depth = 10.0;

  static Path hex(Rect r, double radius) {
    final pts = [
      Offset(r.center.dx, r.top),
      Offset(r.right, r.top + r.height * 0.25),
      Offset(r.right, r.top + r.height * 0.75),
      Offset(r.center.dx, r.bottom),
      Offset(r.left, r.top + r.height * 0.75),
      Offset(r.left, r.top + r.height * 0.25),
    ];
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final prev = pts[(i + pts.length - 1) % pts.length];
      final cur = pts[i];
      final next = pts[(i + 1) % pts.length];
      final a = cur + (prev - cur) / (prev - cur).distance * radius;
      final b = cur + (next - cur) / (next - cur).distance * radius;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = Color.lerp(face, Colors.black, 0.22)!;
    final top = Rect.fromLTWH(0, 0, size.width, size.height - depth);
    canvas.drawPath(
      hex(top.shift(const Offset(0, depth)), 10),
      Paint()..color = side,
    );
    canvas.drawPath(hex(top, 10), Paint()..color = face);
    // Mặt trong: nhỏ hơn, có gờ dưới tối → cảm giác nút bấm.
    final inner = top.deflate(9);
    canvas.drawPath(
      hex(inner.shift(const Offset(0, 4)), 8),
      Paint()..color = side,
    );
    canvas.drawPath(
      hex(inner, 8),
      Paint()..color = Color.lerp(face, Colors.white, 0.08)!,
    );
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.face != face;
}

/// Dải phân cách chặng: tên file ở giữa hai đường kẻ (kiểu Coddy). File còn
/// được dùng ở theme khác thì có nhãn "Dùng ở N theme" → màn File cross-cut.
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.file, required this.content});

  final CodeFile file;
  final Content content;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final themeCount = content
        .locateFilesNamed(file.name)
        .map((u) => u.theme.id)
        .toSet()
        .length;
    final line = Expanded(
      child: Divider(color: p.outline.withValues(alpha: 0.4), thickness: 1.5),
    );
    return Column(
      children: [
        Row(
          children: [
            line,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2),
              child: Text(
                file.name,
                style: AppText.code.copyWith(
                  fontSize: 16,
                  color: p.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            line,
          ],
        ),
        if (themeCount >= 2)
          InkWell(
            key: Key('file-${file.id}'),
            onTap: () =>
                context.push('/file/${Uri.encodeComponent(file.name)}'),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              margin: const EdgeInsets.only(top: AppSpace.s1),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.s2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: p.primary),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Dùng ở $themeCount theme',
                style: AppText.caption.copyWith(color: p.primary),
              ),
            ),
          ),
      ],
    );
  }
}

/// Thẻ module con: tên, mô tả, số bài (gồm cả module lồng bên trong).
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.passed});

  final Topic module;
  final bool Function(Exercise) passed;

  @override
  Widget build(BuildContext context) {
    final exercises = [for (final f in module.allFiles) ...f.exercises];
    final count = exercises.length;
    return SurfaceCard(
      key: Key('module-${module.id}'),
      onTap: () => context.push('/topic/${module.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(module.name, style: AppText.title),
            if (module.description.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s1),
              Text(
                module.description,
                style: AppText.body.copyWith(color: context.palette.inkMuted),
              ),
            ],
            const SizedBox(height: AppSpace.s2),
            Text(
              '$count bài tập',
              style: AppText.caption.copyWith(color: context.palette.inkMuted),
            ),
            if (count > 0) ...[
              const SizedBox(height: AppSpace.s2),
              SegmentedProgress(done: [for (final e in exercises) passed(e)]),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassHeader extends StatelessWidget {
  const _ClassHeader({required this.fileId, required this.className});

  final String fileId;
  final String className;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'class $className',
        key: Key('class-$fileId-$className'),
        style: AppText.caption.copyWith(color: context.palette.inkMuted),
      ),
    );
  }
}
