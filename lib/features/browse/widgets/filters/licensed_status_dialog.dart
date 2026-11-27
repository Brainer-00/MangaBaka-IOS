import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';

class LicensedStatusDialog {
  static void show({
    required BuildContext context,
    required LocalizationService l10n,
    required SearchFilters currentFilters,
    required ValueChanged<bool?> onStatusSelected,
    String titleKey = 'licensed_status',
    bool? Function(SearchFilters filters)? selected,
  }) {
    final current = (selected ?? (f) => f.isLicensed)(currentFilters);
    showModalBottomSheet(
      showDragHandle: true,
      context: context,
      isScrollControlled: true,
      builder: (BuildContext dialogContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: dialogContext.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 60),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate(titleKey).toUpperCase(),
                  style: AppTypography.display(
                    color: dialogContext.colors.text,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 24),
                _SelectionTile(
                  label: l10n.translate('any'),
                  isSelected: current == null,
                  onTap: () {
                    onStatusSelected(null);
                    Navigator.pop(dialogContext);
                  },
                ),
                _SelectionTile(
                  label: l10n.translate('yes'),
                  isSelected: current == true,
                  onTap: () {
                    onStatusSelected(true);
                    Navigator.pop(dialogContext);
                  },
                ),
                _SelectionTile(
                  label: l10n.translate('no'),
                  isSelected: current == false,
                  onTap: () {
                    onStatusSelected(false);
                    Navigator.pop(dialogContext);
                  },
                  isLast: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLast;

  const _SelectionTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(color: context.colors.border, width: 1),
                ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: AppTypography.sans(
                color: isSelected
                    ? context.colors.text
                    : context.colors.textMuted,
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const Spacer(),
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? context.colors.accentOn(
                      context.colors.surface,
                      minimum: 3.0,
                    )
                  : context.colors.textMuted,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
