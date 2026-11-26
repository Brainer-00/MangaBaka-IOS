import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

class StatisticCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const StatisticCard({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mutedOnCard = MbPalette.ensureContrast(
      colors.textMuted,
      colors.surface,
      minimum: 4.5,
    );
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppConstants.largeRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The number leads, the label sits under it as a caps kicker — a
          // statistic is read value-first. The glyph is a quiet corner mark.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: AppTypography.display(
                    color: colors.text,
                    fontSize: 28,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: icon == Icons.star
                    ? RatingStar(icon: icon, size: 18)
                    : Icon(icon, color: mutedOnCard, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: AppTypography.monoLabel(color: mutedOnCard, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
