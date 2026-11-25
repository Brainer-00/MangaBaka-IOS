import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';

class EntryField<T> {
  const EntryField.omitted() : supplied = false, value = null;
  const EntryField.set(this.value) : supplied = true;

  final bool supplied;
  final T? value;
}

class LibraryEntryDraft {
  LibraryEntryDraft({
    required this.lease,
    required this.seriesId,
    this.state = const EntryField.omitted(),
    this.priority = const EntryField.omitted(),
    this.startDate = const EntryField.omitted(),
    this.finishDate = const EntryField.omitted(),
    this.progressChapter = const EntryField.omitted(),
    this.progressVolume = const EntryField.omitted(),
    this.numberOfRereads = const EntryField.omitted(),
    this.readLink = const EntryField.omitted(),
    this.isPrivate = const EntryField.omitted(),
    this.rating = const EntryField.omitted(),
    this.note = const EntryField.omitted(),
    EntryField<List<int>> lists = const EntryField.omitted(),
  }) : lists = lists.value == null
           ? lists
           : EntryField.set(List.unmodifiable(lists.value!));

  final LibraryCacheLease lease;
  final String seriesId;
  final EntryField<String> state, startDate, finishDate, readLink, note;
  final EntryField<num> priority;
  final EntryField<int> progressChapter,
      progressVolume,
      numberOfRereads,
      rating;
  final EntryField<bool> isPrivate;
  final EntryField<List<int>> lists;

  static const states = {
    'considering',
    'completed',
    'dropped',
    'paused',
    'plan_to_read',
    'reading',
    'rereading',
  };

  Map<String, Object?> toJson() {
    final fields = <String, EntryField<Object>>{
      'state': state,
      'priority': priority,
      'start_date': startDate,
      'finish_date': finishDate,
      'progress_chapter': progressChapter,
      'progress_volume': progressVolume,
      'number_of_rereads': numberOfRereads,
      'read_link': readLink,
      'is_private': isPrivate,
      'rating': rating,
      'note': note,
      'lists': lists,
    };
    final payload = <String, Object?>{
      for (final field in fields.entries)
        if (field.value.supplied) field.key: field.value.value,
    };
    void validate(bool valid, String field) {
      if (!valid) throw ArgumentError('Invalid Library field: $field');
    }

    if (state.supplied) validate(states.contains(state.value), 'state');
    if (isPrivate.supplied) validate(isPrivate.value != null, 'is_private');
    for (final (key, min, max) in <(String, int, int)>[
      ('priority', 10, 30),
      ('rating', 0, 100),
      ('number_of_rereads', 0, 1000),
      ('progress_chapter', 0, 10000),
      ('progress_volume', 0, 10000),
    ]) {
      final value = payload[key] as num?;
      if (value != null) {
        validate(value.isFinite && value >= min && value <= max, key);
      } else if (key == 'priority' && priority.supplied) {
        validate(false, key);
      }
    }
    for (final key in ['start_date', 'finish_date']) {
      final value = payload[key] as String?;
      if (value == null) continue;
      final date = DateTime.tryParse('${value}T00:00:00Z');
      validate(
        date != null &&
            date.toIso8601String().substring(0, 10) == value &&
            value.compareTo('1679-01-01') >= 0 &&
            value.compareTo('2262-12-31') <= 0,
        key,
      );
    }
    final link = readLink.value;
    if (link != null) {
      validate(Uri.tryParse(link)?.isAbsolute == true, 'read_link');
    }
    if (lists.supplied) {
      final ids = lists.value;
      validate(
        ids != null &&
            ids.length <= 30 &&
            ids.every((id) => id > 0 && id <= 2147483647),
        'lists',
      );
    }
    return payload;
  }
}

class AccountLibraryList {
  const AccountLibraryList({
    required this.id,
    required this.name,
    required this.isPrivate,
  });
  final int id;
  final String name;
  final bool isPrivate;
}

enum LibrarySaveOutcome { saved, refreshPending, uncertain }

class LibrarySaveResult {
  const LibrarySaveResult(this.outcome, {this.entry});
  final LibrarySaveOutcome outcome;
  final LibraryEntry? entry;
}
