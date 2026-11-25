part of '../database.dart';

/// The caller must establish this ID from authenticated MangaBaka identity
/// before crossing the database boundary. This type does not verify OAuth.
final class VerifiedLibraryOwner {
  VerifiedLibraryOwner.fromVerifiedAccountId(this.id) {
    if (id.isEmpty || id.trim() != id) {
      throw ArgumentError('Expected a verified MangaBaka account ID');
    }
  }

  final String id;
}

/// Capture this when scheduling an operation. Never reacquire it after an
/// asynchronous wait or when draining work queued by another session.
final class LibraryCacheLease {
  const LibraryCacheLease._(this.owner, this.generation);

  final VerifiedLibraryOwner owner;
  final int generation;
}

typedef OwnedEntryWithSeries = ({
  OwnedLibraryEntry entry,
  SeriesTableData series,
});

@DriftAccessor(tables: [LibraryCacheStates, OwnedLibraryEntries, SeriesTable])
class OwnedLibraryDao extends DatabaseAccessor<AppDatabase>
    with _$OwnedLibraryDaoMixin {
  OwnedLibraryDao(super.db);

  Future<LibraryCacheState?> readState(VerifiedLibraryOwner owner) => (select(
    libraryCacheStates,
  )..where((t) => t.ownerId.equals(owner.id))).getSingleOrNull();

  Stream<LibraryCacheState?> watchState(VerifiedLibraryOwner owner) => (select(
    libraryCacheStates,
  )..where((t) => t.ownerId.equals(owner.id))).watchSingleOrNull();

  Future<Set<String>> existingSeriesIds(
    VerifiedLibraryOwner owner,
    Iterable<String> candidates,
  ) async {
    final table = ownedLibraryEntries;
    final ids = candidates.toSet().toList();
    final result = <String>{};
    for (var i = 0; i < ids.length; i += 500) {
      result.addAll(
        await (selectOnly(table)
              ..addColumns([table.seriesId])
              ..where(
                table.ownerId.equals(owner.id) &
                    table.seriesId.isIn(ids.skip(i).take(500)),
              ))
            .map((row) => row.read(table.seriesId)!)
            .get(),
      );
    }
    return result;
  }

  /// Call once per verified session, including after process restart. The
  /// previous writer loses its lease even when reconnecting to the same owner.
  Future<LibraryCacheLease> activate(VerifiedLibraryOwner owner) =>
      db.transaction(() async {
        await (update(libraryCacheStates)..where((t) => t.active.equals(true)))
            .write(const LibraryCacheStatesCompanion(active: Value(false)));
        final saved = await readState(owner);
        final generation = (saved?.generation ?? 0) + 1;
        if (saved == null) {
          await into(libraryCacheStates).insert(
            LibraryCacheStatesCompanion.insert(
              ownerId: owner.id,
              active: const Value(true),
              generation: Value(generation),
            ),
          );
        } else {
          await (update(
            libraryCacheStates,
          )..where((t) => t.ownerId.equals(owner.id))).write(
            LibraryCacheStatesCompanion(
              active: const Value(true),
              generation: Value(generation),
            ),
          );
        }
        return LibraryCacheLease._(owner, generation);
      });

  /// A stale invalidation cannot revoke the current session.
  Future<void> invalidate(LibraryCacheLease lease) async {
    await (update(libraryCacheStates)..where((t) => _activeLease(t, lease)))
        .write(const LibraryCacheStatesCompanion(active: Value(false)));
  }

  Expression<bool> _activeLease(
    LibraryCacheStates table,
    LibraryCacheLease lease,
  ) =>
      table.ownerId.equals(lease.owner.id) &
      table.generation.equals(lease.generation) &
      table.active.equals(true);

  Future<T> _write<T>(
    LibraryCacheLease lease,
    Future<T> Function() work, {
    void Function()? beforeCommit,
  }) => db.transaction(() async {
    // Acquire SQLite's write lock while checking the persisted lease.
    // Activation/invalidation must serialize before or after this commit.
    final matched =
        await (update(libraryCacheStates)..where((t) => _activeLease(t, lease)))
            .write(const LibraryCacheStatesCompanion(active: Value(true)));
    if (matched != 1) throw StateError('Library cache lease is inactive');
    final result = await work();
    beforeCommit?.call();
    return result;
  });

  JoinedSelectStatement<HasResultSet, dynamic> _query(
    VerifiedLibraryOwner owner, {
    String? seriesId,
  }) {
    final entries = ownedLibraryEntries;
    return select(entries).join([
      innerJoin(seriesTable, seriesTable.id.equalsExp(entries.seriesId)),
    ])..where(
      entries.ownerId.equals(owner.id) &
          (seriesId == null
              ? const Constant(true)
              : entries.seriesId.equals(seriesId)),
    );
  }

  OwnedEntryWithSeries _withSeries(TypedResult row) => (
    entry: row.readTable(ownedLibraryEntries),
    series: row.readTable(seriesTable),
  );

  Future<OwnedEntryWithSeries?> findEntry(
    VerifiedLibraryOwner owner,
    String seriesId,
  ) => _query(owner, seriesId: seriesId).map(_withSeries).getSingleOrNull();

  Stream<OwnedEntryWithSeries?> watchEntry(
    VerifiedLibraryOwner owner,
    String seriesId,
  ) => _query(owner, seriesId: seriesId).map(_withSeries).watchSingleOrNull();

  Future<List<OwnedEntryWithSeries>> listEntries(VerifiedLibraryOwner owner) =>
      _query(owner).map(_withSeries).get();

  Stream<List<OwnedEntryWithSeries>> watchEntries(VerifiedLibraryOwner owner) =>
      _query(owner).map(_withSeries).watch();

  Future<void> upsertEntries(
    LibraryCacheLease lease,
    List<api.LibraryEntry> entries, {
    void Function()? beforeCommit,
  }) => _write(
    lease,
    () => _upsert(lease.owner, entries),
    beforeCommit: beforeCommit,
  );

  Future<void> _upsert(
    VerifiedLibraryOwner owner,
    List<api.LibraryEntry> entries,
  ) async {
    await db.seriesDao.upsertSeries(
      entries.map((entry) => entry.series).toList(),
    );
    final table = ownedLibraryEntries;
    for (final entry in entries) {
      if (entry.id.isEmpty || entry.series.id.isEmpty) {
        throw ArgumentError('Expected both Library entry and series IDs');
      }
      final previous =
          await (select(table)..where(
                (t) =>
                    t.ownerId.equals(owner.id) &
                    t.seriesId.equals(entry.series.id),
              ))
              .getSingleOrNull();
      Value<T> field<T>(String key, T value) =>
          value != null || entry.explicitlyClears(key)
          ? Value(value)
          : const Value.absent();

      final changes = OwnedLibraryEntriesCompanion(
        state: entry.state.isEmpty ? const Value.absent() : Value(entry.state),
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
        listIdsJson: entry.listIds == null
            ? const Value.absent()
            : Value(jsonEncode(entry.listIds)),
      );
      if (previous?.id == entry.id) {
        if (changes.toColumns(false).isEmpty) continue;
        await (update(
              table,
            )..where((t) => t.ownerId.equals(owner.id) & t.id.equals(entry.id)))
            .write(changes);
      } else {
        if (entry.state.isEmpty) {
          throw ArgumentError('New Library entry requires a state');
        }
        if (previous != null) {
          await (delete(table)..where(
                (t) => t.ownerId.equals(owner.id) & t.id.equals(previous.id),
              ))
              .go();
        }
        // A conflicting ID for another series fails the plain insert and rolls
        // back the entire transaction, including any replacement above.
        await into(table).insert(
          changes.copyWith(
            ownerId: Value(owner.id),
            id: Value(entry.id),
            seriesId: Value(entry.series.id),
          ),
        );
      }
    }
  }

  Future<int> updateQuickFields(
    LibraryCacheLease lease,
    String seriesId, {
    Value<String> state = const Value.absent(),
    Value<int?> progressChapter = const Value.absent(),
    Value<int?> progressVolume = const Value.absent(),
    Value<int?> rating = const Value.absent(),
    void Function()? beforeCommit,
  }) => _write(
    lease,
    () =>
        (update(ownedLibraryEntries)..where(
              (t) =>
                  t.ownerId.equals(lease.owner.id) &
                  t.seriesId.equals(seriesId),
            ))
            .write(
              OwnedLibraryEntriesCompanion(
                state: state,
                progressChapter: progressChapter,
                progressVolume: progressVolume,
                rating: rating,
              ),
            ),
    beforeCommit: beforeCommit,
  );

  Future<int> deleteEntry(
    LibraryCacheLease lease,
    String seriesId, {
    void Function()? beforeCommit,
  }) => _write(
    lease,
    () =>
        (delete(ownedLibraryEntries)..where(
              (t) =>
                  t.ownerId.equals(lease.owner.id) &
                  t.seriesId.equals(seriesId),
            ))
            .go(),
    beforeCommit: beforeCommit,
  );

  /// Use only for a successfully completed, unfiltered server snapshot.
  /// An explicit empty snapshot is authoritative. Failed or capped imports
  /// must never call this method.
  Future<void> finishFullImport(
    LibraryCacheLease lease, {
    required Set<String> completeSeriesIds,
    required String? watermark,
    List<api.LibraryEntry> entries = const [],
    void Function()? beforeCommit,
  }) => _write(lease, () async {
    final owner = lease.owner;
    await _upsert(owner, entries);
    final table = ownedLibraryEntries;
    final ids =
        await (selectOnly(table)
              ..addColumns([table.seriesId])
              ..where(table.ownerId.equals(owner.id)))
            .map((row) => row.read(table.seriesId)!)
            .get();
    if (!ids.toSet().containsAll(completeSeriesIds)) {
      throw StateError('Full Library import is missing entries');
    }
    final stale = ids.where((id) => !completeSeriesIds.contains(id)).toList();
    // Bound the number of SQLite variables even for large libraries.
    for (var i = 0; i < stale.length; i += 500) {
      await (delete(table)..where(
            (t) =>
                t.ownerId.equals(owner.id) &
                t.seriesId.isIn(stale.skip(i).take(500)),
          ))
          .go();
    }
    await (update(
      libraryCacheStates,
    )..where((t) => _activeLease(t, lease))).write(
      LibraryCacheStatesCompanion(
        initialized: const Value(true),
        watermark: Value(watermark),
      ),
    );
  }, beforeCommit: beforeCommit);

  Future<void> applyIncrementalSync(
    LibraryCacheLease lease,
    List<api.LibraryEntry> entries, {
    required String watermark,
    void Function()? beforeCommit,
  }) => _write(lease, () async {
    final state = await readState(lease.owner);
    if (state?.initialized != true) {
      throw StateError('Library cache requires a full import');
    }
    await _upsert(lease.owner, entries);
    await (update(libraryCacheStates)..where((t) => _activeLease(t, lease)))
        .write(LibraryCacheStatesCompanion(watermark: Value(watermark)));
  }, beforeCommit: beforeCommit);
}
