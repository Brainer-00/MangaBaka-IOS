import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

/// Small uppercase badge — the reference's amber "TOP" tag.
///
/// [MbBadge.accent] is the loud amber-on-ink variant; the default constructor
/// is the quiet dark-well variant used for neutral metadata (type, status).
class MbBadge extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;
  final bool _accent;

  const MbBadge({
    super.key,
    required this.label,
    this.background,
    this.foreground,
  }) : _accent = false;

  const MbBadge.accent({super.key, required this.label})
    : background = null,
      foreground = null,
      _accent = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = background ?? (_accent ? colors.accent : colors.surfaceRaised);
    final ink = foreground ?? (_accent ? colors.onAccent : colors.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.display(color: ink, fontSize: 10),
      ),
    );
  }
}
