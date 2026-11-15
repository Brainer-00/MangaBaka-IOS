import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

class ChipBase extends StatelessWidget {
  final Widget label;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final TextStyle? labelStyle;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChipBase({
    required this.label,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 16,
    this.padding,
    this.labelStyle,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = backgroundColor ?? colors.surfaceRaised;
    final chip = Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1)
            : null,
      ),
      child: DefaultTextStyle(
        style:
            labelStyle ??
            AppTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: MbPalette.ensureContrast(
                colors.text,
                background,
                minimum: 4.5,
              ),
              height: 1.2,
            ),
        child: label,
      ),
    );

    if (onTap != null || onLongPress != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(borderRadius),
          hoverColor: colors.accent.withValues(alpha: 0.08),
          splashColor: colors.accent.withValues(alpha: 0.12),
          child: chip,
        ),
      );
    }

    return chip;
  }
}
