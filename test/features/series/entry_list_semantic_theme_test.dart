import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/collections/widgets/collection_card.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';
import 'package:mangabaka_app/features/series/widgets/entry_list_item.dart';
import 'package:mangabaka_app/features/series/widgets/entry_list_item_layouts.dart';
import 'package:mangabaka_app/features/series/widgets/entry_list_item_list_layouts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UnusedLibraryService extends Fake implements LibraryService {
  @override
  Stream<LibraryEntry?> watchEntryFromDb(String id) =>
      Stream<LibraryEntry?>.value(null);
}

final _palettes = <String, MbPalette>{
  'EirenYu Dark': EirenYuPalette.dark,
  'EirenYu Light': EirenYuPalette.light,
  'Nord Dark': ThemePresets.byId('nord')!.dark!,
  'Catppuccin Light': ThemePresets.byId('catppuccin')!.light!,
  'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
};

final _series = Series.fromJson({
  'id': 'entry-theme-fixture',
  'title': 'Entry theme fixture',
  'cover': '',
  'type': 'manga',
  'status': 'completed',
  'year': '2024',
  'rating': '8.5',
  'total_chapters': '100',
});

final _collection = SeriesCollection(
  id: 'collection-theme-fixture',
  title: 'Collection title',
  format: 'Tankobon',
  type: 'manga',
  status: 'ongoing',
  medium: 'Print',
  publisherName: 'Publisher name',
  editionName: 'Edition name',
  languageName: 'English',
  countMain: 4,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await resetServiceLocator();
  });

  tearDown(() async {
    await resetServiceLocator();
  });

  for (final entry in _palettes.entries) {
    testWidgets('${entry.key}: entry layouts and collection text are themed', (
      tester,
    ) async {
      final palette = entry.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: 60,
                    height: 80,
                    child: EntryListLayoutHelper.buildPlaceholder(60, 80),
                  ),
                  SizedBox(
                    width: 140,
                    height: 240,
                    child: CompactGridItem(
                      series: _series,
                      displayTitle: _series.title,
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    height: 190,
                    child: CoverOnlyGridItem(series: _series),
                  ),
                  MinimalListItem(series: _series, displayTitle: _series.title),
                  CompactListItem(
                    series: _series,
                    displayTitle: _series.title,
                    l10n: LocalizationService(),
                  ),
                  ComfortableListItem(
                    series: _series,
                    displayTitle: _series.title,
                    l10n: LocalizationService(),
                  ),
                  CollectionCard(collection: _collection),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final brokenImage in tester.widgetList<Icon>(
        find.byIcon(Icons.broken_image),
      )) {
        expect(
          MbPalette.contrastRatio(brokenImage.color!, palette.surfaceRaised),
          greaterThanOrEqualTo(3),
        );
      }
      expect(
        tester.widget<Card>(find.byType(Card).first).color,
        palette.surface,
      );
      for (final title in tester.widgetList<Text>(find.text(_series.title))) {
        expect(title.style!.color, palette.text);
        expect(
          MbPalette.contrastRatio(title.style!.color!, palette.background),
          greaterThanOrEqualTo(4.5),
        );
      }
      final collectionTitle = tester.widget<Text>(find.text(_collection.title));
      expect(collectionTitle.style!.color, palette.text);
      final byline = tester.widget<Text>(find.textContaining('Publisher name'));
      expect(
        MbPalette.contrastRatio(byline.style!.color!, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
      final volumeCount = tester.widget<Text>(find.text('4 VOLS'));
      expect(
        MbPalette.contrastRatio(volumeCount.style!.color!, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
      final badge = tester.widget<Text>(find.text('TANKOBON'));
      expect(
        MbPalette.contrastRatio(badge.style!.color!, palette.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  testWidgets('entry ranking and progress indicators use active accent', (
    tester,
  ) async {
    final palette = EirenYuPalette.light.withAccent(const Color(0xFF808080));
    getIt.registerSingleton<ProfileAuthService>(ProfileAuthService());
    getIt.registerSingleton<LibraryService>(_UnusedLibraryService());
    await SettingsManager().setShowLibraryProgress(true);
    await SettingsManager().setShowQuickProgress(false);
    final libraryEntry = LibraryEntry(
      id: 'entry-theme-fixture',
      state: 'reading',
      progressChapter: 45,
      series: _series,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: palette),
        home: Scaffold(
          body: EntryListItem(
            series: _series,
            ranking: 3,
            listStyle: AppListStyle.compact,
            previewEntry: libraryEntry,
          ),
        ),
      ),
    );
    await tester.pump();

    final ranking = tester.widget<Text>(find.text('3'));
    expect(
      MbPalette.contrastRatio(ranking.style!.color!, palette.accent),
      greaterThanOrEqualTo(4.5),
    );
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      MbPalette.contrastRatio(
        progress.valueColor!.value!,
        progress.backgroundColor!,
      ),
      greaterThanOrEqualTo(3),
    );
    expect(progress.value, 0.45);
  });

  testWidgets('collection callback and publisher visibility are preserved', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: EirenYuPalette.dark),
        home: Scaffold(
          body: CollectionCard(
            collection: _collection,
            onTap: () => taps++,
            showPublisher: false,
          ),
        ),
      ),
    );

    expect(find.text('Publisher name'), findsNothing);
    expect(find.textContaining('Edition name'), findsOneWidget);
    await tester.tap(find.text(_collection.title));
    expect(taps, 1);
  });

  testWidgets('placeholder follows live palette changes and retains its Hero', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, value, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: value),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: 60,
                    height: 80,
                    child: EntryListLayoutHelper.buildPlaceholder(60, 80),
                  ),
                  SizedBox(
                    width: 60,
                    height: 80,
                    child: EntryListLayoutHelper.buildCoverImage(
                      series: _series,
                      heroTagPrefix: 'theme-test',
                      width: 60,
                      height: 80,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widgetList<Container>(find.byType(Container))
          .any(
            (container) => container.color == EirenYuPalette.dark.surfaceRaised,
          ),
      isTrue,
    );
    expect(
      tester.widget<Hero>(find.byType(Hero)).tag,
      'theme-test_${_series.id}',
    );

    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Container>(find.byType(Container))
          .any(
            (container) =>
                container.color == EirenYuPalette.light.surfaceRaised,
          ),
      isTrue,
    );
  });

  testWidgets(
    'entry layouts and collection card fit phone and landscape widths',
    (tester) async {
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
                    MinimalListItem(
                      series: _series,
                      displayTitle: _series.title,
                    ),
                    CompactListItem(
                      series: _series,
                      displayTitle: _series.title,
                      l10n: LocalizationService(),
                    ),
                    ComfortableListItem(
                      series: _series,
                      displayTitle: _series.title,
                      l10n: LocalizationService(),
                    ),
                    CollectionCard(collection: _collection),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'viewport $size');
      }
    },
  );
}
