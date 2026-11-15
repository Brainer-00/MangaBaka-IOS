import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/series/controllers/series_filter_drawer_controller.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/services/series_search_service.dart';
import 'package:mangabaka_app/features/series/widgets/chips/date_dialog.dart';
import 'package:mangabaka_app/features/series/widgets/description_section.dart';
import 'package:mangabaka_app/features/series/widgets/series_detail_error_banner.dart';
import 'package:mangabaka_app/features/series/widgets/series_filter_drawer.dart';
import 'package:mangabaka_app/features/series/widgets/series_information_card.dart';
import 'package:mangabaka_app/features/series/widgets/series_list_skeleton.dart';
import 'package:mangabaka_app/features/series/widgets/series_detail_skeleton.dart';
import 'package:mangabaka_app/features/series/widgets/series_details_grid.dart';
import 'package:mangabaka_app/features/series/widgets/series_hero_cover.dart';
import 'package:mangabaka_app/features/series/widgets/mb_card.dart';
import 'package:mangabaka_app/features/series/widgets/tags_placeholder.dart';

class _SearchService implements SeriesSearchService {
  @override
  Future<List<Map<String, dynamic>>> getGenres() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getTags() async => const [];

  @override
  Future<SeriesSearchResult> searchSeries(
    String query, {
    String? sortBy,
    String? type,
    Map<String, dynamic>? extraParams,
  }) => throw UnimplementedError();

  @override
  Future<List<Series>> searchSeriesByName(
    String query, {
    String? sortBy,
    String? type,
    Map<String, dynamic>? extraParams,
  }) => throw UnimplementedError();

  @override
  void dispose() {}
}

class _DateDialogHost extends StatelessWidget {
  const _DateDialogHost({required this.palette});

  final ValueListenable<MbPalette> palette;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MbPalette>(
    valueListenable: palette,
    builder: (context, colors, _) => MaterialApp(
      theme: AppTheme.build(showTooltips: true, palette: colors),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const DateDialog(start: '2020-01-01', end: '2021-01-01'),
              ),
              child: const Text('Open date'),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DrawerHost extends StatefulWidget {
  const _DrawerHost({super.key, required this.palette});

  final ValueListenable<MbPalette> palette;

  @override
  State<_DrawerHost> createState() => _DrawerHostState();
}

class _DrawerHostState extends State<_DrawerHost>
    with TickerProviderStateMixin {
  late final SeriesFilterDrawerController controller;

  @override
  void initState() {
    super.initState();
    controller = SeriesFilterDrawerController(
      vsync: this,
      searchService: _SearchService(),
    );
    controller.replaceFilters(SearchFilters(genre: const ['action']));
    controller.drawerAnimation.value = 1;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<MbPalette>(
    valueListenable: widget.palette,
    builder: (context, colors, _) => MaterialApp(
      theme: AppTheme.build(showTooltips: true, palette: colors),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Stack(
          children: [
            const SizedBox.expand(),
            SeriesFilterDrawer(controller: controller, onSearch: (_) {}),
          ],
        ),
      ),
    ),
  );
}

void main() {
  final palettes = <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  };

  Series seriesFixture() => Series.fromJson({
    'id': 'series-visual-theme',
    'title': 'Theme fixture',
    'authors': ['Readable Author'],
    'type': 'manga',
    'status': 'completed',
    'published': {'start_date': '2020-01-01'},
    'anime': {'start': '2020', 'end': '2022'},
    'description': List.filled(
      55,
      'A long description remains expanded.',
    ).join(' '),
  });

  testWidgets('date dialog recolors live and closes from its action', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(_DateDialogHost(palette: palette));
    await tester.tap(find.text('Open date'));
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
    await tester.tap(find.text(LocalizationService().translate('close')));
    await tester.pumpAndSettle();
    expect(find.byType(DateDialog), findsNothing);
  });

