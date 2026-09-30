import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/library/helpers/library_filter_helper.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';

void main() {
  group('LibraryFilterHelper', () {
    final mockSeries = Series(
      id: '1',
      title: 'One Piece',
      state: 'reading',
      nativeTitle: '',
      romanizedTitle: '',
      secondaryTitles: [],
      coverUrl: '',
      rawCoverUrl: '',
      authors: [],
      artists: [],
      description: '',
      year: '1997',
      status: 'ongoing',
      isLicensed: 'yes',
      hasAnime: 'yes',
      contentRating: 'safe',
      type: 'manga',
      rating: '95',
      finalVolume: '',
      totalChapters: '1000',
      links: [],
      publishers: [],
      genres: ['Action', 'Adventure'],
      tags: [],
      lastUpdated: '',
    );

    final mockEntry = LibraryEntry(
      id: '1',
      state: 'reading',
      rating: 10,
      series: mockSeries,
    );

    test('filters by query correctly', () {
      final helper = LibraryFilterHelper(
        allEntries: [mockEntry],
        query: 'Piece',
        contentPreferences: ['safe'],
      );

      final result = helper.getFilteredAndSorted();
      expect(result, hasLength(1));

      final helperNoMatch = LibraryFilterHelper(
        allEntries: [mockEntry],
        query: 'Naruto',
        contentPreferences: ['safe'],
      );
      expect(helperNoMatch.getFilteredAndSorted(), isEmpty);
    });

    test('filters by tab (state) correctly', () {
      final helper = LibraryFilterHelper(
        allEntries: [mockEntry],
        query: '',
        contentPreferences: ['safe'],
      );

      expect(helper.getByTab('reading'), hasLength(1));
      expect(helper.getByTab('completed'), isEmpty);
    });

    test('filters by content rating correctly', () {
      final helper = LibraryFilterHelper(
        allEntries: [mockEntry],
        query: '',
        contentPreferences: ['erotica'], // Only erotica
      );

      expect(helper.getFilteredAndSorted(), isEmpty);
    });

    test('filters by status correctly using SearchFilters', () {
      final helper = LibraryFilterHelper(
        allEntries: [mockEntry],
        query: '',
        contentPreferences: ['safe'],
        filters: SearchFilters(status: ['ongoing']),
      );

      expect(helper.getFilteredAndSorted(), hasLength(1));

      final helperNoMatch = LibraryFilterHelper(
        allEntries: [mockEntry],
        query: '',
        contentPreferences: ['safe'],
        filters: SearchFilters(status: ['completed']),
      );
      expect(helperNoMatch.getFilteredAndSorted(), isEmpty);
    });

    test('derives tab partitions and counts from one filtered result', () {
      final entries = [
        mockEntry,
        LibraryEntry(id: '2', state: 'completed', series: mockSeries),
        LibraryEntry(id: '3', state: 'unknown', series: mockSeries),
      ];
      final helper = LibraryFilterHelper(
        allEntries: entries,
        query: '',
        contentPreferences: ['safe'],
      );

      expect(helper.result.filtered, hasLength(3));
      expect(helper.getByTab('reading'), hasLength(2));
      expect(helper.getByTab('completed'), hasLength(1));
      expect(helper.counts, {'reading': 1, 'completed': 1, 'unknown': 1});
      expect(helper.getByTab('reading'), same(helper.getByTab('reading')));
    });

    test('preserves every supported sort mode without changing membership', () {
      const sortModes = [
        'random',
        'name_asc',
        'name_desc',
        'popularity_desc',
        'rating_desc',
        'score_desc',
        'popularity_asc',
        'rating_asc',
        'score_asc',
        'last_updated',
        'created_at',
        'updated_at',
        'chapters_desc',
        'chapters_asc',
        'unread_desc',
        'unread_asc',
      ];
      for (final sortBy in sortModes) {
        final helper = LibraryFilterHelper(
          allEntries: [mockEntry],
          query: '',
          contentPreferences: ['safe'],
          filters: SearchFilters(sortBy: sortBy),
        );
        expect(helper.getFilteredAndSorted(), hasLength(1), reason: sortBy);
      }
    });
  });
}
