import 'package:drift/drift.dart';

import 'library_entries_table.dart';
import 'series_table.dart';

@DataClassName('LibraryCacheState')
class LibraryCacheStates extends Table {
  TextColumn get ownerId => text()();
  BoolColumn get initialized => boolean().withDefault(const Constant(false))();
  TextColumn get watermark => text().nullable()();
  IntColumn get generation => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {ownerId};
}

@DataClassName('OwnedLibraryEntry')
class OwnedLibraryEntries extends Table with LibraryEntryColumns {
  TextColumn get ownerId => text().references(LibraryCacheStates, #ownerId)();
  TextColumn get seriesId => text().references(SeriesTable, #id)();

  @override
  Set<Column> get primaryKey => {ownerId, id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {ownerId, seriesId},
  ];
}