  for (final entry in palettes.entries) {
    testWidgets(
      '${entry.key}: Series visual surfaces use semantic palette roles',
      (tester) async {
        final palette = entry.value;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: palette),
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: DateDialog(start: '2020-01-01', end: '2021-01-01'),
                  ),
                  SliverToBoxAdapter(
                    child: SeriesInformationCard(
                      series: seriesFixture(),
                      l10n: LocalizationService(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: DescriptionSection(
                      description: seriesFixture().description,
                    ),
                  ),
                  SeriesDetailErrorBanner(onRetry: () {}),
                  const SliverToBoxAdapter(child: SeriesDetailSkeleton()),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        final author = tester.widget<Text>(find.text('Readable Author'));
        expect(
          MbPalette.contrastRatio(author.style!.color!, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
        final authorLabel = tester.widget<Text>(find.text('AUTHORS'));
        expect(
          MbPalette.contrastRatio(authorLabel.style!.color!, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
        final calendar = tester.widget<Icon>(
          find.byIcon(Icons.calendar_today_rounded),
        );
        final calendarSurface = Color.alphaBlend(
          palette.accent.withValues(alpha: 0.12),
          palette.surface,
        );
        expect(
          MbPalette.contrastRatio(calendar.color!, calendarSurface),
          greaterThanOrEqualTo(4.5),
        );
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -1200),
        );
        await tester.pump(const Duration(milliseconds: 250));
        final retry = tester.widget<Text>(
          find.text(LocalizationService().translate('retry')),
        );
        final bannerTint = Color.alphaBlend(
          palette.error.withValues(alpha: 0.14),
          palette.surfaceRaised,
        );
        expect(
          MbPalette.contrastRatio(retry.style!.color!, bannerTint),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }

  testWidgets('description expansion survives live palette change', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DescriptionSection(
                description: seriesFixture().description,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final descriptionText = tester.widget<Text>(
      find.text(seriesFixture().description),
    );
    expect(
      MbPalette.contrastRatio(
        descriptionText.style!.color!,
        EirenYuPalette.dark.background,
      ),
      greaterThanOrEqualTo(4.5),
    );
    await tester.tap(find.text(LocalizationService().translate('show_more')));
    await tester.pumpAndSettle();
    expect(
      find.text(LocalizationService().translate('show_less')),
      findsOneWidget,
    );
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(
      find.text(LocalizationService().translate('show_less')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter drawer recolors live without dropping selected filters', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    final hostKey = GlobalKey<_DrawerHostState>();
    await tester.pumpWidget(_DrawerHost(key: hostKey, palette: palette));
    await tester.pump(const Duration(milliseconds: 350));
    expect(hostKey.currentState!.controller.filters!.genre, ['action']);
    var expectedBackground = EirenYuPalette.dark.background;
    final sheet = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color == expectedBackground,
    );
    expect(sheet, findsOneWidget);

    palette.value = EirenYuPalette.light;
    expectedBackground = EirenYuPalette.light.background;
    await tester.pump(const Duration(milliseconds: 350));
    expect(sheet, findsOneWidget);
    expect(hostKey.currentState!.controller.filters!.genre, ['action']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Series Details metadata uses readable semantic text', (
    tester,
  ) async {
    final palette = EirenYuPalette.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: palette),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeriesDetailsGrid(
              series: seriesFixture(),
              l10n: LocalizationService(),
            ),
          ),
        ),
      ),
    );
    final animeYear = tester.widget<Text>(find.text('2020'));
    expect(
      MbPalette.contrastRatio(animeYear.style!.color!, palette.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
  });

  for (final entry in palettes.entries) {
    testWidgets('${entry.key}: hero cover hover uses a visible theme accent', (
      tester,
    ) async {
      final palette = entry.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: Center(
              child: SeriesHeroCover(
                series: seriesFixture(),
                height: 180,
                width: 120,
              ),
            ),
          ),
        ),
      );
      final cover = find.byType(SeriesHeroCover);
      final center = tester.getCenter(cover);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: center);
      await gesture.moveTo(center);
      await tester.pump(const Duration(milliseconds: 60));
      final animated = tester.widget<AnimatedContainer>(
        find.descendant(of: cover, matching: find.byType(AnimatedContainer)),
      );
      final border = animated.decoration as BoxDecoration;
      expect(
        border.border!.top.color,
        palette.accentOn(palette.background, minimum: 3),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('error banner Retry preserves callback behavior', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [SeriesDetailErrorBanner(onRetry: () => retries++)],
          ),
        ),
      ),
    );
    await tester.tap(find.text(LocalizationService().translate('retry')));
    expect(retries, 1);
  });

  testWidgets(
    'narrow portrait and short landscape Series placeholders do not overflow',
    (tester) async {
      for (final size in [const Size(320, 640), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(
              showTooltips: true,
              palette: EirenYuPalette.light,
            ),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: SeriesListSkeleton(isGrid: true)),
                  Expanded(
                    child: SingleChildScrollView(child: SeriesDetailSkeleton()),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('TagsPlaceholder scales inside a padded card and recolors live', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final width in [320.0, 375.0]) {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (context, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: MbCard(label: 'Tags', child: const TagsPlaceholder()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(TagsPlaceholder),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).color ==
                    EirenYuPalette.dark.surfaceRaised.withValues(alpha: 0.65),
          ),
        ),
        findsNWidgets(6),
      );
    }

    palette.value = EirenYuPalette.light;
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(TagsPlaceholder),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  EirenYuPalette.light.surfaceRaised.withValues(alpha: 0.65),
        ),
      ),
      findsNWidgets(6),
    );
  });
}
