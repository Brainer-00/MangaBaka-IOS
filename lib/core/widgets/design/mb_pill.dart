import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/motion/app_motion.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

/// Uppercase pill — the design system's single selectable-chip shape.
///
/// Selected reads as a solid amber fill with ink-black caps; unselected is a
/// flat dark well with white caps. Used for browse type tabs, filter chips and
/// any other one-of-many choice.
class MbPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final IconData? icon;

  /// Shown as a small count/qualifier after the label (e.g. an active filter
  /// count). Its smaller type preserves hierarchy without reducing contrast.
  final String? trailingText;

  const MbPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.icon,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = selected ? colors.accent : colors.surfaceRaised;
    final fg = selected ? colors.onAccent : colors.text;
    final trailingFg = MbPalette.ensureContrast(
      selected ? colors.onAccent : colors.textMuted,
      fill,
      minimum: 4.5,
    );

    return MbTappable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.emphasized,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppConstants.pillRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 7),
              ],
              AnimatedDefaultTextStyle(
                duration: AppMotion.fast,
                curve: AppMotion.emphasized,
                style: AppTypography.display(color: fg, fontSize: 13),
                child: Text(label.toUpperCase()),
              ),
              if (trailingText != null) ...[
                const SizedBox(width: 6),
                Text(
                  trailingText!,
                  style: AppTypography.display(color: trailingFg, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling row of [MbPill]s, matching the reference's genre
/// tab strip. Bleeds to the screen edge so the strip reads as scrollable.
class MbPillStrip extends StatelessWidget {
  final List<Widget> pills;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  const MbPillStrip({
    super.key,
    required this.pills,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppConstants.horizontalPadding,
    ),
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < pills.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            pills[i],
          ],
        ],
      ),
    );
  }
}
