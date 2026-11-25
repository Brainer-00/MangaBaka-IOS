import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';

mixin LibrarySyncMixin on LibraryServiceBase {
  Object? _syncRun;
  Future<void>? _running;
  final Map<LibraryCacheLease, Future<void>> _initialSyncs = {};
  LibraryCacheLease? _completedInitial;
  int _cancelGeneration = 0;
  LibraryCacheLease? _incomplete;

  int get maxSyncPages => AppConstants.libraryMaxPages;

  Future<bool> isLibraryIncomplete() async {
    final lease = currentLease;
    if (lease == null) return false;
    final state = await owned.readState(lease.owner);
    return identical(lease, currentLease) &&
        (state?.initialized != true || identical(_incomplete, lease));
  }

  Future<void> performInitialSyncIfNeeded() {
    final lease = currentLease;
    if (lease == null) return Future.value();
    if (identical(_completedInitial, lease)) return Future.value();
    return _initialSyncs.putIfAbsent(lease, () {
      final future = _initialSyncFor(lease, _cancelGeneration);
      future.whenComplete(() {
        if (identical(_initialSyncs[lease], future)) {
          _initialSyncs.remove(lease);
        }
      }).ignore();
      return future;
    });
  }

  Future<void> _initialSyncFor(LibraryCacheLease lease, int generation) async {
    final cache = await owned.readState(lease.owner);
    checkLease(lease);
    if (generation != _cancelGeneration) return;
    final running = _running;
    if (running != null) {
      await running;
      checkLease(lease);
      if (generation != _cancelGeneration) return;
      final updated = await owned.readState(lease.owner);
      checkLease(lease);
      if (generation != _cancelGeneration) return;
      if (cache?.initialized != true && updated?.initialized == true) {
        _completedInitial = lease;
        return;
      }
    }
    await syncFor(lease);
    checkLease(lease);
    if (generation == _cancelGeneration) _completedInitial = lease;
  }

  void cancelSync() {
    _cancelGeneration++;
    _syncRun = null;
    _running = null;
    _initialSyncs.clear();
    _completedInitial = null;
    syncStatus.value = const LibrarySyncStatus();
  }

  Future<void> syncLibrary({String? state}) async {
    final lease = currentLease;
    if (lease == null) return;
    await syncFor(lease, state: state, waitForExisting: false);
  }

  Future<void> importFullLibrary() async {
    final lease = requireLease();
    if (_running != null) return;
    await _start(lease, forceFull: true);
  }

  @override
  Future<void> syncFor(
    LibraryCacheLease lease, {
    String? state,
    bool waitForExisting = true,
  }) async {
    checkLease(lease);
    while (_running != null) {
      if (!waitForExisting) return;
      try {
        final waiting = _running;
        await waiting;
      } catch (_) {
        // A separate failed refresh does not consume this request.
      }
      checkLease(lease);
    }
    await _start(lease, state: state);
  }

  Future<void> _start(
    LibraryCacheLease lease, {
    String? state,
    bool forceFull = false,
  }) {
    final run = Object();
    _syncRun = run;
    final future = _sync(lease, run, state: state, forceFull: forceFull);
    _running = future;
    return future;
  }

  Future<void> _sync(
    LibraryCacheLease lease,
    Object run, {
    String? state,
    required bool forceFull,
  }) async {
    bool live() => identical(_syncRun, run) && identical(currentLease, lease);
    void beforeCommit() {
      if (!live()) throw StateError('Library sync no longer active');
    }

    if (live()) syncStatus.value = const LibrarySyncStatus(isSyncing: true);
    try {
      final cache = await owned.readState(lease.owner);
      if (!live()) return;
      final full = forceFull || cache?.initialized != true;
      final filter = full ? null : state;
      final previous = DateTime.tryParse(cache?.watermark ?? '');
      final seriesIds = <String>{};
      final incremental = <LibraryEntry>[];
      DateTime? newest;
      var count = 0;
      int? snapshotCount;

      for (var page = 1; page <= maxSyncPages; page++) {
        if (!live()) return;
        final result = await fetchPage(lease, page, state: filter);
        if (!live()) return;
        if (result.isError) {
          throw ApiException(
            message: 'Could not complete Library sync',
            statusCode: 400,
          );
        }
        if (full && result.count != null) {
          snapshotCount ??= result.count;
          if (snapshotCount != result.count) {
            throw const FormatException('Library changed during full import');
          }
        }

        var reachedOlder = false;
        for (final entry in result.entries) {
          final timestamp = DateTime.tryParse(
            entry.updatedAt ?? entry.createdAt ?? '',
          );
          if (timestamp != null &&
              (newest == null || timestamp.isAfter(newest))) {
            newest = timestamp;
          }
          // Equal timestamps can span multiple pages. Only stop at a strictly
          // older record, and include results with missing timestamps.
          if (!full &&
              previous != null &&
              timestamp != null &&
              timestamp.isBefore(previous)) {
            reachedOlder = true;
            break;
          }
          if (full) {
            if (!seriesIds.add(entry.series.id)) {
              throw const FormatException(
                'Duplicate series in Library snapshot',
              );
            }
          } else {
            incremental.add(entry);
          }
        }
        if (full && result.entries.isNotEmpty) {
          await owned.upsertEntries(
            lease,
            result.entries,
            beforeCommit: beforeCommit,
          );
          if (!live()) return;
        }
        count = full ? seriesIds.length : incremental.length;
        syncStatus.value = syncStatus.value.copyWith(currentEntries: count);

        final more = result.next != null;
        if (more && result.entries.isEmpty) {
          throw const FormatException(
            'Invalid empty Library page with a next page',
          );
        }
        if (!live()) return;
        if (reachedOlder || !more) {
          if (full) {
            if (snapshotCount != null && seriesIds.length != snapshotCount) {
              throw const FormatException('Incomplete Library snapshot');
            }
            await owned.finishFullImport(
              lease,
              completeSeriesIds: seriesIds,
              watermark: newest?.toUtc().toIso8601String(),
              beforeCommit: beforeCommit,
            );
          } else if (filter == null &&
              newest != null &&
              (previous == null || !newest.isBefore(previous))) {
            await owned.applyIncrementalSync(
              lease,
              incremental,
              watermark: newest.toUtc().toIso8601String(),
              beforeCommit: beforeCommit,
            );
          } else if (incremental.isNotEmpty) {
            await owned.upsertEntries(
              lease,
              incremental,
              beforeCommit: beforeCommit,
            );
          }
          if (live()) _incomplete = null;
          return;
        }
      }
      if (live()) _incomplete = lease;
      throw ApiException(
        message: 'Library sync reached its page limit',
        statusCode: 400,
        code: 'LIBRARY_PAGE_LIMIT',
      );
    } catch (error) {
      if (!live()) return;
      _incomplete = lease;
      syncStatus.value = syncStatus.value.copyWith(error: 'failed_to_load');
      rethrow;
    } finally {
      if (live()) {
        _running = null;
        _syncRun = null;
        syncStatus.value = syncStatus.value.copyWith(isSyncing: false);
      }
    }
  }
}
