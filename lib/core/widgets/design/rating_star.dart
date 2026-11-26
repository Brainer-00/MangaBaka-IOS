import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';

/// A standalone rating glyph with the same pigment on every surface.
class RatingStar extends StatelessWidget {
  const RatingStar({super.key, this.icon = Icons.star_rounded, this.size = 18});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SemanticYellowIcon(icon: icon, size: size);
}

class SemanticYellowIcon extends StatelessWidget {
  const SemanticYellowIcon({super.key, required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, color: AppConstants.semanticYellow, size: size);
}
