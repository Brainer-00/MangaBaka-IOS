import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/widgets/search/ghost_text_editing_controller.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/browse/widgets/results/browse_results_status_widgets.dart';
import 'package:mangabaka_app/features/browse/widgets/search/mb_search_bar_suffix.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_bar_shell.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';

Widget _app(MbPalette palette, Widget child) => MaterialApp(
  theme: AppTheme.build(showTooltips: true, palette: palette),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(body: child),
);

void main() {
  final palettes = [
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    ThemePresets.byId('catppuccin')!.light!,
    EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  ];

  testWidgets('suffix icons follow the field surface and callbacks', (
    tester,
  ) async {
    var clears = 0;
    var scans = 0;
    var filters = 0;
    for (final palette in palettes) {
      await tester.pumpWidget(
        _app(
          palette,
          MBSearchBarSuffix(
            controllerText: 'query',
            onClear: () => clears++,
            onScanTap: () => scans++,
            onFilterTap: () => filters++,
            currentFilters: SearchFilters(),
          ),
        ),
      );
      for (final icon in [
        Icons.clear,
        Icons.qr_code_scanner,
        Icons.filter_list,
      ]) {
        final color = tester.widget<Icon>(find.byIcon(icon)).color!;
        expect(
          MbPalette.contrastRatio(color, palette.surfaceRaised),
          greaterThanOrEqualTo(3),
        );
      }
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byIcon(Icons.clear));
    await tester.tap(find.byIcon(Icons.qr_code_scanner));
    await tester.tap(find.byIcon(Icons.filter_list));
    expect((clears, scans, filters), (1, 1, 1));
  });

  testWidgets('ghost recolors live without another request or losing query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    final text = GhostTextEditingController();
    addTearDown(text.dispose);
    var requests = 0;
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => _app(
          colors,
          SearchBarShell(
            controller: text,
            onChanged: (_) {},
            showFilterButton: false,
            requestSuggestions: (_, callback) {
              requests++;
              callback(const [
                AutocompleteSeriesResult(
                  id: 1,
                  title: 'Manga',
                  thumbnailUrl: '',
                  allTitles: ['Manga'],
                ),
              ]);
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Man');
    await tester.pump();
    expect(text.ghostSuffix, 'ga');
    final before = requests;
    palette.value = EirenYuPalette.light;
    await tester.pump();
    expect(text.text, 'Man');
    expect(text.ghostSuffix, 'ga');
    expect(requests, before);
    expect(
      MbPalette.contrastRatio(
        text.ghostColor!,
        EirenYuPalette.light.surfaceRaised,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(text.text, isEmpty);
  });

  testWidgets('Browse empty and error states recolor and retry', (
    tester,
  ) async {
    var retries = 0;
    for (final palette in palettes) {
      await tester.pumpWidget(
        _app(
          palette,
          Column(
            children: [
              const Expanded(child: BrowseResultsEmpty()),
              Expanded(
                child: BrowseResultsError(
                  error: 'Failed',
                  onRetry: () => retries++,
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('Failed')).style!.color,
        MbPalette.ensureContrast(
          palette.error,
          palette.background,
          minimum: 4.5,
        ),
      );
      expect(
        MbPalette.contrastRatio(
          tester.widget<Icon>(find.byIcon(Icons.error_outline)).color!,
          palette.background,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byType(ElevatedButton));
    expect(retries, 1);
  });
}
