import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_surfaces.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/browse/models/sort_options.dart';

/// Which list a [DesktopListStyleToggle] controls.
enum DesktopListScope { library, browse }

/// Every list style as a row of icons, written to whichever setting the list
/// reads from — the phone hides this in settings or cycles it one step per
/// tap, which is a poor fit when all five fit in the toolbar.
class DesktopListStyleToggle extends StatelessWidget {
  final DesktopListScope scope;

  const DesktopListStyleToggle({super.key, required this.scope});

  static const Map<AppListStyle, String> _labelKeys = {
    AppListStyle.comfortable: 'list_style_comfortable',
    AppListStyle.compact: 'list_style_compact',
    AppListStyle.minimalList: 'list_style_minimal_list',
    AppListStyle.coverOnlyGrid: 'list_style_cover_only_grid',
    AppListStyle.compactGrid: 'list_style_compact_grid',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsManager(),
      builder: (context, _) {
        final settings = SettingsManager();
        final l10n = LocalizationService();
        final current = scope == DesktopListScope.library
            ? settings.resolvedLibraryListStyle
            : settings.resolvedBrowseListStyle;

        return DesktopSegmented<AppListStyle>(
          value: current,
          segments: [
            for (final style in AppListStyle.values) (style, null, style.icon),
          ],
          tooltipFor: (style) => l10n.translate(_labelKeys[style]!),
          onChanged: (style) {
            if (!settings.separateListStyles) {
              settings.setListStyle(style);
            } else if (scope == DesktopListScope.library) {
              settings.setLibraryListStyle(style);
            } else {
              settings.setBrowseListStyle(style);
            }
          },
        );
      },
    );
  }
}

/// The sort dropdown for a filtered list.
class DesktopSortMenu extends StatelessWidget {
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;
  final bool library;

  const DesktopSortMenu({
    super.key,
    required this.filters,
    required this.onChanged,
    this.library = false,
  });

  /// Sentinel for "no explicit sort" — PopupMenuButton cannot select null.
  static const String _defaultKey = '';

  @override
  Widget build(BuildContext context) {
    final l10n = LocalizationService();
    final options = searchSortOptions(l10n, library: library);
    final current = filters.sortBy ?? _defaultKey;

    return DesktopMenuButton<String>(
      label: l10n.translate('sort_by'),
      valueLabel: options[current] ?? l10n.translate('default'),
      icon: Icons.sort_rounded,
      selected: current,
      items: [
        (_defaultKey, l10n.translate('default')),
        for (final e in options.entries) (e.key, e.value),
      ],
      onSelected: (key) =>
          onChanged(filters.copyWithSortBy(key == _defaultKey ? null : key)),
    );
  }
}
