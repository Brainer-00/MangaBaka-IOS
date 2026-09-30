import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';

/// Instant, local-DB backed autocomplete for the Library screen.
/// No network calls, no debounce — results are immediate.
class LibraryAutocompleteService {
  static const int maxResults = 6;

  LibraryAutocompleteIndex buildIndex(List<LibraryEntry> entries) =>
      LibraryAutocompleteIndex(entries);

  List<AutocompleteSeriesResult> search(
    String query,
    List<LibraryEntry> allEntries,
  ) => searchIndexed(query, buildIndex(allEntries));

  List<AutocompleteSeriesResult> searchIndexed(
    String query,
    LibraryAutocompleteIndex index,
  ) {
    if (query.trim().isEmpty) return [];

    final q = query.trim().toLowerCase();

    // Keep only the best six in the same order as the old full sort.
    final best = <_ScoredMatch>[];
    for (final item in index.items) {
      final score = _score(item, q);
      if (score == 0) continue;
      final match = _ScoredMatch(score: score, item: item);
      var position = best.length;
      for (var i = 0; i < best.length; i++) {
        if (_compare(match, best[i]) < 0) {
          position = i;
          break;
        }
      }
      if (position < maxResults) {
        best.insert(position, match);
        if (best.length > maxResults) best.removeLast();
      }
    }

    return best.map((match) {
      final series = match.item.entry.series;

      int? year;
      if (series.year.isNotEmpty) {
        year = int.tryParse(
          series.year.length >= 4 ? series.year.substring(0, 4) : series.year,
        );
      }

      final List<String> allTitles = [
        series.title,
        series.nativeTitle,
        series.romanizedTitle,
        ...series.secondaryTitles,
      ].where((t) => t.isNotEmpty).toSet().toList();

      return AutocompleteSeriesResult(
        id: int.tryParse(series.id) ?? 0,
        title: series.title,
        thumbnailUrl: series.coverUrl,
        type: series.type,
        year: year,
        genres: series.genres.take(3).toList(),
        allTitles: allTitles,
        contentRating: series.contentRating,
      );
    }).toList();
  }

  int _score(IndexedLibraryEntry item, String query) {
    if (item.title.startsWith(query)) {
      return 100;
    }
    if (item.native.startsWith(query) || item.romanized.startsWith(query)) {
      return 90;
    }
    if (item.secondary.any((title) => title.startsWith(query))) {
      return 80;
    }
    if (item.title.contains(query)) {
      return 50;
    }
    if (item.native.contains(query) || item.romanized.contains(query)) {
      return 40;
    }
    if (item.secondary.any((title) => title.contains(query))) {
      return 30;
    }
    return 0;
  }

  int _compare(_ScoredMatch a, _ScoredMatch b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    return a.item.entry.series.title.length.compareTo(
      b.item.entry.series.title.length,
    );
  }
}

class LibraryAutocompleteIndex {
  final List<IndexedLibraryEntry> items;

  const LibraryAutocompleteIndex.empty() : items = const [];

  LibraryAutocompleteIndex(List<LibraryEntry> entries)
    : items = List.unmodifiable(entries.map(IndexedLibraryEntry.new));
}

class IndexedLibraryEntry {
  final LibraryEntry entry;
  final String title;
  final String native;
  final String romanized;
  final List<String> secondary;

  IndexedLibraryEntry(this.entry)
    : title = entry.series.title.toLowerCase(),
      native = entry.series.nativeTitle.toLowerCase(),
      romanized = entry.series.romanizedTitle.toLowerCase(),
      secondary = List.unmodifiable(
        entry.series.secondaryTitles.map((title) => title.toLowerCase()),
      );
}

class _ScoredMatch {
  final int score;
  final IndexedLibraryEntry item;
  _ScoredMatch({required this.score, required this.item});
}
