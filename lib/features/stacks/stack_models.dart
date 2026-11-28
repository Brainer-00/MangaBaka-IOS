import '../series/models/series.dart';

typedef StackJson = Map<String, dynamic>;

enum StackSection {
  created(''),
  saved('/saved'),
  following('/followed');

  const StackSection(this.path);
  final String path;
}

enum StackVisibility { draft, unlisted, public }

enum StackRating { safe, suggestive, erotica, pornographic }

enum StackRelationship { none, saved, following }

enum StackAction {
  save('saved', 'PUT'),
  unsave('saved', 'DELETE'),
  follow('followed', 'PUT'),
  unfollow('followed', 'DELETE'),
  vote('votes', 'PUT'),
  unvote('votes', 'DELETE');

  const StackAction(this.path, this.method);
  final String path;
  final String method;

  bool matches(StackViewer state) => switch (this) {
    save => state.saved,
    unsave => !state.saved,
    follow => state.followed,
    unfollow => !state.followed,
    vote => state.voted,
    unvote => !state.voted,
  };
}

final class StackViewer {
  const StackViewer({
    required this.id,
    required this.relationship,
    required this.voted,
    required this.saveCount,
    required this.followCount,
    required this.voteCount,
    required this.libraryCount,
  });

  factory StackViewer.fromJson(StackJson json) {
    final saved = json['has_saved'] as bool;
    final followed = json['has_followed'] as bool;
    if (followed && !saved) {
      throw const FormatException('Invalid Stack relationship');
    }
    return StackViewer(
      id: stackId(json['id']),
      relationship: followed
          ? StackRelationship.following
          : saved
          ? StackRelationship.saved
          : StackRelationship.none,
      voted: json['has_voted'] as bool,
      saveCount: stackCount(json['save_count']),
      followCount: stackCount(json['follow_count']),
      voteCount: stackCount(json['vote_count']),
      libraryCount: json['library_count'] == null
          ? null
          : stackCount(json['library_count']),
    );
  }

  final int id;
  final StackRelationship relationship;
  final bool voted;
  final int saveCount;
  final int followCount;
  final int voteCount;
  final int? libraryCount;

  bool get saved => relationship != StackRelationship.none;
  bool get followed => relationship == StackRelationship.following;
}

final class StackCover {
  const StackCover(this.seriesId, this.url);

  factory StackCover.fromJson(StackJson json) {
    final cover = json['cover'] as StackJson;
    return StackCover(
      stackId(json['series_id']),
      (cover['x250'] ?? cover['x150'] ?? cover['x350']) as String?,
    );
  }

  final int seriesId;
  final String? url;
}

final class StackSummary {
  StackSummary.fromJson(StackJson json)
    : id = stackId(json['id']),
      title = json['title'] as String,
      ownerId = (json['owner'] as StackJson)['id'] as String,
      ownerName = (json['owner'] as StackJson)['name'] as String,
      visibility = StackVisibility.values.byName(json['visibility'] as String),
      rating = StackRating.values.byName(json['content_rating'] as String),
      spoiler = json['is_spoiler'] as bool,
      entryCount = stackCount(json['entry_count']),
      saveCount = stackCount(json['save_count']),
      voteCount = stackCount(json['vote_count']),
      covers = List.unmodifiable(
        (json['covers'] as List).cast<StackJson>().map(StackCover.fromJson),
      );

  final int id;
  final String title;
  final String ownerId;
  final String ownerName;
  final StackVisibility visibility;
  final StackRating rating;
  final bool spoiler;
  final int entryCount;
  final int saveCount;
  final int voteCount;
  final List<StackCover> covers;
}

final class StackEntry {
  const StackEntry(this.id, {this.series, this.note, this.available = true});

  factory StackEntry.fromJson(StackJson json) {
    final id = stackId(json['series_id']);
    final seriesJson = json['series'] as StackJson?;
    if (!json.containsKey('note') ||
        !json.containsKey('series') ||
        !json.containsKey('issue') ||
        (seriesJson != null && stackId(seriesJson['id']) != id)) {
      throw const FormatException('Incomplete Stack entry');
    }
    return StackEntry(
      id,
      series: seriesJson == null ? null : Series.fromJson(seriesJson),
      note: json['note'] as String?,
      available: json['issue'] == null && seriesJson?['state'] == 'active',
    );
  }

