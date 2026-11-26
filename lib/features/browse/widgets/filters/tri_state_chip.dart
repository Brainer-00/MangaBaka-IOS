import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

enum TriState { off, include, exclude }

class TriStateChip extends StatelessWidget {
  final String label;
  final TriState state;
  final ValueChanged<TriState> onChanged;

  const TriStateChip({
    super.key,
    required this.label,
    required this.state,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Color? backgroundColor;
    Color textColor = colors.text;
    IconData? icon;

    switch (state) {
      case TriState.include:
        backgroundColor = Color.alphaBlend(
          colors.accent.withValues(alpha: 0.2),
          colors.surface,
        );
        textColor = colors.accentOn(backgroundColor);
        icon = Icons.check;
        break;
      case TriState.exclude:
        backgroundColor = Color.alphaBlend(
          colors.error.withValues(alpha: 0.2),
          colors.surface,
        );
        textColor = MbPalette.ensureContrast(
          colors.error,
          backgroundColor,
          minimum: 4.5,
        );
        icon = Icons.close;
        break;
      case TriState.off:
        backgroundColor = Color.alphaBlend(
          colors.border.withValues(alpha: 0.25),
          colors.surface,
        );
        textColor = MbPalette.ensureContrast(
          colors.textMuted,
          backgroundColor,
          minimum: 4.5,
        );
        icon = null;
        break;
    }

    return ActionChip(
      label: Text(label, style: AppTypography.sans(color: textColor)),
      backgroundColor: backgroundColor,
      side: BorderSide.none,
      avatar: icon != null ? Icon(icon, size: 16, color: textColor) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      onPressed: () {
        if (state == TriState.off) {
          onChanged(TriState.include);
        } else if (state == TriState.include) {
          onChanged(TriState.exclude);
        } else {
          onChanged(TriState.off);
        }
      },
    );
  }
}
