import 'dart:async';

import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';

mixin LibrarySyncMixin on LibraryServiceBase {
  Object? _syncRun;
  Completer<void>? _interruptRun;
  Future<void>? _running;
  Future<void>? _reconciliation;
  final Map<LibraryCacheLease, Future<void>> _initialSyncs = {};
  LibraryCacheLease? _completedInitial;
  int _cancelGeneration = 0;
  LibraryCacheLease? _incomplete;
  LibraryCacheLease? _pauseLease;
  int _pauseCount = 0;
  Completer<void>? _pauseReleased;

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
      if (identical(_completedInitial, lease) ||
          (cache?.initialized != true && updated?.initialized == true)) {
        _completedInitial = lease;
        return;
      }
    }
    await reconcileLibrary(lease);
    checkLease(lease);
    if (generation == _cancelGeneration) _completedInitial = lease;
  }

  @override
  void cancelSync() {
    _cancelGeneration++;
    final interrupt = _interruptRun;
    _interruptRun = null;
    if (interrupt != null && !interrupt.isCompleted) interrupt.complete();
    _pauseLease = null;
    _pauseCount = 0;
    final released = _pauseReleased;
    _pauseReleased = null;
    if (released != null && !released.isCompleted) released.complete();
    _syncRun = null;
    _running = null;
    _reconciliation = null;
    _initialSyncs.clear();
    _completedInitial = null;
    syncStatus.value = const LibrarySyncStatus();
  }

  @override
  void Function() pauseSyncForReconciliation(LibraryCacheLease lease) {
    checkLease(lease);
    final generation = _cancelGeneration;
    if (_pauseCount++ == 0) {
      _pauseLease = lease;
      _pauseReleased = Completer<void>();
      if (_syncRun != null) {
        _syncRun = null;
        _interruptRun?.complete();
        syncStatus.value = const LibrarySyncStatus();
      }
    }
    var done = false;
    return () {
      if (done) return;
      done = true;
      if (!identical(_pauseLease, lease) || generation != _cancelGeneration) {
        return;
      }
      _pauseCount--;
      if (_pauseCount != 0) return;
      final released = _pauseReleased;
      _pauseReleased = null;
      _pauseLease = null;
      released?.complete();
    };
  }

  Future<void> syncLibrary({String? state}) async {
    final lease = currentLease;
    if (lease == null) return;
    await syncFor(lease, state: state, waitForExisting: false);
  }

  /// Explicit Home and Library refreshes share a deletion-aware run with
  /// account startup. Routine mutation catch-up can still use incremental sync.
  Future<void> reconcileLibrary(LibraryCacheLease lease) {
    checkLease(lease);
    final active = _reconciliation;
    if (active != null) return active;
    late final Future<void> run;
    run = _runReconciliation(lease).whenComplete(() {
      if (identical(_reconciliation, run)) _reconciliation = null;
    });
    return _reconciliation = run;
  }

  Future<void> _runReconciliation(LibraryCacheLease lease) async {
    final generation = _cancelGeneration;
    while (true) {
      final pause = _pauseReleased;
      final running = _running;
      if (pause != null) {
        await pause.future;
      } else if (running != null) {
        try {
          await running;
        } catch (_) {
          // An incremental or filtered failure does not consume this request.
        }
      } else {
        await _start(lease, forceFull: true, verifyAbsences: true);
        checkLease(lease);
        if (generation == _cancelGeneration) _completedInitial = lease;
        return;
      }
      checkLease(lease);
      if (generation != _cancelGeneration) return;
    }
  }

  Future<void> importFullLibrary() async {
    final lease = requireLease();
    final generation = _cancelGeneration;
    while (_pauseReleased != null) {
      await _pauseReleased!.future;
      checkLease(lease);
      if (generation != _cancelGeneration) return;
    }
    if (_running != null) return;
    await _start(lease, forceFull: true, verifyAbsences: true);
  }

  @override
  Future<void> syncFor(
    LibraryCacheLease lease, {
    String? state,
    bool waitForExisting = true,
  }) async {
    checkLease(lease);
    final generation = _cancelGeneration;
    while (true) {
      final pause = _pauseReleased;
      final running = _running;
      if (pause != null) {
        await pause.future;
      } else if (running != null) {
        if (!waitForExisting) return;
        try {
          await running;
        } catch (_) {
          // A separate failed refresh does not consume this request.
        }
      } else {
        await _start(lease, state: state);
        return;
      }
      checkLease(lease);
      if (generation != _cancelGeneration) return;
    }
  }

  Future<void> _start(
    LibraryCacheLease lease, {
    String? state,
    bool forceFull = false,
    bool verifyAbsences = false,
  }) {
    final generation = _cancelGeneration;
    // Publish the logical Future before the attempt can notify listeners.
    final future = Future<void>.microtask(
      () =>
          _runLogicalSync(lease, generation, state, forceFull, verifyAbsences),
    );
    _running = future;
    return future;
  }

  Future<void> _runLogicalSync(
    LibraryCacheLease lease,
    int generation,
    String? state,
    bool forceFull,
    bool verifyAbsences,
  ) async {
    bool active() =>
        generation == _cancelGeneration && identical(currentLease, lease);
    try {
      while (active()) {
        final pause = _pauseReleased;
        if (pause != null) {
          await pause.future;
          continue;
        }
        final run = Object();
        final interrupted = Completer<void>();
        _syncRun = run;
        _interruptRun = interrupted;
        // Future.any observes late errors from the abandoned attempt.
        // Its run token also fences every database commit.
        await Future.any([
          _sync(
            lease,
            run,
            state: state,
            forceFull: forceFull,
            verifyAbsences: verifyAbsences,
          ),
          interrupted.future,
        ]);
        if (identical(_syncRun, run)) return;
      }
    } finally {
      if (active()) {
        _running = null;
        _syncRun = null;
        _interruptRun = null;
        syncStatus.value = syncStatus.value.copyWith(isSyncing: false);
      }
    }
  }

  Future<void> _sync(
    LibraryCacheLease lease,
    Object run, {
    String? state,
    required bool forceFull,
    required bool verifyAbsences,
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
          if (full &&
              (entry.id.isEmpty ||
                  entry.series.id.isEmpty ||
                  !AppConstants.libraryStates.contains(entry.state))) {
            throw const FormatException('Invalid Library snapshot entry');
          }
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
            // Offset pages can shift even when the total stays equal. Confirm
            // only absent cached IDs, one at a time, before any deletion.
            if (verifyAbsences && (page > 1 || snapshotCount == null)) {
              final cached = await owned.listEntries(lease.owner);
              if (!live()) return;
              for (final row in cached) {
                final id = row.entry.seriesId;
                if (seriesIds.contains(id)) continue;
                final exists = await confirmLibraryEntryExists(lease, id);
                if (!live()) return;
                if (exists) seriesIds.add(id);
              }
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
    }
  }
}
