import 'dart:convert';
import 'package:mangabaka_app/core/database/database.dart' as db;
import 'package:mangabaka_app/features/library/models/library_entry.dart'
    as api;
import 'package:mangabaka_app/features/series/models/series.dart' as api;

class DbToApiMapper {
  static List<int>? _decodeListIds(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List || decoded.any((id) => id is! int || id <= 0)) {
        return null;
      }
      return decoded.cast<int>();
    } on FormatException {
      return null;
    }
  }
  // ── JSON decode helpers ───────────────────────────────────────────────────

  static List<String> _decodeStringArray(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }

  static Map<String, dynamic>? _decodeJsonObject(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  static List<dynamic> _decodeList(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) return decoded;
    } catch (_) {}
    return [];
  }

  // ── Mapping ───────────────────────────────────────────────────────────────

  static api.LibraryEntry libraryEntryFromDb(
    db.LibraryEntryWithSeries dbEntry,
  ) {
    return api.LibraryEntry(
      id: dbEntry.libraryEntry.id,
      state: dbEntry.libraryEntry.state,
      note: dbEntry.libraryEntry.note,
      progressChapter: dbEntry.libraryEntry.progressChapter,
      progressVolume: dbEntry.libraryEntry.progressVolume,
      numberOfRereads: dbEntry.libraryEntry.numberOfRereads,
      rating: dbEntry.libraryEntry.rating,
      priority: dbEntry.libraryEntry.priority,
      startDate: dbEntry.libraryEntry.startDate,
      finishDate: dbEntry.libraryEntry.finishDate,
      readLink: dbEntry.libraryEntry.readLink,
      isPrivate: dbEntry.libraryEntry.isPrivate,
      listIds: _decodeListIds(dbEntry.libraryEntry.listIdsJson),
      series: seriesFromDb(dbEntry.series),
    );
  }

  static api.Series seriesFromDb(db.SeriesTableData dbSeries) {
    final source = _decodeJsonObject(dbSeries.source);

    // Calculate combined average if source data is available
    String rating = dbSeries.rating ?? '';
    if (source != null && source.isNotEmpty) {
      final normalizedRatings = source.values
          .where((v) => v is Map && v['rating_normalized'] != null)
          .map((v) => (v['rating_normalized'] as num).toDouble())
          .toList();
      if (normalizedRatings.isNotEmpty) {
        final avg =
            normalizedRatings.reduce((a, b) => a + b) /
            normalizedRatings.length;
        rating = avg.toStringAsFixed(1);
      }
    }

    return api.Series(
      id: dbSeries.id,
      state: dbSeries.state ?? '',
      mergedWith: dbSeries.mergedWith,
      title: dbSeries.title,
      nativeTitle: dbSeries.nativeTitle ?? '',
      romanizedTitle: dbSeries.romanizedTitle ?? '',
      secondaryTitles: _decodeStringArray(dbSeries.secondaryTitles),
      coverUrl: dbSeries.coverUrl,
      rawCoverUrl: dbSeries.coverUrl,
      authors: _decodeStringArray(dbSeries.authors),
      artists: _decodeStringArray(dbSeries.artists),
      description: dbSeries.description,
      year: dbSeries.year ?? '',
      published: _decodeJsonObject(dbSeries.published),
      status: dbSeries.status ?? '',
      isLicensed: dbSeries.isLicensed ?? '',
      hasAnime: dbSeries.hasAnime ?? '',
      anime: _decodeJsonObject(dbSeries.anime),
      contentRating: dbSeries.contentRating ?? '',
      type: dbSeries.type ?? '',
      rating: rating,
      finalVolume: dbSeries.finalVolume ?? '',
      totalChapters: dbSeries.totalChapters ?? '',
      links: _decodeList(dbSeries.links),
      publishers: _decodeStringArray(dbSeries.publishers),
      genres: _decodeStringArray(dbSeries.genres),
      tags: _decodeStringArray(dbSeries.tags),
      lastUpdated: dbSeries.lastUpdated ?? '',
      relationships: _decodeJsonObject(dbSeries.relationships),
      source: source,
    );
  }
}
