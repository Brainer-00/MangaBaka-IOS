import 'package:drift/drift.dart';
import 'series_table.dart';

mixin LibraryEntryColumns on Table {
  TextColumn get id => text()();
  TextColumn get state => text()();
  TextColumn get note => text().nullable()();
  IntColumn get progressChapter => integer().nullable()();
  IntColumn get progressVolume => integer().nullable()();
  IntColumn get numberOfRereads => integer().nullable()();
  IntColumn get rating => integer().nullable()();
  RealColumn get priority => real().nullable()();
  TextColumn get startDate => text().nullable()();
  TextColumn get finishDate => text().nullable()();
  TextColumn get readLink => text().nullable()();
  BoolColumn get isPrivate => boolean().nullable()();

  /// Account-specific list IDs encoded as JSON. SQL NULL means unknown; '[]'
  /// means the server confirmed that the entry belongs to no lists.
  TextColumn get listIdsJson => text().nullable()();
}

/// Temporary ownerless storage used by the existing application readers.
/// Owned cache operations never read or promote these rows.
class LibraryEntriesTable extends Table with LibraryEntryColumns {
  TextColumn get seriesId => text().references(SeriesTable, #id)();

  @override
  Set<Column> get primaryKey => {id};

  List<Index> get indexes => [
    Index(
      'library_series_idx',
      'CREATE INDEX IF NOT EXISTS library_series_idx ON library_entries_table (series_id)',
    ),
    Index(
      'library_state_idx',
      'CREATE INDEX IF NOT EXISTS library_state_idx ON library_entries_table (state)',
    ),
  ];
}
