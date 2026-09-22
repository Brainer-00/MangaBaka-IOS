import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/utils/content_rating_filter.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/home/models/top_genre_rail.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';

void main() {
  group('TopGenre.tryParse', () {
    test('reads a results item', () {
      final g = TopGenre.tryParse(
        {'tag_id': 12, 'tag_name': 'Romance', 'affinity_score': 0.83},
      )!;
      expect(g.tagId, 12);
      expect(g.name, 'Romance');
      expect(g.affinity, closeTo(0.83, 1e-9));
    });

    test('rejects unusable items rather than throwing', () {
      expect(TopGenre.tryParse('nope'), isNull);
      expect(TopGenre.tryParse({'tag_name': 'x'}), isNull);
      expect(TopGenre.tryParse({'tag_id': 1, 'tag_name': ''}), isNull);
    });
  });

  group('ContentRatingFilter.excluded', () {
    test('is the ratings the user has not allowed', () {
      expect(
        ContentRatingFilter.excluded(['safe', 'suggestive']),
        ['erotica', 'pornographic'],
      );
    });

    test('excludes nothing when there is no preference or all are allowed', () {
      expect(ContentRatingFilter.excluded(const []), isEmpty);
      expect(ContentRatingFilter.excluded(ContentRatingFilter.all), isEmpty);
    });
  });

  group('SearchFilters.hasAnime', () {
    test('is sent to the API, counted, and survives other edits', () {
      final f = SearchFilters().copyWithHasAnime(true);
      expect(f.toMap()['has_anime'], true);
      expect(f.isEmpty, isFalse);
      expect(f.activeFiltersCount, 1);

      expect(f.copyWithSortBy('score_desc').hasAnime, true);
      expect(f.copyWithIsLicensed(true).hasAnime, true);
      expect(f.copyWithYear(publishedYearLower: 2000).hasAnime, true);
      expect(f.copyWithHasAnime(null).toMap().containsKey('has_anime'), false);
    });

    test('false is a real value, not "unset"', () {
      expect(SearchFilters().copyWithHasAnime(false).toMap()['has_anime'], false);
    });
  });

  test('SeriesCollection reads the ids the collection screen needs', () {
    final c = SeriesCollection.fromJson({
      'id': 'abc',
      'series_id': 222,
      'title': 'T',
      'publisher': {'id': 246, 'name': 'Panini'},
      'edition': {'name': 'Standard Edition'},
      'language': {'iso': 'es-la', 'language': 'Spanish'},
      'count_main': 16,
    });
    expect(c.seriesId, '222');
    expect(c.publisherId, '246');
    expect(c.editionName, 'Standard Edition');
    expect(c.languageName, 'Spanish');
  });
}
