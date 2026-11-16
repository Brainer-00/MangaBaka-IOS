import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/features/publisher/models/publisher.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

class PublisherListItem extends StatelessWidget {
  final Publisher publisher;
  final VoidCallback onTap;

  /// Space around the card. The default suits a vertical list; a grid supplies
  /// its own spacing and passes [EdgeInsets.zero].
  final EdgeInsetsGeometry? margin;

  const PublisherListItem({
    super.key,
    required this.publisher,
    required this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = MbPalette.ensureContrast(
      colors.textMuted,
      colors.surface,
      minimum: 4.5,
    );
    final badgeFill = Color.alphaBlend(
      colors.accent.withValues(alpha: 0.1),
      colors.surface,
    );
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      publisher.name,
                      style: AppTypography.sans(
                        color: colors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Wraps rather than overflows: in a narrow grid cell the
                    // badge and its facts do not fit on one line.
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildBadge(
                          publisher.subType.toUpperCase(),
                          colors,
                          badgeFill,
                        ),
                        if (publisher.founded != null)
                          _buildInfoText('Est. ${publisher.founded}', muted),
                        if (publisher.closed != null)
                          _buildInfoText(
                            'Closed ${publisher.closed}',
                            MbPalette.ensureContrast(
                              colors.error,
                              colors.surface,
                              minimum: 4.5,
                            ),
                          ),
                        if (publisher.imprints.isNotEmpty)
                          _buildInfoText(
                            '${publisher.imprints.length} Imprints',
                            muted,
                          ),
                        if (publisher.links.isNotEmpty)
                          Icon(
                            Icons.link_rounded,
                            size: 14,
                            color: colors.accentOn(colors.surface, minimum: 3),
                          ),
                      ],
                    ),
                    if (publisher.description != null &&
                        publisher.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        publisher.description!,
                        style: AppTypography.sans(color: muted, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: MbPalette.ensureContrast(
                  colors.textMuted,
                  colors.surface,
                  minimum: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, MbPalette colors, Color fill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTypography.sans(
          color: colors.accentOn(fill),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildInfoText(String text, Color color) {
    return Text(
      text,
      style: AppTypography.sans(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
