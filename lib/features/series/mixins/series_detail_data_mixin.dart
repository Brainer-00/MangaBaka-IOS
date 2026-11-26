import 'package:flutter/material.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/models/series_cover.dart';
import 'package:mangabaka_app/features/news/models/news.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';
import 'package:mangabaka_app/features/series/models/series_work.dart';
import 'package:mangabaka_app/features/series/models/series_link.dart';
import 'package:mangabaka_app/features/series/services/series_service.dart';

mixin SeriesDetailDataMixin<T extends StatefulWidget> on State<T> {
  SeriesService get seriesService;
  Series get series;
  String get selectedTab;

  List<SeriesCover>? covers;
  List<Series>? related;
  List<Series>? similar;
  List<Series>? readersAlsoLike;
  List<News>? news;
  List<SeriesCollection>? collections;
  List<SeriesWork>? works;

  List<SeriesLink>? enrichedLinks;
  Series? fullSeries;
  bool isDataLoaded = false;
  bool fetchError = false;

  /// Hook the host screen can override to hold freshly-fetched data until it is
  /// safe to rebuild — e.g. until the route push transition has finished — so a
  /// mid-transition `setState` never drops frames. Defaults to no delay.
  @protected
  Future<void> whenReadyToApplyData() async {}

  final _tabLoads = <String, Future<bool>>{};
  int _metadataGeneration = 0;

  Future<bool> fetchTabData(String tab, {bool refresh = false}) {
    final active = _tabLoads[tab];
    if (!refresh && active != null) return active;
    late final Future<bool> request;
    request = Future<bool>.microtask(() async {
      bool current() => mounted && identical(_tabLoads[tab], request);
      Future<void> load<Item>(
        List<Item>? cached,
        Future<List<Item>> Function(String, {bool refresh}) fetch,
        void Function(List<Item>) apply,
      ) async {
        if (!refresh && cached != null) return;
        final data = await fetch(series.id, refresh: refresh);
        if (current()) setState(() => apply(data));
      }

      try {
        switch (tab) {
          case 'Covers':
            await load(
              covers,
              seriesService.fetchSeriesCovers,
              (data) => covers = data,
            );
          case 'Related':
            await load(
              related,
              seriesService.fetchSeriesRelated,
              (data) => related = data,
            );
          case 'News':
            await load(
              news,
              seriesService.fetchSeriesNews,
              (data) => news = data,
            );
          case 'Collections':
            await load(
              collections,
              seriesService.fetchSeriesCollections,
              (data) => collections = data,
            );
          case 'Works':
            await load(
              works,
              seriesService.fetchSeriesWorks,
              (data) => works = data,
            );
          case 'Similar':
            await Future.wait([
              load(
                readersAlsoLike,
                seriesService.fetchSeriesReadersAlsoLike,
                (data) => readersAlsoLike = data,
              ),
              load(
                similar,
                seriesService.fetchSeriesSimilar,
                (data) => similar = data,
              ),
            ]);
        }
        return true;
      } catch (e) {
        seriesService.logger.warning(
          'Error fetching tab "$tab" data (${e.runtimeType})',
        );
        if (current() && !refresh) setState(() => fetchError = true);
        return false;
      } finally {
        if (current()) _tabLoads.remove(tab);
      }
    });
    return _tabLoads[tab] = request;
  }

  Future<void> fetchFullData({bool refresh = false}) async {
    final generation = ++_metadataGeneration;
    final tab = fetchTabData(selectedTab, refresh: refresh);
    var metadataFailed = false;
    try {
      final results = await (
        seriesService.fetchSeriesLinks(series.id, refresh: refresh),
        seriesService.fetchSeries(series.id, refresh: refresh),
      ).wait;
      await whenReadyToApplyData();
      if (mounted && generation == _metadataGeneration) {
        setState(() {
          enrichedLinks = results.$1;
          fullSeries = results.$2;
          isDataLoaded = true;
        });
      }
    } catch (e) {
      metadataFailed = true;
      seriesService.logger.warning(
        'Error fetching full data (${e.runtimeType})',
      );
    }
    final tabFailed = !await tab;
    await whenReadyToApplyData();
    if (mounted && generation == _metadataGeneration) {
      setState(() {
        isDataLoaded = true;
        fetchError = metadataFailed || tabFailed;
      });
    }
  }
}
