import 'package:flutter/material.dart';

/// Semantic UI colors. Fixed photographic overlays stay local to widgets.
@immutable
class MbPalette {
  const MbPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.text,
    required this.textMuted,
    required this.star,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Brightness brightness;
  final Color background, surface, surfaceRaised, border;
  final Color accent, onAccent, text, textMuted;
  final Color star, success, warning, error, info;

  MbPalette withAccent(Color color) {
    final adjusted = ensureContrast(color, surface, minimum: 3.0);
    return MbPalette(
      brightness: brightness,
      background: background,
      surface: surface,
      surfaceRaised: surfaceRaised,
      border: border,
      accent: adjusted,
      onAccent: readableOn(adjusted),
      text: text,
      textMuted: textMuted,
      star: star,
      success: success,
      warning: warning,
      error: error,
      info: info,
    );
  }

  /// WCAG relative luminance for an opaque sRGB color.
  static double luminance(Color color) => color.computeLuminance();

  static double contrastRatio(Color a, Color b) {
    final aLuminance = luminance(a);
    final bLuminance = luminance(b);
    final light = aLuminance > bLuminance ? aLuminance : bLuminance;
    final dark = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (light + 0.05) / (dark + 0.05);
  }

  /// Chooses black or white based on the higher WCAG contrast ratio.
  static Color readableOn(Color color) {
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    return contrastRatio(black, color) >= contrastRatio(white, color)
        ? black
        : white;
  }

  /// Nudges an accent toward black or white only when it is too close to the
  /// palette surface to read as a control or text foreground.
  static Color ensureContrast(
    Color color,
    Color background, {
    double minimum = 3.0,
  }) {
    if (contrastRatio(color, background) >= minimum) return color;
    final target = readableOn(background);
    var low = 0.0;
    var high = 1.0;
    for (var i = 0; i < 16; i++) {
      final midpoint = (low + high) / 2;
      final candidate = Color.lerp(color, target, midpoint)!;
      if (contrastRatio(candidate, background) >= minimum) {
        high = midpoint;
      } else {
        low = midpoint;
      }
    }
    return Color.lerp(color, target, high)!;
  }

  static MbPalette lerp(MbPalette a, MbPalette b, double t) {
    Color color(Color first, Color second) => Color.lerp(first, second, t)!;
    return MbPalette(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      background: color(a.background, b.background),
      surface: color(a.surface, b.surface),
      surfaceRaised: color(a.surfaceRaised, b.surfaceRaised),
      border: color(a.border, b.border),
      accent: color(a.accent, b.accent),
      onAccent: color(a.onAccent, b.onAccent),
      text: color(a.text, b.text),
      textMuted: color(a.textMuted, b.textMuted),
      star: color(a.star, b.star),
      success: color(a.success, b.success),
      warning: color(a.warning, b.warning),
      error: color(a.error, b.error),
      info: color(a.info, b.info),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MbPalette &&
      other.brightness == brightness &&
      other.background == background &&
      other.surface == surface &&
      other.surfaceRaised == surfaceRaised &&
      other.border == border &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.text == text &&
      other.textMuted == textMuted &&
      other.star == star &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      other.info == info;

  @override
  int get hashCode => Object.hash(
    brightness,
    background,
    surface,
    surfaceRaised,
    border,
    accent,
    onAccent,
    text,
    textMuted,
    star,
    success,
    warning,
    error,
    info,
  );
}

class EirenYuPalette {
  const EirenYuPalette._();
  static const obsidian = Color(0xFF0B0B10);
  static const midnight = Color(0xFF14182D);
  static const moonlight = Color(0xFFEDEFF7);
  static const crimsonMoon = Color(0xFFA82F4F);
  static const twilightLavender = Color(0xFF8B7CF6);
  static const horizonBlue = Color(0xFF4CC9FF);

  static const dark = MbPalette(
    brightness: Brightness.dark,
    background: obsidian,
    surface: midnight,
    surfaceRaised: Color(0xFF202540),
    border: Color(0xFF343952),
    accent: crimsonMoon,
    onAccent: Color(0xFFFFFFFF),
    text: moonlight,
    textMuted: Color(0xFFAFB3C5),
    star: Color(0xFFFFD36B),
    success: Color(0xFF69D69B),
    warning: Color(0xFFFFC875),
    error: Color(0xFFFF8293),
    info: Color(0xFF79CCF5),
  );

  static const light = MbPalette(
    brightness: Brightness.light,
    background: Color(0xFFF6F5F9),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEDEBF3),
    border: Color(0xFFD4D0DE),
    accent: Color(0xFF982B49),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF181725),
    textMuted: Color(0xFF575467),
    star: Color(0xFF916500),
    success: Color(0xFF177648),
    warning: Color(0xFF925A00),
    error: Color(0xFFB62440),
    info: Color(0xFF17639A),
  );
}
