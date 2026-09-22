import 'package:mangabaka_app/features/series/models/series.dart';

/// One of the user's top genres, from their taste profile.
///
/// [tagId] is what `/v2/series/search?tag=` takes; [affinity] orders the
/// genres (higher is a stronger fit) and is not shown to the user.
class TopGenre {
  final int tagId;
  final String name;
  final double affinity;

  const TopGenre({
    required this.tagId,
    required this.name,
    required this.affinity,
  });

  /// Parses an item of the `results` array. Null when the item is unusable,
  /// so one bad row does not drop the rest.
  static TopGenre? tryParse(Object? item) {
    if (item is! Map) return null;
    final id = item['tag_id'];
    final name = item['tag_name']?.toString() ?? '';
    if (id is! num || name.isEmpty) return null;
    return TopGenre(
      tagId: id.toInt(),
      name: name,
      affinity: (item['affinity_score'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// A "Top in {genre}" rail: the genre and its best-rated series.
class TopGenreRail {
  final TopGenre genre;
  final List<Series> series;

  const TopGenreRail(this.genre, this.series);
}
