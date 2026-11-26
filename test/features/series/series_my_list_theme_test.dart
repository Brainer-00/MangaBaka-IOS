import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_dropdown.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_dropdown.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/widgets/mb_card.dart';
import 'package:mangabaka_app/features/series/widgets/series_my_list_card.dart';
import 'package:mangabaka_app/features/series/widgets/state_selection_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LocalizationService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().init();
  });

  final palettes = <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  };

  for (final paletteEntry in palettes.entries) {
    testWidgets(
      '${paletteEntry.key} status colors remain distinct and readable',
      (tester) async {
        final colors = paletteEntry.value;
        for (final status in AppConstants.libraryStates) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(showTooltips: true, palette: colors),
              home: Scaffold(
                body: StateSelectionSection(
                  currentState: status,
                  onStateChanged: (_) {},
                ),
              ),
            ),
          );
          final dropdown = find.byType(LibraryStatusDropdown);
          final button = tester.widget<OutlinedButton>(
            find.descendant(
              of: dropdown,
              matching: find.byType(OutlinedButton),
            ),
          );
          final style = button.style!;
          final statusColor = AppConstants.getColorForState(status);
          expect(style.backgroundColor!.resolve({}), statusColor);
          expect(
            MbPalette.contrastRatio(
              style.foregroundColor!.resolve({})!,
              statusColor,
            ),
            greaterThanOrEqualTo(4.5),
          );
          final side = style.side!.resolve({})!;
          if (status == 'paused') {
            expect(statusColor, const Color(0xFFFBD24B));
            expect(side, BorderSide.none);
          } else {
            expect(
              MbPalette.contrastRatio(side.color, colors.surface),
              greaterThanOrEqualTo(3),
            );
          }
          final icon = find
              .descendant(of: dropdown, matching: find.byType(Icon))
              .first;
          expect(
            MbPalette.contrastRatio(
              IconTheme.of(tester.element(icon)).color!,
              statusColor,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('${paletteEntry.key} My List values, tracks and actions', (
      tester,
    ) async {
      final colors = paletteEntry.value;
      final series = Series.fromJson({
        'id': 'series-1',
        'title': 'A Series',
        'total_chapters': '10',
        'final_volume': '4',
      });
      final entry = LibraryEntry(
        id: 'series-1',
        state: 'completed',
        progressChapter: 2,
        progressVolume: 1,
        rating: 80,
        series: series,
      );
      var chapters = 0, volumes = 0, ratings = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeriesMyListCard(
                series: series,
                entry: entry,
                l10n: LocalizationService(),
                onStateChanged: (_) {},
                onUpdateChapter: () => chapters++,
                onUpdateVolume: () => volumes++,
                onUpdateRating: () => ratings++,
              ),
            ),
          ),
        ),
      );
      final card = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(MbCard),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((card.decoration as BoxDecoration).color, colors.surface);
      for (final label in ['LIBRARY', 'CHAPTERS', 'VOLUMES', '80']) {
        final text = tester.widget<Text>(find.text(label));
        expect(
          MbPalette.contrastRatio(text.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text(' / 100', findRichText: true), findsNothing);
      final fills = tester
          .widgetList<FractionallySizedBox>(
            find.descendant(
              of: find.byType(SeriesMyListCard),
              matching: find.byType(FractionallySizedBox),
            ),
          )
          .map((widget) => widget.widthFactor)
          .toList();
      expect(fills, [0.2, 0.25]);
      final tracks = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SeriesMyListCard),
              matching: find.byType(Container),
            ),
          )
          .where(
            (widget) =>
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).color ==
                    colors.surfaceRaised,
          );
      expect(tracks.length, 2);
      final progressGradients = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SeriesMyListCard),
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>()
          .toList();
      expect(progressGradients, hasLength(2));
      for (final gradient in progressGradients) {
        for (final color in gradient.colors) {
          expect(
            MbPalette.contrastRatio(color, colors.surfaceRaised),
            greaterThanOrEqualTo(3),
          );
        }
      }
      await tester.tap(find.text('CHAPTERS'));
      await tester.tap(find.text('VOLUMES'));
      await tester.tap(find.text('80'));
      expect([chapters, volumes, ratings], [1, 1, 1]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Paused uses clean yellow status controls and progress in Light mode',
    (tester) async {
      final palette = EirenYuPalette.light;
      final series = Series.fromJson({
        'id': 'paused-series',
        'title': 'Paused series',
        'total_chapters': '10',
        'final_volume': '4',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: SeriesMyListCard(
              series: series,
              entry: LibraryEntry(
                id: 'paused-entry',
                state: 'paused',
                series: series,
                progressChapter: 2,
                progressVolume: 1,
              ),
              l10n: LocalizationService(),
              onStateChanged: (_) {},
              onUpdateChapter: () {},
              onUpdateVolume: () {},
              onUpdateRating: () {},
            ),
          ),
        ),
      );
      final indicators = find.byType(FractionallySizedBox);
      expect(indicators, findsNWidgets(2));
      for (final indicator in indicators.evaluate()) {
        final element = find.byWidget(indicator.widget);
        final fill =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: element,
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        BoxDecoration? track;
        indicator.visitAncestorElements((parent) {
          final widget = parent.widget;
          if (widget is! Container || widget.decoration is! BoxDecoration) {
            return true;
          }
          track = widget.decoration! as BoxDecoration;
          return false;
        });
        expect(fill.color, const Color(0xFFFBD24B));
        expect(track!.color, palette.surfaceRaised);
        expect(track!.border, isNull);
        expect(
          (indicator.widget as FractionallySizedBox).widthFactor,
          isIn([0.2, 0.25]),
        );
      }
      final dropdown = find.byType(LibraryStatusDropdown);
      final style = tester
          .widget<OutlinedButton>(
            find.descendant(
              of: dropdown,
              matching: find.byType(OutlinedButton),
            ),
          )
          .style!;
      expect(style.backgroundColor!.resolve({}), const Color(0xFFFBD24B));
      expect(
        style.foregroundColor!.resolve({}),
        AppConstants.primaryBackground,
      );
      expect(style.side!.resolve({}), BorderSide.none);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      final glyph = find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.byIcon(Icons.pause_circle_outline),
      );
      expect(tester.widget<Icon>(glyph).color, const Color(0xFFFBD24B));
      expect(tester.getSize(glyph), const Size.square(17));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('open status menu recolors on theme change and selects once', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    final selected = <String>[];
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: StateSelectionSection(
              currentState: 'reading',
              onStateChanged: selected.add,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(LibraryStatusDropdown));
    await tester.pumpAndSettle();
    final menuRows = find.byType(MenuItemButton);
    expect(menuRows, findsNWidgets(7));
    expect(selected, isEmpty);
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    expect(
      anchor.style!.backgroundColor!.resolve({}),
      EirenYuPalette.light.surface,
    );
    final selectedLabel = find.descendant(
      of: menuRows,
      matching: find.text('READING'),
    );
    final selectedRow = tester.widget<MenuItemButton>(
      find.ancestor(of: selectedLabel, matching: menuRows),
    );
    final tintedSurface = Color.alphaBlend(
      AppConstants.getColorForState('reading').withValues(alpha: 0.14),
      EirenYuPalette.light.surface,
    );
    expect(selectedRow.style!.backgroundColor!.resolve({}), tintedSurface);
    expect(
      MbPalette.contrastRatio(
        tester.widget<Text>(selectedLabel).style!.color!,
        tintedSurface,
      ),
      greaterThanOrEqualTo(4.5),
    );
    final check = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(
      MbPalette.contrastRatio(check.color!, tintedSurface),
      greaterThanOrEqualTo(4.5),
    );
    await tester.tap(find.text('COMPLETED'));
    await tester.pumpAndSettle();
    expect(selected, ['completed']);
    expect(menuRows, findsNothing);
    expect(
      tester
          .widget<LibraryStatusDropdown>(find.byType(LibraryStatusDropdown))
          .value,
      'completed',
    );
  });

  testWidgets('shared dropdown keeps custom caller colors and callbacks', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: Scaffold(
          body: DesktopDropdown<int>(
            valueLabel: 'One',
            selected: 1,
            backgroundColor: const Color(0xFF402030),
            foregroundColor: Colors.white,
            menuBackgroundColor: const Color(0xFFF7F4F8),
            items: const [
              DesktopDropdownItem(value: 1, label: 'One'),
              DesktopDropdownItem(value: 2, label: 'Two'),
            ],
            onSelected: (_) => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DesktopDropdown<int>));
    await tester.pumpAndSettle();
    expect(
      (tester
                  .widget<Container>(
                    find.byKey(const Key('desktop_dropdown_menu')),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      const Color(0xFFF7F4F8),
    );
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('status menu opens upward in short landscape without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.reset());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 250),
            child: StateSelectionSection(
              currentState: 'paused',
              onStateChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(LibraryStatusDropdown));
    await tester.pumpAndSettle();
    final rows = find.byType(MenuItemButton).hitTestable();
    expect(rows, findsWidgets);
    expect(tester.getCenter(rows.first).dy, lessThan(250));
    expect(tester.getCenter(rows.last).dy, lessThan(250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('My List fits a narrow portrait viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.reset());
    final series = Series.fromJson({
      'id': 'series-1',
      'title': 'A Series',
      'total_chapters': '10',
      'final_volume': '4',
    });
    final entry = LibraryEntry(
      id: 'series-1',
      state: 'reading',
      progressChapter: 2,
      progressVolume: 1,
      rating: 80,
      series: series,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeriesMyListCard(
              series: series,
              entry: entry,
              l10n: LocalizationService(),
              onStateChanged: (_) {},
              onUpdateChapter: () {},
              onUpdateVolume: () {},
              onUpdateRating: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(LibraryStatusDropdown));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(7));
    expect(find.text('ALL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'personal rating distinguishes a localized unset score from zero',
    (tester) async {
      final l10n = LocalizationService();
      await tester.runAsync(() => l10n.setLanguage('fr'));
      final series = Series.fromJson({'id': 's', 'title': 'Series'});
      for (final rating in [null, 0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SeriesMyListCard(
                series: series,
                entry: LibraryEntry(
                  id: 's',
                  state: 'reading',
                  series: series,
                  rating: rating,
                ),
                l10n: l10n,
                onStateChanged: (_) {},
                onUpdateChapter: () {},
                onUpdateVolume: () {},
                onUpdateRating: () {},
              ),
            ),
          ),
        );
        expect(
          find.byIcon(rating == null ? Icons.star_border : Icons.star),
          findsOneWidget,
        );
        expect(
          find.text(rating == null ? 'Aucune note pour le moment' : '0'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.add), findsNothing);
        expect(find.byType(FractionallySizedBox), findsNothing);
      }
    },
  );
}