  final int id;
  final Series? series;
  final String? note;
  final bool available;

  StackEntry withNote(String? note) =>
      StackEntry(id, series: series, note: note, available: available);

  StackJson toJson() => {'series_id': id, 'note': note};
}

final class StackDetail {
  StackDetail.fromJson(StackJson json, {required bool owned})
    : summary = StackSummary.fromJson(json),
      description = json['description'] as String?,
      comments = json['is_comments_enabled'] as bool,
      revision = owned ? json['token'] as String : null,
      spoilerLocked = owned && (json['is_spoiler_locked'] as bool),
      minRating = owned && json['min_content_rating'] != null
          ? StackRating.values.byName(json['min_content_rating'] as String)
          : null,
      entries = List.unmodifiable(
        (json['entries'] as List).cast<StackJson>().map(StackEntry.fromJson),
      ) {
    if (!json.containsKey('description') ||
        entries.length != summary.entryCount ||
        entries.map((entry) => entry.id).toSet().length != entries.length ||
        (owned &&
            (revision!.isEmpty || !json.containsKey('min_content_rating')))) {
      throw const FormatException('Incomplete Stack detail');
    }
  }

  final StackSummary summary;
  final String? description;
  final bool comments;
  final String? revision;
  final bool spoilerLocked;
  final StackRating? minRating;
  final List<StackEntry> entries;
}

final class StackDraft {
  StackDraft.fromDetail(StackDetail detail)
    : base = detail,
      title = detail.summary.title,
      description = detail.description,
      visibility = detail.summary.visibility,
      rating = detail.summary.rating,
      spoiler = detail.summary.spoiler,
      comments = detail.comments,
      entries = [...detail.entries];

  static const maxEntries = 100;
  static const minPublishedEntries = 5;
  final StackDetail base;
  String title;
  String? description;
  StackVisibility visibility;
  StackRating rating;
  bool spoiler;
  bool comments;
  final List<StackEntry> entries;

  String? get validationError {
    if (title.trim().isEmpty || title.trim().runes.length > 200) {
      return 'stack_title_limit';
    }
    if ((description?.runes.length ?? 0) > 10000 ||
        entries.any((entry) => (entry.note?.runes.length ?? 0) > 5000)) {
      return 'stack_markdown_limit';
    }
    if (entries.length > maxEntries ||
        entries.map((entry) => entry.id).toSet().length != entries.length) {
      return 'stack_entry_limit';
    }
    if (visibility != StackVisibility.draft &&
        entries.where((entry) => entry.available).length <
            minPublishedEntries) {
      return 'stack_publication_minimum';
    }
    final minimum = base.minRating;
    final higherRated = entries.where((entry) {
      final name = entry.series?.contentRating;
      return StackRating.values.any(
        (candidate) => candidate.name == name && candidate.index > rating.index,
      );
    }).length;
    if ((minimum != null && rating.index < minimum.index) ||
        higherRated * 10 > entries.length) {
      return 'stack_rating_limit';
    }
    if (base.spoilerLocked && spoiler != base.summary.spoiler) {
      return 'stack_spoiler_locked';
    }
    return null;
  }

  StackJson toJson() => {
    'title': title.trim(),
    'description': description,
    'visibility': visibility.name,
    'content_rating': rating.name,
    'is_spoiler': spoiler,
    'is_comments_enabled': comments,
    'token': base.revision,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  bool matches(StackDetail detail) =>
      detail.summary.title == title.trim() &&
      detail.description == description &&
      detail.summary.visibility == visibility &&
      detail.summary.rating == rating &&
      detail.summary.spoiler == spoiler &&
      detail.comments == comments &&
      detail.entries.length == entries.length &&
      entries.indexed.every((item) {
        final actual = detail.entries[item.$1];
        return actual.id == item.$2.id && actual.note == item.$2.note;
      });
}

int stackId(Object? value) {
  if (value is! int || value < 1 || value > 2147483647) {
    throw const FormatException('Invalid Stack or series ID');
  }
  return value;
}

int stackCount(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value % 1 != 0) {
    throw const FormatException('Invalid Stack count');
  }
  return value.toInt();
}
