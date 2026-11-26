import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';
import 'package:mangabaka_app/features/browse/models/browse_type.dart';
import 'package:mangabaka_app/features/browse/widgets/browse_type_tabs.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_bar_shell.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_suggestions_panel.dart';
import 'package:mangabaka_app/features/home/widgets/home_rail.dart';
import 'package:mangabaka_app/features/home/widgets/home_trending_section.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/settings_switch_item.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child, {double scale = 2, MbPalette? palette}) {
  return MaterialApp(
    theme: AppTheme.build(
      showTooltips: true,
      palette: palette ?? EirenYuPalette.light,
    ),
    themeAnimationDuration: Duration.zero,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().init();
  });

  testWidgets('Browse tabs fit German labels in compact split view', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);
    final l10n = LocalizationService();
    await tester.runAsync(() => l10n.setLanguage('de'));
    addTearDown(() => l10n.setLanguage('en'));
    BrowseType? tapped;
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topCenter,
          child: BrowseTypeTabs(
            selectedType: BrowseType.series,
            onTypeChanged: (type) => tapped = type,
          ),
        ),
      ),
    );
    final tabs = find.byType(BrowseTypeTabs);
    final tab = find.text(l10n.translate('publishers'));
    final target = find
        .ancestor(of: tab, matching: find.byType(GestureDetector))
        .first;
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    expect(tester.getRect(tabs).contains(tester.getCenter(tab)), isTrue);
    await tester.tap(tab);
    expect(tapped, BrowseType.publishers);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Search overlay follows the field above the keyboard and on resize',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      final results = List.generate(
        5,
        (index) => AutocompleteSeriesResult(
          id: index,
          title: 'Series result ${index + 1}',
          thumbnailUrl: '',
        ),
      );
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.topCenter,
            child: SearchBarShell(
              onChanged: (_) {},
              requestSuggestions: (_, callback) => callback(results),
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.enterText(field, 'Series');
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await tester.pumpAndSettle();

      final panel = find.byType(SearchSuggestionsPanel);
      expect(tester.getSize(panel).width, tester.getSize(field).width);
      expect(tester.getBottomLeft(panel).dy, lessThanOrEqualTo(218));
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(
        find
            .descendant(of: panel, matching: find.text(results.last.title))
            .hitTestable(),
        findsOneWidget,
      );

      tester.view.physicalSize = const Size(430, 932);
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, tester.getSize(field).width);
      expect(tester.getSize(panel).width, 430);
      expect(tester.getBottomLeft(panel).dy, lessThanOrEqualTo(582));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home rail keeps the two-line title and score inside its bounds',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.reset);
      const title = 'An unusually long title for a long-running series';
      await tester.pumpWidget(
        _app(
          HomeTrendingSection(
            series: [
              Series.fromJson({'id': '1', 'title': title, 'rating': 95}),
            ],
            loading: false,
            selectedType: null,
            window: 7,
            onTypeChanged: (_) {},
            onWindowChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rail = find.byType(HomeRail);
      final cardList = find.descendant(
        of: rail,
        matching: find.byType(ListView),
      );
      final star = find.descendant(of: rail, matching: find.byType(RatingStar));
      expect(
        tester.getTopLeft(star).dy,
        greaterThan(tester.getBottomLeft(find.text(title)).dy),
      );
      expect(
        tester.getBottomLeft(star).dy,
        lessThan(tester.getBottomLeft(cardList).dy),
      );
      expect(
        tester.getSize(find.byType(ListView).first).height,
        greaterThanOrEqualTo(44),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Browse suggestions wrap long metadata in a narrow window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    const result = AutocompleteSeriesResult(
      id: 1,
      title:
          'A very long series title that spans several lines at large text sizes',
      thumbnailUrl: '',
      type: 'manhwa',
      year: 2026,
      genres: ['action', 'historical fantasy and adventure'],
    );
    AutocompleteSeriesResult? chosen;
    await tester.pumpWidget(
      _app(
        SearchSuggestionsPanel(
          results: const [result],
          onResultTapped: (value) => chosen = value,
          showSuggestions: true,
        ),
      ),
    );
    final type = find.text('MANHWA');
    final genre = find.text('Action, Historical fantasy and adventure');
    expect(
      tester.getTopLeft(genre).dy,
      greaterThan(tester.getTopLeft(type).dy),
    );
    expect(tester.getTopRight(genre).dx, lessThanOrEqualTo(320));
    await tester.tap(find.text(result.title));
    expect(chosen, same(result));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings keeps a long label and switch aligned and tappable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    addTearDown(tester.view.reset);
    const label = 'Erscheinungsbild an Systemeinstellungen anpassen';
    bool? selection;
    await tester.pumpWidget(
      _app(
        SettingsSwitchItem(
          icon: Icons.palette_outlined,
          title: label,
          subtitle: 'Benutzerdefinierte Darstellung',
          value: false,
          onChanged: (value) => selection = value,
        ),
      ),
    );
    final control = find.byType(Switch);
    final titleRect = tester.getRect(find.text(label));
    final subtitleRect = tester.getRect(
      find.text('Benutzerdefinierte Darstellung'),
    );
    final center = tester.getCenter(control);
    expect(titleRect.right, lessThanOrEqualTo(tester.getTopLeft(control).dx));
    expect(center.dy, closeTo((titleRect.top + subtitleRect.bottom) / 2, 1));
    await tester.tap(control);
    expect(selection, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Every supported palette and custom accent keeps both star states yellow',
    (tester) async {
      const yellow = Color(0xFFFBD24B);
      const customAccent = Color(0xFF777777);
      final palettes = [
        for (final preset in ThemePresets.all) ...[?preset.dark, ?preset.light],
        EirenYuPalette.light.withAccent(customAccent),
      ];
      expect(ThemePresets.all, hasLength(15));
      final custom = palettes.last;
      expect(custom.accent, isNot(EirenYuPalette.light.accent));
      for (final palette in palettes) {
        expect(palette.star, yellow);
        await tester.pumpWidget(
          _app(
            palette: palette,
            Row(
              children: [
                RatingStar(icon: Icons.star_rounded),
                RatingStar(icon: Icons.star_outline_rounded),
              ],
            ),
          ),
        );
        for (final icon in [Icons.star_rounded, Icons.star_outline_rounded]) {
          final glyph = find.byIcon(icon);
          expect(tester.widget<Icon>(glyph).color, yellow);
          expect(tester.getSize(glyph), const Size.square(18));
          final star = find.ancestor(
            of: glyph,
            matching: find.byType(RatingStar),
          );
          expect(tester.getRect(star), tester.getRect(glyph));
        }
        for (final type in [DecoratedBox, Padding]) {
          expect(
            find.descendant(
              of: find.byType(RatingStar),
              matching: find.byType(type),
            ),
            findsNothing,
          );
        }
      }
    },
  );
}
