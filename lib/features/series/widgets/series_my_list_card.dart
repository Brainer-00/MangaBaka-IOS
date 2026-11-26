import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/widgets/mb_card.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';
import 'package:mangabaka_app/features/series/widgets/state_selection_section.dart';

/// The reader’s personal Library tracking and editing controls.
class SeriesMyListCard extends StatelessWidget {
  final Series series;
  final LibraryEntry entry;
  final LocalizationService l10n;
  final Function(String) onStateChanged;
  final VoidCallback onUpdateChapter;
  final VoidCallback onUpdateVolume;
  final VoidCallback onUpdateRating;
  final VoidCallback? onEdit;

  const SeriesMyListCard({
    super.key,
    required this.series,
    required this.entry,
    required this.l10n,
    required this.onStateChanged,
    required this.onUpdateChapter,
    required this.onUpdateVolume,
    required this.onUpdateRating,
    this.onEdit,
  });

  int? _parseTotal(String raw) {
    if (raw.isEmpty || raw == 'null') return null;
    return int.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chapterTotal = _parseTotal(series.totalChapters);
    final volumeTotal = _parseTotal(series.finalVolume);
    final hasChapters =
        series.totalChapters.isNotEmpty && series.totalChapters != 'null';
    final hasVolumes =
        series.finalVolume.isNotEmpty && series.finalVolume != 'null';

    final statusColor = AppConstants.getColorForState(entry.state);
    final rating = entry.rating;

    return MbCard(
      label: l10n.translate('library'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      trailing: onEdit == null
          ? null
          : IconButton(
              tooltip: l10n.translate('library_editor_edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StateSelectionSection(
            currentState: entry.state,
            onStateChanged: onStateChanged,
          ),
          if (hasChapters)
            _ProgressRow(
              label: l10n.translate('chapters'),
              value: entry.progressChapter ?? 0,
              total: chapterTotal,
              onTap: onUpdateChapter,
              statusColor: statusColor,
            ),
          if (hasVolumes)
            _ProgressRow(
              label: l10n.translate('volumes'),
              value: entry.progressVolume ?? 0,
              total: volumeTotal,
              onTap: onUpdateVolume,
              statusColor: statusColor,
            ),
          const SizedBox(height: 2),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Tooltip(
              message: l10n.translate('rating'),
              child: InkWell(
                onTap: onUpdateRating,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      RatingStar(
                        icon: rating == null ? Icons.star_border : Icons.star,
                        surface: colors.surface,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rating?.toString() ?? l10n.translate('no_rating_yet'),
                          style: AppTypography.sans(
                            color: colors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.edit, size: 16, color: colors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final int value;
  final int? total;
  final VoidCallback onTap;
  final Color statusColor;

  const _ProgressRow({
    required this.label,
    required this.value,
    required this.total,
    required this.onTap,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final paused = statusColor == AppConstants.pausedColor;
    final statusText = MbPalette.ensureContrast(
      paused && MbPalette.contrastRatio(statusColor, colors.surface) < 4.5
          ? colors.text
          : statusColor,
      colors.surface,
      minimum: 4.5,
    );
    final statusIndicator = paused
        ? statusColor
        : MbPalette.ensureContrast(
            statusColor,
            colors.surfaceRaised,
            minimum: 3.0,
          );
    final track =
        paused && MbPalette.contrastRatio(statusColor, colors.surfaceRaised) < 3
        ? MbPalette.ensureContrast(
            colors.surfaceRaised,
            statusColor,
            minimum: 3,
          )
        : colors.surfaceRaised;
    final pct = (total != null && total! > 0)
        ? (value / total!).clamp(0.0, 1.0)
        : 0.0;
    final totalLabel = total != null ? '$total' : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: AppTypography.monoLabel(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$value',
                        style: AppTypography.sans(
                          color: statusText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: ' / $totalLabel',
                        style: AppTypography.sans(
                          color: colors.text,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.add, size: 16, color: colors.textMuted),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: paused ? statusIndicator : null,
                      gradient: paused
                          ? null
                          : LinearGradient(
                              colors: [
                                statusIndicator,
                                Color.lerp(statusIndicator, colors.text, 0.28)!,
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
