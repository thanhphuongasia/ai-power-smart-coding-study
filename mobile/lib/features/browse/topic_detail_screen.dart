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

/// Lộ trình bài trong một file: nút lục giác xếp zíc zắc, nối bằng đường cong.
/// Đoạn đường đi ra từ bài đã xong tô xanh.
class _LessonPath extends StatelessWidget {
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

  static const _rowHeight = 150.0;
  static const _nodeTop = 30.0; // chừa chỗ cho bong bóng START
  static const _hexW = 76.0;
  static const _hexH = 70.0;
  static const _zigzag = [0.0, -1.0, 0.0, 1.0];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final swing = (width / 2 - 80).clamp(0.0, 90.0);
        double cx(int i) => width / 2 + _zigzag[i % _zigzag.length] * swing;
        final centers = [
          for (var i = 0; i < exercises.length; i++)
            Offset(cx(i), i * _rowHeight + _nodeTop + _hexH / 2),
        ];
        return SizedBox(
          height: exercises.length * _rowHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PathPainter(
                    centers: centers,
                    done: [for (final e in exercises) passed(e)],
                    doneColor: p.primary,
                    todoColor: p.outline.withValues(alpha: 0.35),
                  ),
                ),
              ),
              for (var i = 0; i < exercises.length; i++)
                Positioned(
                  left: centers[i].dx - 80,
                  top: i * _rowHeight,
                  width: 160,
                  child: _PathNode(
                    exercise: exercises[i],
                    isDone: passed(exercises[i]),
                    isLocked: !unlocked(exercises[i]),
                    isStarted: inProgress(exercises[i]),
                    isNext: identical(exercises[i], next),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
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
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.centers != centers ||
      old.done.toString() != done.toString() ||
      old.doneColor != doneColor ||
      old.todoColor != todoColor;
}

/// Một bài trên lộ trình: nút lục giác nổi (3D), tên method, chữ trạng thái.
/// Chạm để mở bài; bài khoá không điều hướng (INV-08).
class _PathNode extends StatelessWidget {
  const _PathNode({
    required this.exercise,
    required this.isDone,
    required this.isLocked,
    required this.isStarted,
    required this.isNext,
  });

  final Exercise exercise;
  final bool isDone;
  final bool isLocked;
  final bool isStarted;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (String status, IconData icon, Color face) = isLocked
        ? ('Khoá', Icons.lock_outline, p.outline.withValues(alpha: 0.45))
        : isDone
        ? ('Đã xong', Icons.check_rounded, p.primary)
        : isStarted
        ? ('Đang dở', Icons.timelapse, p.accent)
        : ('Mới', Icons.code, p.accent);
    final iconColor = isLocked
        ? p.inkMuted
        : isDone
        ? p.onPrimary
        : p.onAccent;

    final node = GestureDetector(
      key: Key('exercise-${exercise.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: isLocked ? null : () => context.push('/exercise/${exercise.id}'),
      child: Column(
        children: [
          SizedBox(
            height: _LessonPath._nodeTop,
            child: isNext
                ? _StartBubble(key: Key('start-${exercise.id}'))
                : null,
          ),
          SizedBox(
            width: _LessonPath._hexW,
            height: _LessonPath._hexH,
            child: CustomPaint(
              painter: _HexPainter(face: face),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Icon(icon, size: 30, color: iconColor),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.s1),
          Text(
            '${exercise.qualifiedName}()',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.code.copyWith(
              fontSize: 12,
              color: isLocked ? p.inkMuted : p.ink,
            ),
          ),
          Text(
            status,
            style: AppText.caption.copyWith(
              color: isDone ? p.primary : p.inkMuted,
            ),
          ),
        ],
      ),
    );
    if (!isLocked) return node;
    return Tooltip(message: 'Hoàn thành bài trước để mở', child: node);
  }
}

class _StartBubble extends StatelessWidget {
  const _StartBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: p.outline.withValues(alpha: 0.5), width: 2),
        ),
        child: Text(
          'START',
          style: AppText.label.copyWith(
            color: p.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

/// Lục giác đỉnh nhọn hai lớp: lớp dưới tối hơn, lệch xuống → cảm giác nổi khối.
class _HexPainter extends CustomPainter {
  _HexPainter({required this.face});

  final Color face;

  static const _depth = 8.0;

  Path _hex(Size s, double dy) {
    final w = s.width;
    final h = s.height - _depth;
    return Path()
      ..moveTo(w / 2, dy)
      ..lineTo(w, dy + h * 0.25)
      ..lineTo(w, dy + h * 0.75)
      ..lineTo(w / 2, dy + h)
      ..lineTo(0, dy + h * 0.75)
      ..lineTo(0, dy + h * 0.25)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = Color.lerp(face, Colors.black, 0.28)!;
    canvas.drawPath(_hex(size, _depth), Paint()..color = side);
    canvas.drawPath(_hex(size, 0), Paint()..color = face);
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.face != face;
}

/// Tên file; nếu file còn được dùng ở theme khác thì hiện nhãn "Dùng ở N
/// theme" và chạm để mở màn File cross-cut.
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
    final name = Text(file.name, style: AppText.code.copyWith(color: p.ink));
    if (themeCount < 2) return name;

    return InkWell(
      key: Key('file-${file.id}'),
      onTap: () => context.push('/file/${Uri.encodeComponent(file.name)}'),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
        child: Row(
          children: [
            Expanded(child: name),
            Container(
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
            const SizedBox(width: AppSpace.s1),
            Icon(Icons.chevron_right, size: 18, color: p.inkMuted),
          ],
        ),
      ),
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
    return Text(
      'class $className',
      key: Key('class-$fileId-$className'),
      style: AppText.label.copyWith(color: context.palette.inkMuted),
    );
  }
}
