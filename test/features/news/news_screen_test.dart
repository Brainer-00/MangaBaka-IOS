import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/news/models/news.dart';
import 'package:mangabaka_app/features/news/screens/news_screen.dart';
import 'package:mangabaka_app/features/news/services/news_service.dart';
import 'package:mangabaka_app/features/news/widgets/news_list_item.dart';
import 'package:mangabaka_app/features/news/widgets/referenced_list_item.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:shared_preferences/shared_preferences.dart';

News _news(int index, {String? source}) => News(
  id: '$index',
  title: 'Mock News Title $index',
  url: 'https://example.com/news/$index',
  author: 'Author',
  source: source ?? 'Mock Source',
  publishedAt: '2021-01-01',
  series: [],
);

class MockNewsService extends Fake implements NewsService {
  List<News> cached = [];
  Future<List<News>> Function()? response;

  @override
  Future<List<News>> getCachedNews() async => cached;

  @override
  Future<List<News>> fetchNews({int page = 1, int limit = 10}) async =>
      response != null ? response!() : [_news(1)];
}

void main() {
  late MockNewsService service;

  setUp(() async {
    await resetServiceLocator();
    SharedPreferences.setMockInitialValues({});
    service = MockNewsService();
    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<NewsService>(service);
  });

  Future<void> pumpNews(
    WidgetTester tester,
    ValueNotifier<MbPalette> palette,
  ) => tester.pumpWidget(
    ValueListenableBuilder<MbPalette>(
      valueListenable: palette,
      builder: (_, colors, _) => MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: colors),
        themeAnimationDuration: Duration.zero,
        home: const NewsScreen(),
      ),
    ),
  );

  testWidgets('NewsScreen renders news items from service', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NewsScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Mock News Title 1'), findsOneWidget);
    expect(find.textContaining('MOCK SOURCE'), findsOneWidget);
  });

  testWidgets('News cards and badge follow palettes with readable small text', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await pumpNews(tester, palette);
    await tester.pump();
    await tester.pump();
    for (final colors in [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      palette.value = colors;
      await tester.pump();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        colors.background,
      );
      expect(
        tester.widget<Card>(find.byType(Card).first).color,
        colors.surface,
      );
      final badge = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('MOCK SOURCE'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((badge.decoration! as BoxDecoration).color, colors.surfaceRaised);
      final source = tester.widget<Text>(find.text('MOCK SOURCE'));
      expect(
        MbPalette.contrastRatio(source.style!.color!, colors.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
      final date = tester.widget<Text>(find.text('Jan 1, 2021'));
      expect(
        MbPalette.contrastRatio(date.style!.color!, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.open_in_new_rounded));
      expect(
        MbPalette.contrastRatio(icon.color!, colors.surface),
        greaterThanOrEqualTo(3),
      );
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      expect(
        MbPalette.contrastRatio(refresh.color!, refresh.backgroundColor!),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('mounted News content and scroll state survive theme changes', (
    tester,
  ) async {
    service.response = () async => List.generate(20, _news);
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await pumpNews(tester, palette);
    await tester.pump();
    await tester.pump();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(600);
    await tester.pump();
    final before = scroll.position.pixels;
    final visibleIds = tester
        .widgetList<NewsListItem>(find.byType(NewsListItem))
        .map((item) => item.news.id)
        .toList();
    palette.value = EirenYuPalette.light;
    await tester.pump();
    expect(
      tester
          .widgetList<NewsListItem>(find.byType(NewsListItem))
          .map((item) => item.news.id)
          .toList(),
      visibleIds,
    );
    expect(scroll.position.pixels, before);
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.backgroundColor, palette.value.accent);
    expect(
      MbPalette.contrastRatio(fab.foregroundColor!, fab.backgroundColor!),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading and error states use visible palette colors', (
    tester,
  ) async {
    final pending = Completer<List<News>>();
    service.response = () => pending.future;
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await pumpNews(tester, palette);
    await tester.pump();
    for (final colors in [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      palette.value = colors;
      await tester.pump();
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator).first,
      );
      expect(
        MbPalette.contrastRatio(spinner.color!, colors.background),
        greaterThanOrEqualTo(3),
      );
    }
    pending.completeError(StateError('fixture failure'));
    await tester.pump();
    await tester.pump();
    final error = tester.widget<Text>(find.textContaining('Failed to load'));
    expect(
      MbPalette.contrastRatio(error.style!.color!, palette.value.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty News state remains readable', (tester) async {
    service.response = () async => [];
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.light);
    addTearDown(palette.dispose);
    await pumpNews(tester, palette);
    await tester.pump();
    await tester.pump();
    final empty = tester.widget<Text>(
      find.text(LocalizationService().translate('no_results')),
    );
    expect(
      MbPalette.contrastRatio(empty.style!.color!, palette.value.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('referenced series label follows the card palette', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    final series = Series.fromJson({'id': 'series-1', 'title': 'Series title'});
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Card(child: ReferencedListItem(series: series)),
          ),
        ),
      ),
    );
    for (final colors in [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      palette.value = colors;
      await tester.pump();
      final label = tester.widget<Text>(find.text('Series title'));
      expect(
        MbPalette.contrastRatio(label.style!.color!, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('News card fits narrow portrait and short landscape', (
    tester,
  ) async {
    service.response = () async => [
      _news(1, source: 'An unusually long publisher source name'),
    ];
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    for (final size in [const Size(280, 640), const Size(620, 300)]) {
      await tester.binding.setSurfaceSize(size);
      await pumpNews(tester, palette);
      await tester.pump();
      await tester.pump();
      expect(find.byType(NewsListItem), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
