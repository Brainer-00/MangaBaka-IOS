import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

/// The app emblem. The symbol and fixed white dot share a transparent canvas.
class EirenYuMark extends StatelessWidget {
  const EirenYuMark({super.key, required this.size, this.color});

  static const symbolImage = AssetImage(
    'assets/branding/eirenyu/runtime/symbol_512.png',
  );
  static const dotImage = AssetImage(
    'assets/branding/eirenyu/runtime/dot_512.png',
  );

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppConstants.appName,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: EirenYuPalette.obsidian,
            borderRadius: BorderRadius.circular(size * 0.2),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(
                image: symbolImage,
                color: color ?? context.logoColor,
                colorBlendMode: BlendMode.srcIn,
              ),
              const Image(image: dotImage),
            ],
          ),
        ),
      ),
    );
  }
}
