import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';
import 'package:mangabaka_app/features/series/services/series_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/widgets/expandable_chip_wrap.dart';
import 'package:mangabaka_app/features/series/widgets/external_ratings_section.dart';
import 'package:mangabaka_app/features/series/widgets/tabs/series_collections_tab.dart';
import 'package:mangabaka_app/features/series/widgets/tabs/series_similar_tab.dart';
import 'package:mangabaka_app/features/series/widgets/unblur_warning.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final palettes = <MbPalette>[
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    ThemePresets.byId('catppuccin')!.light!,
    EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  ];
  final series = Series.fromJson({
    'id': 'rating-theme',
    'title': 'Fixture',
    'source': {
      'unknown_source': {'rating_normalized': 8.5},
    },
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
  });

  for (final palette in palettes) {
    testWidgets('${palette.background}: ratings and chips stay readable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ExternalRatingsSection(series: series),
                  ExpandableChipWrap(
                    label: 'Genres',
                    items: List.generate(30, (index) => 'chip-$index'),
                    color: const Color(0xFF808080),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final rating = tester.widget<Text>(find.text('8.5').first);
      expect(
        MbPalette.contrastRatio(rating.style!.color!, palette.background),
        greaterThanOrEqualTo(4.5),
      );
      final chip = tester.widget<Text>(find.text('chip-0').last);
      final chipSurface = Color.alphaBlend(
        const Color(0xFF808080).withValues(alpha: 0.15),
        palette.surfaceRaised,
      );
      expect(
        MbPalette.contrastRatio(chip.style!.color!, chipSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chip expansion retains state across a palette update', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    Widget host() => ValueListenableBuilder<MbPalette>(
      valueListenable: palette,
      builder: (context, colors, _) => MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: colors),
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: SingleChildScrollView(
              child: ExpandableChipWrap(
                label: 'Genres',
                items: List.generate(40, (index) => 'long-chip-$index'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(
      find.text(LocalizationService().translate('show_all')),
      findsOneWidget,
    );
    await tester.tap(find.text(LocalizationService().translate('show_all')));
    await tester.pumpAndSettle();
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(
      find.text(LocalizationService().translate('show_less')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unblur dismissal denies access and dialog recolors live', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    bool? result;
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await confirmUnblur(context),
                child: const Text('Open warning'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open warning'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
      EirenYuPalette.dark.surface,
    );
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
      EirenYuPalette.light.surface,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets(
    'Collections and Similar loading and empty states follow palette',
    (tester) async {
      for (final palette in palettes) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: palette),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Column(
                children: [
                  const SeriesCollectionsTab(),
                  SeriesSimilarTab(similar: null, l10n: LocalizationService()),
                ],
              ),
            ),
          ),
        );
        expect(
          tester
              .widgetList<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .every(
                (indicator) => indicator.color == palette.progressIndicator,
              ),
          isTrue,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: palette),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Column(
                children: [
                  const SeriesCollectionsTab(collections: []),
                  SeriesSimilarTab(
                    similar: const [],
                    readersAlsoLike: const [],
                    l10n: LocalizationService(),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Collections landscape column switch changes preference', (
    tester,
  ) async {
    final collection = SeriesCollection(
      id: '1',
      title: 'Test collection',
      format: 'Volume',
      type: 'manga',
      status: 'ongoing',
      medium: 'print',
      publisherName: '',
      editionName: '',
      countMain: 1,
    );
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeriesCollectionsTab(collections: [collection]),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pump();
    expect(SettingsManager().collectionsListColumns, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Similar layout switch updates the stored style', (tester) async {
    getIt.registerLazySingleton<SeriesService>(() => SeriesService());
    getIt.registerSingleton<ProfileAuthService>(ProfileAuthService());
    getIt.registerSingleton<LibraryService>(_UnusedLibraryService());
    addTearDown(getIt.reset);
    final similar = Series.fromJson({
      'id': 'similar-1',
      'title': 'Similar fixture',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeriesSimilarTab(
              similar: [similar],
              readersAlsoLike: const [],
              l10n: LocalizationService(),
            ),
          ),
        ),
      ),
    );
    expect(SettingsManager().similarListStyle, AppListStyle.compactGrid);
    await tester.tap(find.byIcon(Icons.view_day_outlined));
    await tester.pump();
    expect(SettingsManager().similarListStyle, AppListStyle.comfortable);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scoped Series widgets fit narrow portrait and short landscape', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final size in [const Size(320, 640), const Size(740, 360)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            showTooltips: true,
            palette: EirenYuPalette.light,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ExternalRatingsSection(series: series),
                  const ExpandableChipWrap(
                    label: 'Genres',
                    items: ['Long genre name', 'Another genre'],
                  ),
                  const SeriesCollectionsTab(collections: []),
                  SeriesSimilarTab(
                    similar: const [],
                    readersAlsoLike: const [],
                    l10n: LocalizationService(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}

class _UnusedLibraryService implements LibraryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
