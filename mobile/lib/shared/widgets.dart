import 'package:flutter/material.dart';
import 'package:smart_coding_study/app/theme.dart';

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool highlighted;

  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      child: Material(
        color: context.palette.surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: highlighted ? context.palette.primary : context.palette.outline,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: child,
        ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  final String label;

  const TagChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s2,
        vertical: AppSpace.s1,
      ),
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        border: Border.all(
          color: context.palette.outline,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(color: context.palette.ink),
      ),
    );
  }
}

class ResultBadge extends StatelessWidget {
  final bool passed;

  const ResultBadge({super.key, required this.passed});

  @override
  Widget build(BuildContext context) {
    final text = passed ? 'Đúng' : 'Chưa đúng';
    final icon = passed ? Icons.check_circle : Icons.cancel;
    final color = passed ? context.palette.primary : context.palette.danger;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s2,
        vertical: AppSpace.s1,
      ),
      decoration: BoxDecoration(
        color: context.palette.surfaceRaised,
        border: Border.all(
          color: color,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpace.s1),
          Text(
            text,
            style: AppText.label.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class TimerPill extends StatelessWidget {
  final Duration elapsed;
  final bool warning;

  const TimerPill(
    this.elapsed, {
    super.key,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    final text = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s4,
        vertical: AppSpace.s2,
      ),
      decoration: BoxDecoration(
        color: warning ? context.palette.danger.withValues(alpha: 0.2) : context.palette.surfaceRaised,
        border: Border.all(
          color: warning ? context.palette.danger : context.palette.outline,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppText.code.copyWith(
          color: warning ? context.palette.danger : context.palette.ink,
        ),
      ),
    );
  }
}

class ThinProgressBar extends StatelessWidget {
  final double value;
  final Color? color;

  const ThinProgressBar({
    super.key,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        color: context.palette.outline.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(1),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color ?? context.palette.primary,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;

  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s4,
        vertical: AppSpace.s4,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(
          bottom: BorderSide(
            color: context.palette.outline,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Quay lại',
              onPressed: onBack,
            ),
          if (onBack != null) const SizedBox(width: AppSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.s1),
                  Text(
                    subtitle!,
                    style: AppText.body.copyWith(color: context.palette.inkMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.s4),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
      child: Text(
        text,
        style: AppText.label.copyWith(color: context.palette.inkMuted),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon) : const SizedBox.shrink(),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: context.palette.primary,
        foregroundColor: context.palette.onPrimary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s4,
          vertical: AppSpace.s2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.palette.ink,
        side: BorderSide(
          color: context.palette.outline,
          width: 1,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s4,
          vertical: AppSpace.s2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: Text(label),
    );
  }
}

class HintButton extends StatelessWidget {
  final int used;
  final int max;
  final VoidCallback? onPressed;

  const HintButton({
    super.key,
    required this.used,
    this.max = 3,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (max - used).clamp(0, max);
    final label = 'Gợi ý ($remaining/$max)';

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.lightbulb),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: context.palette.accent,
        foregroundColor: context.palette.onAccent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s4,
          vertical: AppSpace.s2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
