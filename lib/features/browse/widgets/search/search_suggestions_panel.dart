import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';
import 'package:mangabaka_app/core/widgets/design/mb_cover.dart';

class SearchSuggestionsPanel extends StatelessWidget {
  final List<AutocompleteSeriesResult> results;
  final ValueChanged<AutocompleteSeriesResult> onResultTapped;
  final bool showSuggestions;
  final int selectedIndex;
  final ValueChanged<AutocompleteSeriesResult>? onResultHovered;

  const SearchSuggestionsPanel({
    super.key,
    required this.results,
    required this.onResultTapped,
    required this.showSuggestions,
    this.selectedIndex = -1,
    this.onResultHovered,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: showSuggestions
          ? _buildSuggestionsList(context)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSuggestionsList(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppConstants.largeRadius),
        boxShadow: AppConstants.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(results.length, (index) {
          final result = results[index];
          return _buildResultTile(
            context,
            result,
            index == selectedIndex,
            isFirst: index == 0,
            isLast: index == results.length - 1,
          );
        }),
      ),
    );
  }

  Widget _buildResultTile(
    BuildContext context,
    AutocompleteSeriesResult result,
    bool isSelected, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    final borderRadius = BorderRadius.vertical(
      top: isFirst
          ? const Radius.circular(AppConstants.largeRadius)
          : Radius.zero,
      bottom: isLast
          ? const Radius.circular(AppConstants.largeRadius)
          : Radius.zero,
    );

    return Material(
      color: isSelected
          ? context.colors.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: () => onResultTapped(result),
        onHover: (hovering) {
          if (hovering) onResultHovered?.call(result);
        },
        splashColor: context.colors.accent.withValues(alpha: 0.08),
        borderRadius: borderRadius,
        child: Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            top: isFirst ? 14 : 9,
            bottom: isLast ? 14 : 9,
          ),
          child: Row(
            children: [
              // Thumbnail
              MbCover(
                url: result.thumbnailUrl,
                width: 36,
                height: 52,
                radius: 6,
                memCacheWidth: 80,
                contentRating: result.contentRating,
              ),
              const SizedBox(width: 12),
              // Title + metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.title,
                      style: AppTypography.sans(
                        color: context.colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (result.type.isNotEmpty) ...[
                          _buildTypeBadge(context, result.type),
                          const SizedBox(width: 6),
                        ],
                        if (result.year != null)
                          Text(
                            '${result.year}',
                            style: AppTypography.sans(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (result.genres.isNotEmpty &&
                            (result.type.isNotEmpty || result.year != null))
                          Text(
                            '  ·  ${result.genres.take(2).map((g) => g.isNotEmpty ? g[0].toUpperCase() + g.substring(1) : g).join(', ')}',
                            style: AppTypography.sans(
                              color: context.colors.textMuted,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.north_west_rounded,
                size: 15,
                color: context.colors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(BuildContext context, String type) {
    final colors = {
      'manga': const Color(0xFF4A90D9),
      'manhwa': const Color(0xFF7B68EE),
      'manhua': const Color(0xFFE8A838),
      'novel': const Color(0xFF50C878),
      'oel': const Color(0xFFFF6B6B),
    };
    final color = colors[type.toLowerCase()] ?? context.colors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: AppTypography.sans(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
