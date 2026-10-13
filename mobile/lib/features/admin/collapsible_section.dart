import 'package:flutter/material.dart';
import 'package:smart_coding_study/app/theme.dart';

enum SectionStatus { ok, warn, error }

/// Mục đóng/mở được cho màn soạn bài tập. Khi đóng, [child] không được dựng
/// (không nằm trong cây widget), chỉ hiện [summary] một dòng.
class CollapsibleSection extends StatefulWidget {
  final String title;
  final String? summary;
  final SectionStatus status;
  final bool initiallyOpen;
  final Widget? trailing;
  final Widget child;

  const CollapsibleSection({
    super.key,
    required this.title,
    this.summary,
    this.status = SectionStatus.ok,
    this.initiallyOpen = true,
    this.trailing,
    required this.child,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyOpen;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border.all(color: palette.outline, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _toggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.s4,
                        vertical: AppSpace.s2,
                      ),
                      child: Row(
                        children: [
                          _StatusDot(color: _statusColor(palette, widget.status)),
                          const SizedBox(width: AppSpace.s2),
                          Flexible(
                            child: Text(
                              widget.title,
                              style: AppText.body.copyWith(
                                color: palette.ink,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_open && widget.summary != null) ...[
                            const SizedBox(width: AppSpace.s2),
                            Flexible(
                              child: Text(
                                widget.summary!,
                                style: AppText.caption.copyWith(color: palette.inkMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
                InkWell(
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s2),
                    child: _Chevron(open: _open, color: palette.inkMuted),
                  ),
                ),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s4, 0, AppSpace.s4, AppSpace.s4),
                child: widget.child,
              ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ đóng/mở cho ô A/B/C: header có [badge], tiêu đề, id phụ [subtitle] và
/// [actions]; bấm vùng tiêu đề để đóng/mở.
class CollapsibleCard extends StatefulWidget {
  final Widget badge;
  final String title;
  final String? subtitle;
  final bool initiallyOpen;
  final List<Widget> actions;
  final Widget child;

  const CollapsibleCard({
    super.key,
    required this.badge,
    required this.title,
    this.subtitle,
    this.initiallyOpen = true,
    this.actions = const [],
    required this.child,
  });

  @override
  State<CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<CollapsibleCard> {
  late bool _open = widget.initiallyOpen;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: palette.outline, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: palette.surface,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _toggle,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.s4,
                          vertical: AppSpace.s2,
                        ),
                        child: Row(
                          children: [
                            widget.badge,
                            const SizedBox(width: AppSpace.s2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    style: AppText.label.copyWith(color: palette.ink),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.subtitle != null)
                                    Text(
                                      widget.subtitle!,
                                      style: AppText.code.copyWith(
                                        fontSize: 11.5,
                                        color: palette.inkMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ...widget.actions,
                  InkWell(
                    onTap: _toggle,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.s2),
                      child: _Chevron(open: _open, color: palette.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.all(AppSpace.s4),
                child: widget.child,
              ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(AppPalette palette, SectionStatus status) {
  return switch (status) {
    SectionStatus.ok => palette.primary,
    SectionStatus.warn => palette.accent,
    SectionStatus.error => palette.danger,
  };
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Chevron extends StatelessWidget {
  final bool open;
  final Color color;

  const _Chevron({required this.open, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: open ? 0 : -0.25,
      duration: const Duration(milliseconds: 150),
      child: Icon(Icons.expand_more, size: 18, color: color),
    );
  }
}
