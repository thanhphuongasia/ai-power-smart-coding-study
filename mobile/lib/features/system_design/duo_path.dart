import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Trạng thái một node trên lộ trình. Do server/bên gọi quyết định; widget
/// chỉ vẽ, KHÔNG tự tính khoá/mở.
enum DuoNodeState { done, current, open, locked }

/// Dữ liệu một node. `sublabel` là dòng phụ nhỏ (ví dụ "3/5 card").
@immutable
class DuoNode {
  const DuoNode({
    required this.id,
    required this.label,
    required this.state,
    this.sublabel,
  });

  final String id;
  final String label;
  final DuoNodeState state;
  final String? sublabel;
}

const double _kDiscSize = 76;
const double _kDiscDepth = 6; // độ dày 3D của đĩa
const double _kNodeGap = 28; // khoảng cách dọc giữa hai node
const double _kNodeWidth = 160; // bề rộng vùng nhãn quanh đĩa
// Độ lệch ngang theo chu kỳ kiểu sin, lặp lại theo chỉ số node.
const List<double> _kZigzag = [0, -44, -72, -44, 0, 44, 72, 44];

String _stateText(DuoNodeState s) => switch (s) {
  DuoNodeState.done => 'đã xong',
  DuoNodeState.current => 'đang học',
  DuoNodeState.open => 'đã mở',
  DuoNodeState.locked => 'chưa mở',
};

/// Dải xanh lá phía trên lộ trình: chữ nhỏ in hoa + tiêu đề đậm; đáy viền
/// dày hơn để có hiệu ứng nút 3D.
class DuoBanner extends StatelessWidget {
  const DuoBanner({super.key, required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('duo-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: p.success,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border(bottom: BorderSide(color: p.successDark, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: AppText.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(title, style: AppText.title.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

/// Lộ trình kiểu Duolingo: cột đĩa tròn 3D xếp zigzag. Chạm đĩa gọi `onTap`
/// kể cả node locked — bên gọi tự quyết hiển thị thông báo khoá.
class DuoPath extends StatelessWidget {
  const DuoPath({super.key, required this.nodes, required this.onTap});

  final List<DuoNode> nodes;
  final void Function(DuoNode) onTap;

  @override
  Widget build(BuildContext context) {
    // Bóng "BẮT ĐẦU" chỉ dành cho node current ĐẦU TIÊN (tối đa một).
    final currentIdx = nodes.indexWhereCurrent();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < nodes.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : _kNodeGap),
            child: Transform.translate(
              offset: Offset(_kZigzag[i % _kZigzag.length], 0),
              child: _DuoNodeView(
                node: nodes[i],
                showBubble: i == currentIdx,
                onTap: () => onTap(nodes[i]),
              ),
            ),
          ),
      ],
    );
  }
}

extension on List<DuoNode> {
  int indexWhereCurrent() => indexWhere((n) => n.state == DuoNodeState.current);
}

class _DuoNodeView extends StatelessWidget {
  const _DuoNodeView({
    required this.node,
    required this.showBubble,
    required this.onTap,
  });

  final DuoNode node;
  final bool showBubble;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = node.state;

    final (
      Color face,
      Color base,
      Color iconColor,
      IconData icon,
    ) = switch (state) {
      DuoNodeState.done => (
        p.success,
        p.successDark,
        Colors.white,
        Icons.check_rounded,
      ),
      DuoNodeState.current => (
        p.primary,
        p.primaryDark,
        Colors.white,
        Icons.play_arrow_rounded,
      ),
      DuoNodeState.open => (
        p.primary,
        p.primaryDark,
        Colors.white,
        Icons.star_rounded,
      ),
      DuoNodeState.locked => (
        p.outline,
        Color.lerp(p.outline, p.inkMuted, 0.45)!,
        p.inkMuted,
        Icons.lock_rounded,
      ),
    };

    final disc = SizedBox(
      width: _kDiscSize,
      height: _kDiscSize + _kDiscDepth,
      child: Stack(
        children: [
          // Lớp đáy (độ dày): cùng hình, đậm hơn, lệch xuống.
          Positioned(
            top: _kDiscDepth,
            child: Container(
              width: _kDiscSize,
              height: _kDiscSize,
              decoration: BoxDecoration(color: base, shape: BoxShape.circle),
            ),
          ),
          // Mặt trên (kèm quầng sáng nếu là node current).
          Container(
            key: Key('duo-face-${node.id}'),
            width: _kDiscSize,
            height: _kDiscSize,
            decoration: BoxDecoration(
              color: face,
              shape: BoxShape.circle,
              boxShadow: state == DuoNodeState.current
                  ? [
                      BoxShadow(
                        color: p.primary.withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: iconColor, size: 38),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      // Gồm cả sublabel (tiến độ) vì excludeSemantics nuốt Text con.
      label: [
        node.label,
        if (node.sublabel != null) node.sublabel!,
        _stateText(state),
      ].join(', '),
      onTap: onTap,
      child: SizedBox(
        width: _kNodeWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBubble) ...[
              _StartBubble(palette: p),
              const SizedBox(height: 6),
            ],
            GestureDetector(
              key: Key('duo-node-${node.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: disc,
            ),
            const SizedBox(height: 8),
            Text(
              node.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                color: state == DuoNodeState.locked ? p.inkMuted : p.ink,
              ),
            ),
            if (node.sublabel != null)
              Text(
                node.sublabel!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: p.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bóng thoại trắng "BẮT ĐẦU" có mũi nhọn chỉ xuống đĩa.
class _StartBubble extends StatelessWidget {
  const _StartBubble({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('duo-start-bubble'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: const Color(0xFFD9DDE3), width: 2),
          ),
          child: Text(
            'BẮT ĐẦU',
            style: AppText.label.copyWith(
              color: palette.primaryDark,
              letterSpacing: 0.8,
            ),
          ),
        ),
        // Mũi nhọn: hình vuông xoay 45 độ, nửa dưới lộ ra dưới bóng.
        Transform.translate(
          offset: const Offset(0, -6),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  right: BorderSide(color: Color(0xFFD9DDE3), width: 2),
                  bottom: BorderSide(color: Color(0xFFD9DDE3), width: 2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
