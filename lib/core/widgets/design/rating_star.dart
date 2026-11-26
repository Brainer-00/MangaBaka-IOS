import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';

/// Keeps the same yellow on every surface, with a dark backing when needed.
class RatingStar extends StatelessWidget {
  const RatingStar({
    super.key,
    required this.surface,
    this.icon = Icons.star_rounded,
    this.size = 18,
  });

  final Color surface;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    const yellow = AppConstants.starColor;
    final glyph = Icon(icon, color: yellow, size: size);
    if (MbPalette.contrastRatio(yellow, surface) >= 3) return glyph;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppConstants.primaryBackground,
        shape: BoxShape.circle,
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: glyph),
    );
  }
}
