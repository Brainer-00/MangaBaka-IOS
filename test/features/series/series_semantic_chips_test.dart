import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/models/tag_chip_data.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/features/series/widgets/chip.dart';
import 'package:mangabaka_app/features/series/widgets/chips/content_rating_chip.dart';
import 'package:mangabaka_app/features/series/widgets/chips/rating_chip.dart';
import 'package:mangabaka_app/features/series/widgets/chips/status_chip.dart';
import 'package:mangabaka_app/features/series/widgets/mini_badge.dart';
import 'package:mangabaka_app/features/series/widgets/series_genres_section.dart';
import 'package:mangabaka_app/features/series/widgets/series_grouped_tags.dart';
import 'package:mangabaka_app/features/series/widgets/series_segmented_control.dart';
import 'package:mangabaka_app/features/series/widgets/series_tag_group.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';

class _FixtureMetadataService extends MetadataService {
  int lookupCount = 0;

  @override
  String getGenreLabel(String value) => value;

  @override
  String? getTagPath(String tagName) {
    lookupCount++;
    return 'Genre > Theme > $tagName';
  }

  @override
  String? getTagId(String tagName) {
    lookupCount++;
    return 'id-$tagName';
  }
}

class _SegmentedHarness extends StatefulWidget {
  const _SegmentedHarness({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_SegmentedHarness> createState() => _SegmentedHarnessState();
}

class _SegmentedHarnessState extends State<_SegmentedHarness> {
  String selected = 'Info';

  @override
  Widget build(BuildContext context) => SeriesSegmentedControl(
    selectedTab: selected,
    onTabChanged: (value) {
      widget.onChanged(value);
      setState(() => selected = value);
    },
  );
}

void main() {
  final palettes = <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  };

  Widget themed(MbPalette palette, Widget child) => MaterialApp(
    theme: AppTheme.build(showTooltips: true, palette: palette),
    home: Scaffold(body: child),
  );

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  for (final entry in palettes.entries) {
    testWidgets('${entry.key} genre, status and rating colors are readable', (
      tester,
    ) async {
      final colors = entry.value;
      final metadata = _FixtureMetadataService();
      getIt.registerSingleton<MetadataService>(metadata);
      final series = Series.fromJson({
        'id': 'series-1',
        'title': 'Fixture',
        'genres': ['Fantasy'],
      });
      final ratingEntry = LibraryEntry(
        id: 'entry-1',
        state: 'reading',
        rating: 80,
        series: series,
      );

      await tester.pumpWidget(
        themed(
          colors,
          ListView(
            children: [
              SeriesGenresSection(series: series, l10n: LocalizationService()),
              const StatusChip(status: 'Releasing'),
              const StatusChip(status: 'Completed'),
              const StatusChip(status: 'Hiatus'),
              const ContentRatingChip(rating: 'Suggestive'),
              const ContentRatingChip(rating: 'Pornographic'),
              RatingChip(sources: const [], entry: ratingEntry),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final genreChip = tester.widget<ChipBase>(
        find.ancestor(
          of: find.text('Fantasy'),
          matching: find.byType(ChipBase),
        ),
      );
      expect(genreChip.backgroundColor, colors.surfaceRaised);
      final genreText = tester.widget<Text>(find.text('Fantasy'));
      expect(
        MbPalette.contrastRatio(genreText.style!.color!, colors.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );

      for (final label in [
        'RELEASING',
        'COMPLETED',
        'HIATUS',
        'SUGGESTIVE',
        'PORNOGRAPHIC',
        '80 / 100',
      ]) {
        final badgeFinder = find.ancestor(
          of: find.text(label),
          matching: find.byType(MiniBadge),
        );
        final badge = tester.widget<MiniBadge>(badgeFinder);
        final text = tester.widget<Text>(find.text(label));
        final background = badge.backgroundColor!;
        expect(
          MbPalette.contrastRatio(text.style!.color!, background),
          greaterThanOrEqualTo(4.5),
          reason: '$label should remain readable on $background',
        );
      }

      final ratingBadge = tester.widget<MiniBadge>(
        find.ancestor(
          of: find.text('80 / 100'),
          matching: find.byType(MiniBadge),
        ),
      );
      expect(ratingBadge.color, colors.star);
    });
  }

  testWidgets('genre selection contrast and explicit chip overrides persist', (
    tester,
  ) async {
    final colors = EirenYuPalette.light.withAccent(const Color(0xFF808080));
    const explicitBackground = Color(0xFF123456);
    const explicitBorder = Color(0xFF654321);
    const explicitForeground = Color(0xFFABCDEF);
    await tester.pumpWidget(
      themed(
        colors,
        Column(
          children: [
            ChipBase(
              label: const Text('selected genre'),
              backgroundColor: colors.accent,
              borderColor: colors.accent,
              labelStyle: TextStyle(color: colors.accentOn(colors.accent)),
            ),
            const MiniBadge(
              text: 'override',
              color: explicitForeground,
              backgroundColor: explicitBackground,
              hoverColor: explicitBorder,
              onTap: _noop,
            ),
            const ChipBase(
              label: Text('explicit'),
              backgroundColor: explicitBackground,
              borderColor: explicitBorder,
              labelStyle: TextStyle(color: explicitForeground),
            ),
          ],
        ),
      ),
    );

    final selected = tester.widget<ChipBase>(
      find.ancestor(
        of: find.text('selected genre'),
        matching: find.byType(ChipBase),
      ),
    );
    expect(selected.backgroundColor, colors.accent);
    expect(
      MbPalette.contrastRatio(colors.accentOn(colors.accent), colors.accent),
      greaterThanOrEqualTo(4.5),
    );

    final badge = tester.widget<MiniBadge>(find.byType(MiniBadge));
    expect(badge.color, explicitForeground);
    expect(badge.backgroundColor, explicitBackground);
    expect(badge.hoverColor, explicitBorder);
    final explicitChip = tester.widget<ChipBase>(
      find.ancestor(of: find.text('explicit'), matching: find.byType(ChipBase)),
    );
    expect(explicitChip.backgroundColor, explicitBackground);
    expect(explicitChip.borderColor, explicitBorder);
    expect(explicitChip.labelStyle!.color, explicitForeground);
  });

  testWidgets('segmented tabs update across themes and preserve selection', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    final callbacks = <String>[];
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(body: _SegmentedHarness(onChanged: callbacks.add)),
        ),
      ),
    );

    await tester.tap(find.text('COVERS'));
    await tester.pumpAndSettle();
    expect(callbacks, contains('Covers'));
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(find.text('COVERS'), findsOneWidget);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(
      tabBar.labelColor,
      EirenYuPalette.light.accentOn(EirenYuPalette.light.accent),
    );
    expect(
      MbPalette.contrastRatio(
        tabBar.unselectedLabelColor!,
        EirenYuPalette.light.background,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets(
    'resolved expanded tags recolor without repeating metadata lookups',
    (tester) async {
      final metadata = _FixtureMetadataService();
      getIt.registerSingleton<MetadataService>(metadata);
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      final tags = List<String>.generate(100, (index) => 'Tag $index');
      final series = Series.fromJson({
        'id': 'tags-1',
        'title': 'Tags',
        'tags': tags,
      });
      Widget app() => ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeriesGroupedTags(
                series: series,
                l10n: LocalizationService(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final resolvedLookups = metadata.lookupCount;
      expect(resolvedLookups, tags.length * 2);
      expect(find.text('show_all_tags'), findsOneWidget);
      final fadeContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SeriesGroupedTags),
              matching: find.byType(Container),
            ),
          )
          .where((container) {
            final decoration = container.decoration;
            return decoration is BoxDecoration && decoration.gradient != null;
          });
      expect(fadeContainers, isNotEmpty);
      final fadeGradient =
          (fadeContainers.first.decoration! as BoxDecoration).gradient!
              as LinearGradient;
      expect(fadeGradient.colors.last, EirenYuPalette.dark.surface);
      await tester.tap(find.text('show_all_tags'));
      await tester.pumpAndSettle();
      expect(find.text('show_less'), findsOneWidget);

      palette.value = EirenYuPalette.light;
      await tester.pumpAndSettle();
      expect(find.text('show_less'), findsOneWidget);
      expect(metadata.lookupCount, resolvedLookups);
      final tagChip = tester.widget<ChipBase>(
        find.ancestor(of: find.text('Tag 99'), matching: find.byType(ChipBase)),
      );
      expect(tagChip.backgroundColor, EirenYuPalette.light.surfaceRaised);
    },
  );

  testWidgets('tag group preserves selection and tap callbacks', (
    tester,
  ) async {
    final colors = EirenYuPalette.dark;
    final tapped = <String>[];
    final longPressed = <String>[];
    final tag = TagChipData(
      tag: 'Historical',
      tagId: 'historical-id',
      labelParts: const ['Historical'],
    );
    await tester.pumpWidget(
      themed(
        colors,
        SeriesTagGroup(
          header: 'Genre',
          subGroups: {
            'Setting': [tag],
          },
          selectedTagIds: const {'historical-id'},
          onTagTap: tapped.add,
          onTagLongPress: longPressed.add,
        ),
      ),
    );

    await tester.tap(find.text('Historical'));
    await tester.pumpAndSettle();
    expect(tapped, ['Historical']);
    await tester.longPress(find.text('Historical'));
    await tester.pumpAndSettle();
    expect(longPressed, ['Historical']);
    expect(find.text('Historical'), findsOneWidget);
  });

  testWidgets('chips and tabs do not overflow narrow and landscape layouts', (
    tester,
  ) async {
    final originalSize = tester.view.physicalSize;
    final originalDpr = tester.view.devicePixelRatio;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDpr;
    });

    for (final size in const [Size(320, 568), Size(568, 320)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        themed(
          EirenYuPalette.light,
          ListView(
            children: [
              const SeriesSegmentedControl(
                selectedTab: 'Info',
                onTabChanged: _noopString,
              ),
              Wrap(
                spacing: 8,
                children: List<Widget>.generate(
                  8,
                  (index) => ChipBase(label: Text('Long genre label $index')),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

void _noop() {}
void _noopString(String _) {}
