import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/widgets/design/mb_rating_stars.dart';
import 'package:mangabaka_app/features/browse/models/browse_type.dart';
import 'package:mangabaka_app/features/browse/widgets/browse_type_tabs.dart';
import 'package:mangabaka_app/features/browse/widgets/results/browse_content.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_bar_shell.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_suggestions_panel.dart';
import 'package:mangabaka_app/features/browse/widgets/shortcuts/shortcut_button.dart';
import 'package:mangabaka_app/features/home/widgets/home_rail.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';

void main() {
  testWidgets(
    'Home and Browse controls recolor while keeping input and selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      final selected = ValueNotifier<BrowseType>(BrowseType.series);
      addTearDown(selected.dispose);
      const result = AutocompleteSeriesResult(
        id: 1,
        title: 'Test Manga',
        thumbnailUrl: '',
        year: 2024,
      );

      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    ValueListenableBuilder<BrowseType>(
                      valueListenable: selected,
                      builder: (_, type, _) => BrowseTypeTabs(
                        selectedType: type,
                        onTypeChanged: (value) => selected.value = value,
                      ),
                    ),
                    SearchBarShell(
                      onChanged: (_) {},
                      requestSuggestions: (_, callback) => callback([]),
                      showFilterButton: false,
                    ),
                    SearchSuggestionsPanel(
                      results: const [result],
                      onResultTapped: (_) {},
                      showSuggestions: true,
                    ),
                    const MbRatingStars(rating: 8),
                    const HomeRail(title: 'Loading', series: [], loading: true),
                    ShortcutButton(label: 'Discover', onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField), 'Manga');
      await tester.tap(find.text('publishers'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(selected.value, BrowseType.publishers);

      for (final colors in [
        EirenYuPalette.dark,
        EirenYuPalette.light,
        ThemePresets.byId('nord')!.dark!,
      ]) {
        palette.value = colors;
        await tester.pump(const Duration(milliseconds: 250));
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'Manga');
        expect(field.style!.color, colors.text);
        expect(
          field.decoration!.hintStyle!.color,
          MbPalette.ensureContrast(
            colors.textMuted,
            colors.surfaceRaised,
            minimum: 4.5,
          ),
        );
        expect(field.decoration!.fillColor, colors.surfaceRaised);
        expect(
          (field.decoration!.focusedBorder! as OutlineInputBorder)
              .borderSide
              .color,
          colors.accentForeground,
        );
        expect(
          MbPalette.contrastRatio(field.style!.color!, colors.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          MbPalette.contrastRatio(
            field.decoration!.hintStyle!.color!,
            colors.surfaceRaised,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          tester.widget<Text>(find.text('Test Manga')).style!.color,
          colors.text,
        );
        expect(
          tester.widget<Icon>(find.byIcon(Icons.star_rounded)).color,
          AppConstants.starColor,
        );
        expect(
          tester.widget<Text>(find.text('DISCOVER')).style!.color,
          colors.text,
        );
        expect(selected.value, BrowseType.publishers);
        final selectedLabel = tester
            .widgetList<AnimatedDefaultTextStyle>(
              find.descendant(
                of: find.byType(BrowseTypeTabs),
                matching: find.byType(AnimatedDefaultTextStyle),
              ),
            )
            .elementAt(1);
        expect(
          MbPalette.contrastRatio(selectedLabel.style.color!, colors.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(700, 320);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Manga',
      );
    },
  );

  testWidgets('Browse empty, loading, and error states follow the palette', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    for (final colors in [EirenYuPalette.dark, EirenYuPalette.light]) {
      for (final state in ['empty', 'loading', 'error']) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            home: Scaffold(
              body: Column(
                children: [
                  BrowseContent(
                    searchResults: const [],
                    browseType: BrowseType.staff,
                    isLoading: state == 'loading',
                    isLoadingMore: false,
                    error: state == 'error' ? 'Search failed' : null,
                    scrollController: scrollController,
                    onRetry: () {},
                    onNavigateToDetail: (_) {},
                    onNavigateToResults: (_, _, {type, staff, publisher}) {},
                    onNavigateToMix: () {},
                    onNavigateToDiscoveryQueue: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        if (state == 'empty') {
          expect(find.byKey(const ValueKey('search_prompt')), findsOneWidget);
          expect(
            tester.widget<Icon>(find.byIcon(Icons.people)).color,
            colors.textMuted,
          );
        } else if (state == 'loading') {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        } else {
          final errorText = tester.widget<Text>(find.text('Search failed'));
          expect(
            MbPalette.contrastRatio(errorText.style!.color!, colors.background),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });
}
