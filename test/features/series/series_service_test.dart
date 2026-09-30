import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/network/api_client.dart';
import 'package:mangabaka_app/features/series/services/series_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

class _TestSeriesService extends SeriesService {
  _TestSeriesService(this._api);

  final ApiClient _api;

  @override
  ApiClient get seriesApi => _api;
}

Series _series(String id, {String? title}) => Series(
  id: id,
  title: title ?? 'Series $id',
  state: '',
  nativeTitle: '',
  romanizedTitle: '',
  secondaryTitles: const [],
  coverUrl: '',
  rawCoverUrl: '',
  authors: const [],
  artists: const [],
  description: '',
  year: '',
  status: '',
  isLicensed: '',
  hasAnime: '',
  contentRating: 'safe',
  type: '',
  rating: '',
  finalVolume: '',
  totalChapters: '',
  links: const [],
  publishers: const [],
  genres: const [],
  tags: const [],
  lastUpdated: '',
);

void main() {
  group('SeriesService', () {
    late SeriesService seriesService;

    setUp(() {
      seriesService = SeriesService();
    });

    test('precacheSeries stores series in cache', () async {
      final series = _series('1', title: 'Test Series');

      seriesService.precacheSeries(series);

      final result = await seriesService.fetchSeries('1');
      expect(result, series);
      expect(result.title, 'Test Series');
    });

    test('precacheSeries keeps the FIFO cache bounded at 200 entries', () {
      for (var i = 0; i < 250; i++) {
        seriesService.precacheSeries(_series('$i'));
      }

      expect(seriesService.cache, hasLength(200));
      expect(seriesService.cache.containsKey('49'), isFalse);
      expect(seriesService.cache.containsKey('50'), isTrue);
      expect(seriesService.cache['249']?.title, 'Series 249');
    });

    test(
      'recently precached values remain cache hits after FIFO eviction',
      () async {
        for (var i = 0; i < 201; i++) {
          seriesService.precacheSeries(_series('$i'));
        }

        expect(
          await seriesService.fetchSeries('200'),
          same(seriesService.cache['200']),
        );
        expect(seriesService.cache, hasLength(200));
        expect(seriesService.cache.containsKey('0'), isFalse);
      },
    );

    test(
      'normal fetches remain cached through the bounded insertion path',
      () async {
        var requests = 0;
        final api = ApiClient(
          client: MockClient((request) async {
            requests++;
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 'remote',
                  'title': 'Remote Series',
                  'content_rating': 'safe',
                },
              }),
              200,
            );
          }),
        );
        final service = _TestSeriesService(api);

        final first = await service.fetchSeries('remote');
        final second = await service.fetchSeries('remote');

        expect(first.title, 'Remote Series');
        expect(second, same(first));
        expect(requests, 1);
        expect(service.cache, hasLength(1));
        api.close();
      },
    );
  });
}
