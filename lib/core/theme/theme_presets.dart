import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';

class ThemePreset {
  const ThemePreset(this.id, {this.dark, this.light});
  final String id;
  final MbPalette? dark, light;
}

/// Built-in choices retain upstream IDs and only their supported variants.
class ThemePresets {
  const ThemePresets._();
  static const defaultId = 'eirenyu';
  static const accentSwatches = <Color>[
    Color(0xFF5BBD74),
    Color(0xFFFBD24B),
    Color(0xFFFB923C),
    Color(0xFFF43F5E),
    Color(0xFFF472B6),
    Color(0xFFA78BFA),
    Color(0xFF60A5FA),
    Color(0xFF22D3EE),
    Color(0xFF2DD4BF),
    Color(0xFFA3E635),
    EirenYuPalette.crimsonMoon,
    EirenYuPalette.twilightLavender,
    EirenYuPalette.horizonBlue,
  ];
  static const originalGreen = MbPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0B0B),
    surface: Color(0xFF151515),
    surfaceRaised: Color(0xFF1F1F1F),
    border: Color(0xFF262626),
    accent: Color(0xFF5BBD74),
    onAccent: Color(0xFF0B140D),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF8E8E8E),
    star: Color(0xFFFBD24B),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBD24B),
    error: Color(0xFFF87171),
    info: Color(0xFF60A5FA),
  );

  static MbPalette _derive(
    Brightness brightness,
    int background,
    int accent, {
    int? surface,
    int? text,
    int? surfaceRaised,
    int? border,
    int? textMuted,
    int? star,
    int? success,
    int? warning,
    int? error,
    int? info,
  }) {
    final dark = brightness == Brightness.dark;
    final bg = Color(background);
    final fg = Color(text ?? (dark ? 0xFFF4F4F6 : 0xFF171722));
    final base = dark ? EirenYuPalette.dark : EirenYuPalette.light;
    return MbPalette(
      brightness: brightness,
      background: bg,
      surface: Color(surface ?? (dark ? 0xFF272732 : 0xFFFFFFFF)),
      surfaceRaised: surfaceRaised == null
          ? Color.lerp(bg, fg, dark ? 0.15 : 0.07)!
          : Color(surfaceRaised),
      border: border == null
          ? Color.lerp(bg, fg, dark ? 0.25 : 0.19)!
          : Color(border),
      accent: Color(accent),
      onAccent: MbPalette.readableOn(Color(accent)),
      text: fg,
      textMuted: textMuted == null
          ? Color.lerp(bg, fg, dark ? 0.70 : 0.66)!
          : Color(textMuted),
      star: star == null ? base.star : Color(star),
      success: success == null ? base.success : Color(success),
      warning: warning == null ? base.warning : Color(warning),
      error: error == null ? base.error : Color(error),
      info: info == null ? base.info : Color(info),
    );
  }

  static final List<ThemePreset> all = [
    const ThemePreset(
      defaultId,
      dark: EirenYuPalette.dark,
      light: EirenYuPalette.light,
    ),
    ThemePreset(
      'default',
      dark: originalGreen,
      light: _derive(Brightness.light, 0xFFF4F3EF, 0xFF16713A),
    ),
    ThemePreset(
      'amoled',
      dark: _derive(
        Brightness.dark,
        0xFF000000,
        0xFF5BBD74,
        surface: 0xFF0C0C0C,
        surfaceRaised: 0xFF171717,
        border: 0xFF222222,
        text: 0xFFFFFFFF,
        textMuted: 0xFF8E8E8E,
      ),
    ),
    ThemePreset(
      'monochrome',
      dark: _derive(Brightness.dark, 0xFF0A0A0A, 0xFFE5E5E5),
      light: _derive(Brightness.light, 0xFFF5F5F5, 0xFF171717),
    ),
    ThemePreset(
      'catppuccin',
      dark: _derive(
        Brightness.dark,
        0xFF1E1E2E,
        0xFFCBA6F7,
        surface: 0xFF262637,
        text: 0xFFCDD6F4,
        surfaceRaised: 0xFF313244,
        border: 0xFF45475A,
        textMuted: 0xFFA6ADC8,
        star: 0xFFF9E2AF,
        success: 0xFFA6E3A1,
        warning: 0xFFFAB387,
        error: 0xFFF38BA8,
        info: 0xFF89B4FA,
      ),
      light: _derive(
        Brightness.light,
        0xFFEFF1F5,
        0xFF8839EF,
        text: 0xFF4C4F69,
        surfaceRaised: 0xFFE6E9EF,
        border: 0xFFCCD0DA,
        textMuted: 0xFF6C6F85,
        star: 0xFFDF8E1D,
        success: 0xFF40A02B,
        warning: 0xFFFE640B,
        error: 0xFFD20F39,
        info: 0xFF1E66F5,
      ),
    ),
    ThemePreset(
      'dracula',
      dark: _derive(
        Brightness.dark,
        0xFF21222C,
        0xFFBD93F9,
        surface: 0xFF282A36,
        text: 0xFFF8F8F2,
        surfaceRaised: 0xFF343746,
        border: 0xFF44475A,
        textMuted: 0xFFA0A7C8,
        star: 0xFFF1FA8C,
        success: 0xFF50FA7B,
        warning: 0xFFFFB86C,
        error: 0xFFFF5555,
        info: 0xFF8BE9FD,
      ),
    ),
    ThemePreset(
      'nord',
      dark: _derive(
        Brightness.dark,
        0xFF2E3440,
        0xFF88C0D0,
        surface: 0xFF3B4252,
        text: 0xFFECEFF4,
        surfaceRaised: 0xFF434C5E,
        border: 0xFF4C566A,
        star: 0xFFEBCB8B,
        success: 0xFFA3BE8C,
        warning: 0xFFD08770,
        error: 0xFFBF616A,
        info: 0xFF81A1C1,
      ),
      light: _derive(
        Brightness.light,
        0xFFE5E9F0,
        0xFF5E81AC,
        surface: 0xFFF4F6F9,
        text: 0xFF2E3440,
        surfaceRaised: 0xFFD8DEE9,
        border: 0xFFC3CBD8,
        textMuted: 0xFF4C566A,
        error: 0xFFBF616A,
      ),
    ),
    ThemePreset(
      'midnight_dusk',
      dark: _derive(Brightness.dark, 0xFF0B0F19, 0xFFF43F5E),
      light: _derive(Brightness.light, 0xFFF3F4F6, 0xFFE11D48),
    ),
    ThemePreset(
      'strawberry',
      dark: _derive(Brightness.dark, 0xFF1A0B11, 0xFFFB7185),
      light: _derive(Brightness.light, 0xFFFFF1F2, 0xFFE11D48),
    ),
    ThemePreset(
      'tako',
      dark: _derive(Brightness.dark, 0xFF17131C, 0xFFF3B375),
      light: _derive(Brightness.light, 0xFFF7F4FB, 0xFF66577E),
    ),
    ThemePreset(
      'yotsuba',
      dark: _derive(Brightness.dark, 0xFF17110E, 0xFFFB923C),
      light: _derive(Brightness.light, 0xFFFFF7ED, 0xFFC2410C),
    ),
    ThemePreset(
      'green_apple',
      dark: _derive(Brightness.dark, 0xFF0B1220, 0xFF84CC16),
      light: _derive(Brightness.light, 0xFFF1F5F9, 0xFF4D7C0F),
    ),
    ThemePreset(
      'teal',
      dark: _derive(Brightness.dark, 0xFF071A1A, 0xFF2DD4BF),
      light: _derive(Brightness.light, 0xFFF0FDFA, 0xFF0F766E),
    ),
    ThemePreset(
      'tidal_wave',
      dark: _derive(Brightness.dark, 0xFF071826, 0xFF38BDF8),
      light: _derive(Brightness.light, 0xFFF0F9FF, 0xFF0369A1),
    ),
    ThemePreset(
      'lavender',
      dark: _derive(Brightness.dark, 0xFF130F1E, 0xFFA78BFA),
      light: _derive(Brightness.light, 0xFFF5F3FF, 0xFF6D28D9),
    ),
  ];

  static ThemePreset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
