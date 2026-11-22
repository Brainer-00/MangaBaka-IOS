part of '../database.dart';

@DriftAccessor(tables: [LibraryEntriesTable])
class LibraryEntriesDao extends DatabaseAccessor<AppDatabase>
    with _$LibraryEntriesDaoMixin {
  final _logger = LoggingService.logger;
  LibraryEntriesDao(super.db);

  Future<LibraryEntryWithSeries?> getEntryBySeriesId(String seriesId) async {
    try {
      final query = select(libraryEntriesTable).join([
        innerJoin(
          seriesTable,
          seriesTable.id.equalsExp(libraryEntriesTable.seriesId),
        ),
      ])..where(libraryEntriesTable.seriesId.equals(seriesId));

      final row = await query.getSingleOrNull();
      if (row == null) return null;
      return LibraryEntryWithSeries(
        libraryEntry: row.readTable(libraryEntriesTable),
        series: row.readTable(seriesTable),
      );
    } catch (e) {
      _logger.severe('Failed to get entry by series ID (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to get entry by series ID',
        originalError: e,
      );
    }
  }

  /// Returns the candidate series IDs already present locally without loading
  /// full library or series rows.
  Future<Set<String>> getExistingSeriesIds(Iterable<String> seriesIds) async {
    final ids = seriesIds.toSet().toList();
    if (ids.isEmpty) return <String>{};

    final query = selectOnly(libraryEntriesTable)
      ..addColumns([libraryEntriesTable.seriesId])
      ..where(libraryEntriesTable.seriesId.isIn(ids));
    final rows = await query
        .map((row) => row.read(libraryEntriesTable.seriesId)!)
        .get();
    return rows.toSet();
  }

  Stream<LibraryEntryWithSeries?> watchEntryWithSeries(String seriesId) {
    try {
      final query = select(libraryEntriesTable).join([
        innerJoin(
          seriesTable,
          seriesTable.id.equalsExp(libraryEntriesTable.seriesId),
        ),
      ])..where(libraryEntriesTable.seriesId.equals(seriesId));

      return query.watchSingleOrNull().map((row) {
        if (row == null) return null;
        return LibraryEntryWithSeries(
          libraryEntry: row.readTable(libraryEntriesTable),
          series: row.readTable(seriesTable),
        );
      });
    } catch (e) {
      _logger.severe('Failed to watch entry with series (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to watch entry with series',
        originalError: e,
      );
    }
  }

  Stream<List<LibraryEntryWithSeries>> watchAllEntriesWithSeries() {
    try {
      final query = select(libraryEntriesTable).join([
        innerJoin(
          seriesTable,
          seriesTable.id.equalsExp(libraryEntriesTable.seriesId),
        ),
      ]);

      return query.watch().map((rows) {
        return rows
            .map(
              (row) => LibraryEntryWithSeries(
                libraryEntry: row.readTable(libraryEntriesTable),
                series: row.readTable(seriesTable),
              ),
            )
            .toList();
      });
    } catch (e) {
      _logger.severe(
        'Failed to watch all entries with series (${e.runtimeType})',
      );
      throw exc.DatabaseException(
        message: 'Failed to watch all entries with series',
        originalError: e,
      );
    }
  }

  Future<void> upsertLibraryEntries(List<api.LibraryEntry> entries) async {
    if (entries.isEmpty) return;
    try {
      await db.transaction(() async {
        for (final entry in entries) {
          final conflictingId =
              await (select(libraryEntriesTable)..where(
                    (t) =>
                        t.id.equals(entry.id) &
                        t.seriesId.isNotValue(entry.series.id),
                  ))
                  .getSingleOrNull();
          if (conflictingId != null) {
            throw StateError('Library entry ID belongs to another series');
          }
          // A different entry ID is a new identity, so none of the old
          // account-specific values may be carried into it.
          await (delete(libraryEntriesTable)..where(
                (t) =>
                    t.seriesId.equals(entry.series.id) &
                    t.id.isNotValue(entry.id),
              ))
              .go();
          Value<T> field<T>(String key, T value) {
            return value != null || entry.explicitlyClears(key)
                ? Value(value)
                : const Value.absent();
          }

          final listIds = entry.listIds;
          final changes = LibraryEntriesTableCompanion(
            id: Value(entry.id),
            state: entry.state.isEmpty
                ? const Value.absent()
                : Value(entry.state),
            note: field('note', entry.note),
            progressChapter: field('progress_chapter', entry.progressChapter),
            progressVolume: field('progress_volume', entry.progressVolume),
            numberOfRereads: field('number_of_rereads', entry.numberOfRereads),
            rating: field('rating', entry.rating),
            priority: field('priority', entry.priority),
            startDate: field('start_date', entry.startDate),
            finishDate: field('finish_date', entry.finishDate),
            readLink: field('read_link', entry.readLink),
            isPrivate: field('is_private', entry.isPrivate),
            listIdsJson: listIds == null
                ? const Value.absent()
                : Value(jsonEncode(listIds)),
          );
          // Merge only within the same entry identity.
          final updated =
              await (update(libraryEntriesTable)..where(
                    (t) =>
                        t.seriesId.equals(entry.series.id) &
                        t.id.equals(entry.id),
                  ))
                  .write(changes);
          if (updated == 0) {
            await into(libraryEntriesTable).insert(
              changes.copyWith(
                seriesId: Value(entry.series.id),
                state: Value(entry.state),
              ),
            );
          }
        }
      });
    } catch (e) {
      _logger.severe('Failed to upsert library entries (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to upsert library entries',
        originalError: e,
      );
    }
  }

  Future<void> updateEntryState(String seriesId, String newState) async {
    try {
      await (update(libraryEntriesTable)
            ..where((t) => t.seriesId.equals(seriesId)))
          .write(LibraryEntriesTableCompanion(state: Value(newState)));
    } catch (e) {
      _logger.severe('Failed to update entry state (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to update entry state',
        originalError: e,
      );
    }
  }

  Future<void> updateEntryRating(String seriesId, int newRating) async {
    try {
      await (update(libraryEntriesTable)
            ..where((t) => t.seriesId.equals(seriesId)))
          .write(LibraryEntriesTableCompanion(rating: Value(newRating)));
    } catch (e) {
      _logger.severe('Failed to update entry rating (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to update entry rating',
        originalError: e,
      );
    }
  }

  Future<void> updateEntryProgress(
    String seriesId, {
    int? progressChapter,
    int? progressVolume,
    String? state,
    bool writeProgressChapter = false,
    bool writeProgressVolume = false,
  }) async {
    try {
      await (update(
        libraryEntriesTable,
      )..where((t) => t.seriesId.equals(seriesId))).write(
        LibraryEntriesTableCompanion(
          progressChapter: progressChapter != null || writeProgressChapter
              ? Value(progressChapter)
              : const Value.absent(),
          progressVolume: progressVolume != null || writeProgressVolume
              ? Value(progressVolume)
              : const Value.absent(),
          state: state != null ? Value(state) : const Value.absent(),
        ),
      );
    } catch (e) {
      _logger.severe('Failed to update entry progress (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to update entry progress',
        originalError: e,
      );
    }
  }

  Future<void> deleteEntry(String seriesId) async {
    try {
      await (delete(
        libraryEntriesTable,
      )..where((tbl) => tbl.seriesId.equals(seriesId))).go();
    } catch (e) {
      _logger.severe('Failed to delete entry (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to delete entry',
        originalError: e,
      );
    }
  }

  Future<void> deleteEntriesNotIn(List<String> validIds) async {
    try {
      final validSet = validIds.toSet();
      // Only select IDs to save memory
      final query = selectOnly(libraryEntriesTable)
        ..addColumns([libraryEntriesTable.id]);
      final allIds = await query
          .map((row) => row.read(libraryEntriesTable.id)!)
          .get();

      final toDelete = allIds.where((id) => !validSet.contains(id)).toList();

      if (toDelete.isEmpty) return;

      await db.transaction(() async {
        for (var i = 0; i < toDelete.length; i += 500) {
          final end = (i + 500 > toDelete.length) ? toDelete.length : i + 500;
          final chunk = toDelete.sublist(i, end);
          await (delete(
            libraryEntriesTable,
          )..where((t) => t.id.isIn(chunk))).go();
        }
      });
    } catch (e) {
      _logger.severe('Failed to delete stale entries (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to delete stale entries',
        originalError: e,
      );
    }
  }

  Future<void> deleteAllEntries() async {
    try {
      await delete(libraryEntriesTable).go();
    } catch (e) {
      _logger.severe('Failed to delete all entries (${e.runtimeType})');
      throw exc.DatabaseException(
        message: 'Failed to delete all entries',
        originalError: e,
      );
    }
  }
}
