import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';

class SeriesDetailErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const SeriesDetailErrorBanner({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = Color.alphaBlend(
      colors.error.withValues(alpha: 0.14),
      colors.surfaceRaised,
    );
    final errorForeground = MbPalette.ensureContrast(
      colors.error,
      tint,
      minimum: 4.5,
    );
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: MbPalette.ensureContrast(
                    colors.error,
                    tint,
                    minimum: 3.0,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: errorForeground,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      LocalizationService().translate('failed_to_load'),
                      style: AppTypography.sans(
                        color: errorForeground,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(
                      LocalizationService().translate('retry'),
                      style: AppTypography.sans(
                        color: errorForeground,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
