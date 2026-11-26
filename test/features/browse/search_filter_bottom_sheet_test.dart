import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/search_filter_bottom_sheet.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/series/services/series_search_service.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/filter_list_dialog.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/filter_list_item.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/licensed_status_dialog.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/sort_selection_dialog.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/tri_state_chip.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_filter_sheet_launcher.dart';
import 'package:mangabaka_app/core/widgets/design/mb_badge.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';

class MockSeriesSearchService extends Fake implements SeriesSearchService {
  @override
  Future<List<Map<String, dynamic>>> getGenres() async => [
    {'label': 'Action', 'value': 'action'},
    {'label': 'Comedy', 'value': 'comedy'},
  ];
  @override
  Future<List<Map<String, dynamic>>> getTags() async => [];
}

class MockMetadataService extends Fake implements MetadataService {
  @override
  String getGenreLabel(String value) => value;
  @override
  String getTagName(int id) => 'Tag $id';
}

void main() {
  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<SeriesSearchService>(MockSeriesSearchService());
    getIt.registerSingleton<MetadataService>(MockMetadataService());
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: Scaffold(
        body: SearchFilterBottomSheet(
          initialFilters: SearchFilters(),
          onApply: (_) {},
        ),
      ),
    );
  }

  testWidgets('SearchFilterBottomSheet renders filter sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump(); // Handle metadata loading

    // Check for headers (using translated keys if they aren't translated in tests)
    expect(find.text('FILTERS'), findsOneWidget);
    expect(find.text('SORT_BY'), findsAtLeast(1));
    expect(find.text('GENRES'), findsOneWidget);
    expect(find.text('TAGS'), findsOneWidget);
  });

  testWidgets('Reset button clears filters', (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    final resetButton = find.text('RESET');
    await tester.tap(resetButton);
    await tester.pump();

    // Verify reset logic (this is more of a unit test but we can check UI updates if any)
  });

  testWidgets(
    'Tri-state chip keeps readable include and exclude states across themes',
    (tester) async {
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      final state = ValueNotifier<TriState>(TriState.off);
      addTearDown(palette.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder<TriState>(
                  valueListenable: state,
                  builder: (_, current, _) => TriStateChip(
                    label: 'Action',
                    state: current,
                    onChanged: (next) => state.value = next,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      for (final colors in [
        EirenYuPalette.dark,
        EirenYuPalette.light,
        EirenYuPalette.light.withAccent(const Color(0xFFFBD24B)),
        ThemePresets.byId('nord')!.dark!,
      ]) {
        palette.value = colors;
        await tester.pump();
        for (final expected in [
          TriState.include,
          TriState.exclude,
          TriState.off,
        ]) {
          await tester.tap(find.text('Action'));
          await tester.pump();
          expect(state.value, expected);
          final chip = tester.widget<ActionChip>(find.byType(ActionChip));
          final label = tester.widget<Text>(find.text('Action'));
          if (colors.usesCanonicalYellow && expected == TriState.include) {
            expect(label.style!.color, colors.text);
          }
          expect(
            MbPalette.contrastRatio(label.style!.color!, chip.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'Filter list keeps search and selection while its route changes theme',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      List<String> includes = [];
      List<String> excludes = [];
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => FilterListDialog(
                        title: 'Genres',
                        items: const [
                          {'value': 'action', 'label': 'Action'},
                          {'value': 'comedy', 'label': 'Comedy'},
                        ],
                        idKey: 'value',
                        nameKey: 'label',
                        initialIncludes: const [],
                        initialExcludes: const [],
                        onApply: (inc, exc) {
                          includes = List.of(inc);
                          excludes = List.of(exc);
                        },
                      ),
                    ),
                    child: const Text('Open genres'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open genres'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Action');
      await tester.tap(find.widgetWithText(FilterListItem, 'Action'));
      await tester.pump();
      expect(includes, ['action']);

      palette.value = EirenYuPalette.light;
      await tester.pump();
      expect(find.byType(FilterListDialog), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Action',
      );
      expect(includes, ['action']);
      final selectedIcon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(
        MbPalette.contrastRatio(
          selectedIcon.color!,
          EirenYuPalette.light.background,
        ),
        greaterThanOrEqualTo(3.0),
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(700, 320);
      await tester.pump();
      expect(find.byType(FilterListDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.cancel).last);
      await tester.pump();
      expect(includes, isEmpty);
      expect(excludes, ['action']);
    },
  );

  testWidgets(
    'Filter sheet retains draft across theme changes and Apply/Cancel',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      SearchFilters? applied;
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => SearchFilterSheetLauncher.show(
                      context,
                      initialFilters: SearchFilters(type: ['manga']),
                      onApply: (value) => applied = value,
                    ),
                    child: const Text('Open filters'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open filters'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchFilterBottomSheet), findsOneWidget);
      await tester.tap(find.text('RESET'));
      await tester.pump();
      palette.value = ThemePresets.byId('nord')!.dark!;
      await tester.pump();
      expect(find.byType(SearchFilterBottomSheet), findsOneWidget);
      final applyText = tester.widget<Text>(find.text('APPLY'));
      expect(
        MbPalette.contrastRatio(applyText.style!.color!, palette.value.accent),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.text('APPLY'));
      await tester.pumpAndSettle();
      expect(applied!.type, isEmpty);

      await tester.tap(find.text('Open filters'));
      await tester.pumpAndSettle();
      palette.value = EirenYuPalette.light;
      await tester.pump();
      final modal = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(modal.backgroundColor, Colors.transparent);
      expect(find.byType(SearchFilterBottomSheet), findsOneWidget);
      expect(find.byType(MbBadge), findsOneWidget);
      Navigator.of(tester.element(find.byType(SearchFilterBottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(applied!.type, isEmpty);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(700, 320);
      palette.value = EirenYuPalette.dark;
      await tester.pump();
      await tester.tap(find.text('Open filters'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchFilterBottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(SearchFilterBottomSheet))).pop();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Sort and licensed dialogs retain selection and contrast across themes',
    (tester) async {
      tester.view.physicalSize = const Size(700, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      final l10n = LocalizationService();
      String? selectedSort;
      bool? selectedLicense;

      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: Builder(
              builder: (context) => Scaffold(
                body: Row(
                  children: [
                    TextButton(
                      onPressed: () => SortSelectionDialog.show(
                        context: context,
                        l10n: l10n,
                        sortOptions: const {'name_asc': 'Title Asc'},
                        currentFilters: SearchFilters(sortBy: 'name_asc'),
                        onSortSelected: (value) => selectedSort = value,
                      ),
                      child: const Text('Open sort'),
                    ),
                    TextButton(
                      onPressed: () => LicensedStatusDialog.show(
                        context: context,
                        l10n: l10n,
                        currentFilters: SearchFilters(isLicensed: true),
                        onStatusSelected: (value) => selectedLicense = value,
                      ),
                      child: const Text('Open license'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sort'));
      await tester.pumpAndSettle();
      palette.value = EirenYuPalette.light;
      await tester.pump();
      expect(find.text('Title Asc'), findsOneWidget);
      expect(
        MbPalette.contrastRatio(
          tester.widget<Text>(find.text('Title Asc')).style!.color!,
          EirenYuPalette.light.surface,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Title Asc'));
      await tester.pumpAndSettle();
      expect(selectedSort, 'name_asc');

      await tester.tap(find.text('Open license'));
      await tester.pumpAndSettle();
      palette.value = ThemePresets.byId('nord')!.dark!;
      await tester.pump();
      expect(find.text(l10n.translate('yes')), findsOneWidget);
      expect(
        MbPalette.contrastRatio(
          tester.widget<Text>(find.text(l10n.translate('yes'))).style!.color!,
          palette.value.surface,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(l10n.translate('no')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.translate('no')));
      await tester.pumpAndSettle();
      expect(selectedLicense, false);
    },
  );
}
