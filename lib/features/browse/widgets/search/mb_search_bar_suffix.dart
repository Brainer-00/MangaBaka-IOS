import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';

class MBSearchBarSuffix extends StatelessWidget {
  final String controllerText;
  final VoidCallback onClear;
  final VoidCallback? onScanTap;

  /// Null hides the filter button.
  final VoidCallback? onFilterTap;
  final SearchFilters currentFilters;

  const MBSearchBarSuffix({
    super.key,
    required this.controllerText,
    required this.onClear,
    this.onScanTap,
    this.onFilterTap,
    required this.currentFilters,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = MbPalette.ensureContrast(
      colors.text,
      colors.surfaceRaised,
      minimum: 3.0,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (controllerText.isNotEmpty) ...[
            WidgetUtils.tooltip(
              message: LocalizationService().translate('reset'),
              child: IconButton(
                icon: Icon(Icons.clear, color: iconColor),
                onPressed: onClear,
                constraints: const BoxConstraints(),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (onScanTap != null) ...[
            WidgetUtils.tooltip(
              message: LocalizationService().translate('scan_isbn_barcode'),
              child: IconButton(
                icon: Icon(Icons.qr_code_scanner, color: iconColor),
                onPressed: onScanTap,
                constraints: const BoxConstraints(),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (onFilterTap != null)
            WidgetUtils.tooltip(
              message: LocalizationService().translate('filters'),
              child: IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: currentFilters.toMap().isNotEmpty
                      ? colors.accentOn(colors.surfaceRaised, minimum: 3.0)
                      : iconColor,
                ),
                onPressed: onFilterTap,
                constraints: const BoxConstraints(),
              ),
            ),
        ],
      ),
    );
  }
}
