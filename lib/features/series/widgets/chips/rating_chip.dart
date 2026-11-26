import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/series/widgets/mini_badge.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

class RatingChip extends StatelessWidget {
  final List<dynamic> sources;
  final LibraryEntry? entry;
  final VoidCallback? onTap;

  const RatingChip({required this.sources, this.entry, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Treat 0 as unrated
    final userRatingValue = entry?.rating ?? 0;
    final int? userRating = userRatingValue > 0 ? userRatingValue : null;

    // The badge is only present when the user has personally rated the series
    if (userRating == null) return const SizedBox.shrink();

    final background = Color.alphaBlend(
      AppConstants.starColor.withValues(alpha: 0.12),
      colors.surfaceRaised,
    );
    return MiniBadge(
      text: '$userRating / 100',
      iconWidget: RatingStar(surface: background, icon: Icons.star),
      backgroundColor: background,
      hoverColor: AppConstants.starColor.withValues(alpha: 0.15),
      onTap: onTap,
      tooltip: onTap != null
          ? LocalizationService().translate('show_rating')
          : null,
    );
  }
}
