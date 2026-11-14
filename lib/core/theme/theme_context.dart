import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';

@immutable
class MbColors extends ThemeExtension<MbColors> {
  const MbColors(this.palette);
  final MbPalette palette;

  @override
  MbColors copyWith({MbPalette? palette}) => MbColors(palette ?? this.palette);

  @override
  MbColors lerp(ThemeExtension<MbColors>? other, double t) => other is MbColors
      ? MbColors(MbPalette.lerp(palette, other.palette, t))
      : this;
}

extension ThemeColorsContext on BuildContext {
  MbPalette get colors =>
      Theme.of(this).extension<MbColors>()?.palette ?? EirenYuPalette.dark;
}
