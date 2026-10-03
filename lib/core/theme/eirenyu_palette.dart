import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';

/// EirenYu's shared dark foundation plus one of the three approved accent
/// themes. The foundation stays fixed; only the accent tokens change.
class EirenYuPalette {
  const EirenYuPalette({
    required this.accent,
    required this.accentSeed,
    required this.onAccent,
  });

  static const Color obsidian = Color(0xFF0B0B10);
  static const Color midnight = Color(0xFF14182D);
  static const Color moonlight = Color(0xFFEDEFF7);

  static const EirenYuPalette crimsonMoon = EirenYuPalette(
    accent: Color(0xFFA82F4F),
    accentSeed: Color(0xFFA82F4F),
    onAccent: Color(0xFFFFFFFF),
  );

  static const EirenYuPalette twilightLavender = EirenYuPalette(
    accent: Color(0xFF8B7CF6),
    accentSeed: Color(0xFF8B7CF6),
    onAccent: Color(0xFFFFFFFF),
  );

  static const EirenYuPalette horizonBlue = EirenYuPalette(
    accent: Color(0xFF4CC9FF),
    accentSeed: Color(0xFF4CC9FF),
    onAccent: Color(0xFF071018),
  );

  final Color accent;
  final Color accentSeed;
  final Color onAccent;

  static EirenYuPalette forTheme(EirenYuAccentTheme theme) => switch (theme) {
    EirenYuAccentTheme.crimsonMoon => crimsonMoon,
    EirenYuAccentTheme.twilightLavender => twilightLavender,
    EirenYuAccentTheme.horizonBlue => horizonBlue,
  };
}
