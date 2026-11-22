import 'package:mangabaka_app/features/series/models/series.dart';

class LibraryEntry {
  final String id;
  final String state;
  final String? note;
  final int? progressChapter;
  final int? progressVolume;
  final int? numberOfRereads;
  final int? rating;
  final double? priority;
  final String? startDate;
  final String? finishDate;
  final String? readLink;
  final bool? isPrivate;

  /// Null means membership is unknown. An empty list is a confirmed absence
  /// of memberships. IDs belong to the account that supplied the entry.
  final List<int>? listIds;
  final String? updatedAt;
  final String? createdAt;
  final Series series;
  final Set<String> _explicitNullFields;

  LibraryEntry({
    required this.id,
    required this.state,
    this.note,
    this.progressChapter,
    this.progressVolume,
    this.numberOfRereads,
    this.rating,
    this.priority,
    String? startDate,
    String? finishDate,
    this.readLink,
    this.isPrivate,
    List<int>? listIds,
    this.updatedAt,
    this.createdAt,
    required this.series,
    Set<String> explicitNullFields = const {},
  }) : startDate = _calendarDay(startDate),
       finishDate = _calendarDay(finishDate),
       listIds = listIds == null ? null : List.unmodifiable(listIds),
       _explicitNullFields = Set.unmodifiable(explicitNullFields);

  /// A nullable JSON property can be present even when its value is null.
  /// Programmatically constructed entries omit optional nulls by default.
  bool explicitlyClears(String apiKey) => _explicitNullFields.contains(apiKey);

  /// Parses an item from the v1 library page, with its embedded series.
  /// That endpoint does not supply authoritative list membership.
  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    final rawSeries = json['Series'] ?? json['series'];
    if (rawSeries is! Map<String, dynamic>) {
      throw FormatException('Library entry missing Series payload');
    }

    return LibraryEntry(
      id: json['id']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      note: json['note']?.toString(),
      progressChapter: (json['progress_chapter'] as num?)?.toInt(),
      progressVolume: (json['progress_volume'] as num?)?.toInt(),
      numberOfRereads: (json['number_of_rereads'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toInt(),
      priority: (json['priority'] as num?)?.toDouble(),
      startDate: json['start_date'] as String?,
      finishDate: json['finish_date'] as String?,
      readLink: json['read_link'] as String?,
      isPrivate: json['is_private'] as bool?,
      updatedAt: json['updated_at']?.toString(),
      createdAt: json['created_at']?.toString(),
      series: Series.fromJson(rawSeries),
      explicitNullFields: {
        for (final field in json.entries)
          if (field.value == null) field.key,
      },
    );
  }

  static String? _calendarDay(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})(?:T.*)?$').firstMatch(value);
    final day = match?.group(1);
    final date = day == null ? null : DateTime.tryParse('${day}T00:00:00Z');
    if (date == null || date.toIso8601String().substring(0, 10) != day) {
      throw const FormatException('Invalid library calendar date');
    }
    return day;
  }
}
