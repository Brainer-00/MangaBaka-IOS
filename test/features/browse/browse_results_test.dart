import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/browse/controllers/browse_results.dart';
import 'package:mangabaka_app/features/browse/services/browse_search_gateway.dart';
import 'package:mangabaka_app/features/publisher/models/publisher.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

Series _series(String id) => Series.fromJson({'id': id, 'title': id});

Publisher _publisher(String id) => Publisher(
  id: id,
  type: 'publisher',
  subType: '',
  aliases: const [],
  name: id,
);

void main() {
  test('appends many series pages in order without exposing mutation', () {
    final results = BrowseResults();

    for (var page = 0; page < 50; page++) {
      results.addSeries(
        BrowsePage(
          items: [for (var item = 0; item < 20; item++) _series('$page-$item')],
          total: 1000,
          hasMore: page < 49,
        ),
      );
    }

    expect(results.series, hasLength(1000));
    expect(results.series.first.id, '0-0');
    expect(results.series.last.id, '49-19');
    expect(() => results.series.clear(), throwsUnsupportedError);
    expect(results.series, hasLength(1000));
  });

  test('refresh clear resets accumulated series and publishers', () {
    final results = BrowseResults();
    results.addSeries(
      BrowsePage(items: [_series('old')], total: 1, hasMore: false),
    );
    results.addPublishers(
      BrowsePage(items: [_publisher('old')], total: 1, hasMore: false),
    );

    results.clear();

    expect(results.series, isEmpty);
    expect(results.publishers, isEmpty);
    expect(results.page, 1);
    expect(results.hasMore, isTrue);
  });

  test('empty pages do not alter accumulated ordering', () {
    final results = BrowseResults();
    results.addSeries(
      BrowsePage(items: [_series('one')], total: 1, hasMore: true),
    );
    results.addSeries(
      const BrowsePage<Series>(items: [], total: 1, hasMore: false),
    );

    expect(results.series.map((series) => series.id), ['one']);
    expect(results.hasMore, isFalse);
  });
}
