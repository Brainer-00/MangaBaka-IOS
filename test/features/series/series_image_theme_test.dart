import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';
import 'package:mangabaka_app/features/series/models/series_cover.dart';
import 'package:mangabaka_app/features/series/models/series_work.dart';
import 'package:mangabaka_app/features/series/widgets/tabs/series_covers_tab.dart';
import 'package:mangabaka_app/features/series/widgets/tabs/series_works_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final palettes = <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'Catppuccin Light': ThemePresets.byId('catppuccin')!.light!,
    'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  };

  final work = SeriesWork(
    id: 'work-1',
    subTitle: 'Collected edition',
    countType: 'Pages',
    releaseDate: '2026-01-01',
    sequenceString: '1',
    pages: 240,
    priceString: '\$12.00',
  );

  testWidgets('empty and asset-error image states use live semantic colors', (
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
          body: Column(
            children: [
              WidgetUtils.networkImage(url: ''),
              WidgetUtils.networkImage(url: 'assets/missing-theme-test.png'),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump();
    for (final paletteValue in palettes.values) {
      palette.value = paletteValue;
      await tester.pumpWidget(host());
      await tester.pump();
      final brokenIcons = tester.widgetList<Icon>(
        find.byIcon(Icons.broken_image),
      );
      expect(brokenIcons, hasLength(2));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.color == paletteValue.surfaceRaised,
        ),
        findsNWidgets(2),
      );
      for (final icon in brokenIcons) {
        expect(
          MbPalette.contrastRatio(icon.color!, paletteValue.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('custom image placeholder and error widgets remain honored', (
    tester,
  ) async {
    const placeholder = ColoredBox(
      key: ValueKey('custom-placeholder'),
      color: Colors.purple,
    );
    const error = ColoredBox(
      key: ValueKey('custom-image-error'),
      color: Colors.orange,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            WidgetUtils.networkImage(
              url: 'https://images.example.test/pending.png',
              placeholder: placeholder,
            ),
            WidgetUtils.networkImage(url: '', errorWidget: error),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('custom-placeholder')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-image-error')), findsOneWidget);
  });

  testWidgets('default network placeholder recolors with the active theme', (
    tester,
  ) async {
    // Flutter's widget-test binding replaces network access with a fake HTTP
    // client, so this URL never reaches an external service.
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);

    Widget host() => ValueListenableBuilder<MbPalette>(
      valueListenable: palette,
      builder: (context, colors, _) => MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: colors),
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: WidgetUtils.networkImage(
            url: 'https://images.example.test/pending.png',
          ),
        ),
      ),
    );

    await tester.pumpWidget(host());
    final cachedImageElement = tester.element(find.byType(CachedNetworkImage));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.color == EirenYuPalette.dark.surfaceRaised,
      ),
      findsOneWidget,
    );
    palette.value = EirenYuPalette.light;
    await tester.pumpWidget(host());
    expect(
      identical(
        tester.element(find.byType(CachedNetworkImage)),
        cachedImageElement,
      ),
      isTrue,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.color == EirenYuPalette.light.surfaceRaised,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('default placeholder tolerates an unbounded column axis', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: EirenYuPalette.dark),
        home: Scaffold(
          body: Column(
            children: [
              WidgetUtils.networkImage(
                url: 'https://images.example.test/unbounded.png',
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final entry in palettes.entries) {
    testWidgets('${entry.key}: Covers and Works use semantic palette roles', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      SettingsManager.resetForTesting();
      final palette = entry.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SeriesCoversTab(
                    covers: [SeriesCover(type: 'volume', language: 'en')],
                  ),
                  SeriesWorksTab(works: [work]),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.color == palette.surfaceRaised,
        ),
        findsWidgets,
      );
      final coverCaption = tester.widget<Text>(
        find.text('[EN] Front (Volume)'),
      );
      expect(coverCaption.style!.color, palette.text);
      expect(
        MbPalette.contrastRatio(coverCaption.style!.color!, palette.background),
        greaterThanOrEqualTo(4.5),
      );
      final missingCoverIcon = tester.widget<Icon>(
        find.byIcon(Icons.broken_image).last,
      );
      expect(
        MbPalette.contrastRatio(missingCoverIcon.color!, palette.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
      final workTitle = tester.widget<Text>(find.text('Collected edition'));
      expect(workTitle.style!.color, palette.text);
      final price = tester.widget<Text>(find.text('\$12.00'));
      final metadataTexts = tester.widgetList<Text>(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.style?.fontSize == 12,
        ),
      );
      expect(metadataTexts, isNotEmpty);
      for (final text in metadataTexts) {
        expect(
          MbPalette.contrastRatio(text.style!.color!, palette.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
      }
      for (final icon in [Icons.description_outlined, Icons.label_outline]) {
        expect(
          MbPalette.contrastRatio(
            tester.widget<Icon>(find.byIcon(icon)).color!,
            palette.surfaceRaised,
          ),
          greaterThanOrEqualTo(3),
        );
      }
      expect(
        MbPalette.contrastRatio(price.style!.color!, palette.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pump();
      final gridPrice = tester.widget<Text>(find.text('\$12.00'));
      expect(
        MbPalette.contrastRatio(gridPrice.style!.color!, palette.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Covers skeleton surfaces recolor without resetting layout', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    Widget host() => ValueListenableBuilder<MbPalette>(
      valueListenable: palette,
      builder: (context, colors, _) => MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: colors),
        themeAnimationDuration: Duration.zero,
        home: Scaffold(body: SeriesCoversTab(covers: null)),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 30));
    for (final expected in [EirenYuPalette.dark, EirenYuPalette.light]) {
      palette.value = expected;
      await tester.pumpWidget(host());
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  expected.surfaceRaised,
        ),
        findsNWidgets(6),
      );
      expect(find.byType(SeriesCoversTab), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('cover hover border follows the active palette', (tester) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: SeriesCoversTab(
              covers: [
                SeriesCover(
                  type: 'volume',
                  language: 'en',
                  url: 'assets/series_222_cover.jpg',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final item = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion && widget.cursor == SystemMouseCursors.click,
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(item));
    await gesture.moveTo(tester.getCenter(item) + const Offset(1, 1));
    await tester.pump(const Duration(milliseconds: 200));
    palette.value = EirenYuPalette.light;
    await tester.pump();
    final animated = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    final border = (animated.decoration! as BoxDecoration).border!;
    expect(
      border.top.color,
      EirenYuPalette.light.accentOn(
        EirenYuPalette.light.background,
        minimum: 3,
      ),
    );
    expect(tester.takeException(), isNull);
    await gesture.removePointer();
  });

  testWidgets('Works list/grid choice remains interactive across themes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (context, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: SeriesWorksTab(works: [work])),
        ),
      ),
    );
    await tester.pump();
    expect(SettingsManager().worksListStyle.isGrid, isFalse);
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    expect(SettingsManager().worksListStyle, AppListStyle.compactGrid);
    expect(find.byType(AspectRatio), findsOneWidget);

    palette.value = EirenYuPalette.light;
    await tester.pump();
    expect(SettingsManager().worksListStyle.isGrid, isTrue);
    expect(find.text('Collected edition'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow portrait and landscape tabs do not overflow', (
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
                  SeriesCoversTab(
                    covers: [
                      SeriesCover(type: 'volume', language: 'en'),
                      SeriesCover(type: 'other', language: 'ja'),
                    ],
                  ),
                  SeriesWorksTab(works: [work]),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
  });
}
