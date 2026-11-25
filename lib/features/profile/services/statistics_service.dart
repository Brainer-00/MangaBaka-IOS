import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:drift/drift.dart' as drift;
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';

class StatisticsService {
  final _logger = LoggingService.logger;
  final AppDatabase _db;

  final ProfileAuthService _auth;
  StatisticsService(this._db, this._auth);

  drift.Expression<bool> _scope(LibraryCacheLease lease) {
    final states = _db.libraryCacheStates;
    final verified = _db.selectOnly(states)
      ..addColumns([states.ownerId])
      ..where(
        states.ownerId.equals(lease.owner.id) &
            states.generation.equals(lease.generation) &
            states.active.equals(true) &
            states.initialized.equals(true),
      );
    return _db.ownedLibraryEntries.ownerId.equals(lease.owner.id) &
        drift.existsQuery(verified);
  }

  Future<int> getTotalSeries({List<String>? contentPreferences}) async {
    final lease = _auth.libraryLease;
    if (lease == null) return 0;
    try {
      final count = drift.countAll();
      final query = _db.selectOnly(_db.ownedLibraryEntries).join([
        drift.innerJoin(
          _db.seriesTable,
          _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
        ),
      ])..addColumns([count]);

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      final result = await query.getSingle();
      if (!identical(lease, _auth.libraryLease)) return 0;
      final val = result.read(count) ?? 0;
      _logger.fine('Calculated total series count');
      return val;
    } catch (e, st) {
      _logger.severe('Failed to get total series from DB (${e.runtimeType})');
      throw DatabaseException(
        message: 'Failed to get total series',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<int> getChaptersRead({List<String>? contentPreferences}) async {
    final lease = _auth.libraryLease;
    if (lease == null) return 0;
    try {
      final sum = _db.ownedLibraryEntries.progressChapter.sum();
      final query = _db.selectOnly(_db.ownedLibraryEntries).join([
        drift.innerJoin(
          _db.seriesTable,
          _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
        ),
      ])..addColumns([sum]);

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      final result = await query.getSingle();
      if (!identical(lease, _auth.libraryLease)) return 0;
      final val = result.read(sum) ?? 0;
      _logger.fine('Calculated total chapters read');
      return val;
    } catch (e, st) {
      _logger.severe('Failed to get chapters read from DB (${e.runtimeType})');
      throw DatabaseException(
        message: 'Failed to get chapters read',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<int> getVolumesRead({List<String>? contentPreferences}) async {
    final lease = _auth.libraryLease;
    if (lease == null) return 0;
    try {
      final sum = _db.ownedLibraryEntries.progressVolume.sum();
      final query = _db.selectOnly(_db.ownedLibraryEntries).join([
        drift.innerJoin(
          _db.seriesTable,
          _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
        ),
      ])..addColumns([sum]);

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      final result = await query.getSingle();
      if (!identical(lease, _auth.libraryLease)) return 0;
      final val = result.read(sum) ?? 0;
      _logger.fine('Calculated total volumes read');
      return val;
    } catch (e, st) {
      _logger.severe('Failed to get volumes read from DB (${e.runtimeType})');
      throw DatabaseException(
        message: 'Failed to get volumes read',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<double> getCompletionRate({List<String>? contentPreferences}) async {
    final lease = _auth.libraryLease;
    if (lease == null) return 0.0;
    try {
      final totalCount = drift.countAll();
      final completedCount = drift.countAll(
        filter: _db.ownedLibraryEntries.state.equals('completed'),
      );

      final query = _db.selectOnly(_db.ownedLibraryEntries).join([
        drift.innerJoin(
          _db.seriesTable,
          _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
        ),
      ])..addColumns([totalCount, completedCount]);

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      final result = await query.getSingle();
      if (!identical(lease, _auth.libraryLease)) return 0.0;
      final total = result.read(totalCount) ?? 0;
      if (total == 0) return 0.0;

      final completed = result.read(completedCount) ?? 0;
      final rate = (completed / total) * 100;
      _logger.fine('Calculated completion rate');
      return rate;
    } catch (e, st) {
      _logger.severe('Failed to calculate completion rate (${e.runtimeType})');
      throw DatabaseException(
        message: 'Failed to get completion rate',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<int> getTotalRereads({List<String>? contentPreferences}) async {
    final lease = _auth.libraryLease;
    if (lease == null) return 0;
    try {
      final sum = _db.ownedLibraryEntries.numberOfRereads.sum();
      final query = _db.selectOnly(_db.ownedLibraryEntries).join([
        drift.innerJoin(
          _db.seriesTable,
          _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
        ),
      ])..addColumns([sum]);

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      final result = await query.getSingle();
      if (!identical(lease, _auth.libraryLease)) return 0;
      final val = result.read(sum) ?? 0;
      _logger.fine('Calculated total rereads');
      return val;
    } catch (e, st) {
      _logger.severe('Failed to get total rereads from DB (${e.runtimeType})');
      throw DatabaseException(
        message: 'Failed to get total rereads',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<double> getMeanScore({List<String>? contentPreferences}) async {
    final lease = _auth.libraryLease;
    if (lease == null) return 0.0;
    try {
      final avg = _db.ownedLibraryEntries.rating.avg();
      final query =
          _db.selectOnly(_db.ownedLibraryEntries).join([
              drift.innerJoin(
                _db.seriesTable,
                _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
              ),
            ])
            ..addColumns([avg])
            ..where(_db.ownedLibraryEntries.rating.isNotNull());

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      final result = await query.getSingle();
      if (!identical(lease, _auth.libraryLease)) return 0.0;
      final val = result.read(avg) ?? 0.0;
      _logger.fine('Calculated mean score');
      return val;
    } catch (e, st) {
      _logger.severe('Failed to calculate mean score (${e.runtimeType})');
      throw DatabaseException(
        message: 'Failed to get mean score',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<double> getFinishRate({List<String>? contentPreferences}) async {
    final lease = _auth.libraryLease;
    if (lease == null) return 0.0;
    try {
      final completedExpr = _db.ownedLibraryEntries.state.equals('completed');
      final droppedExpr = _db.ownedLibraryEntries.state.equals('dropped');

      final completedCount = drift.countAll(filter: completedExpr);
      final droppedCount = drift.countAll(filter: droppedExpr);

      final query = _db.selectOnly(_db.ownedLibraryEntries).join([
        drift.innerJoin(
          _db.seriesTable,
          _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
        ),
      ])..addColumns([completedCount, droppedCount]);

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      final result = await query.getSingle();
      if (!identical(lease, _auth.libraryLease)) return 0.0;
      final completed = result.read(completedCount) ?? 0;
      final dropped = result.read(droppedCount) ?? 0;

      final total = completed + dropped;
      if (total == 0) return 0.0;

      final rate = (completed / total) * 100;
      _logger.fine('Calculated finish rate');
      return rate;
    } catch (e, st) {
      _logger.severe('Failed to calculate finish rate (${e.runtimeType})');
      throw DatabaseException(
        message: 'Failed to get finish rate',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<OwnedEntryWithSeries?> getHighestRatedSeries({
    List<String>? contentPreferences,
  }) async {
    final lease = _auth.libraryLease;
    if (lease == null) return null;
    try {
      final query = _db.select(_db.ownedLibraryEntries).join([
        drift.innerJoin(
          _db.seriesTable,
          _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
        ),
      ])..where(_db.ownedLibraryEntries.rating.isNotNull());

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      query
        ..orderBy([
          drift.OrderingTerm(
            expression: _db.ownedLibraryEntries.rating,
            mode: drift.OrderingMode.desc,
          ),
          drift.OrderingTerm(
            expression: _db.seriesTable.title,
            mode: drift.OrderingMode.asc,
          ),
        ])
        ..limit(1);

      final row = await query.getSingleOrNull();
      if (row == null || !identical(lease, _auth.libraryLease)) {
        _logger.fine('No rated series found for highest rated check');
        return null;
      }

      final entry = (
        entry: row.readTable(_db.ownedLibraryEntries),
        series: row.readTable(_db.seriesTable),
      );
      _logger.fine('Highest rated series found');
      return entry;
    } catch (e, st) {
      _logger.severe(
        'Failed to get highest rated series from DB (${e.runtimeType})',
      );
      throw DatabaseException(
        message: 'Failed to get highest rated series',
        originalError: e,
        stackTrace: st,
      );
    }
  }

  Future<OwnedEntryWithSeries?> getMostRereadSeries({
    List<String>? contentPreferences,
  }) async {
    final lease = _auth.libraryLease;
    if (lease == null) return null;
    try {
      final query =
          _db.select(_db.ownedLibraryEntries).join([
              drift.innerJoin(
                _db.seriesTable,
                _db.seriesTable.id.equalsExp(_db.ownedLibraryEntries.seriesId),
              ),
            ])
            ..where(_db.ownedLibraryEntries.numberOfRereads.isNotNull())
            ..where(
              _db.ownedLibraryEntries.numberOfRereads.isBiggerThan(
                const drift.Constant(0),
              ),
            );

      query.where(_scope(lease));
      if (contentPreferences != null && contentPreferences.isNotEmpty) {
        query.where(
          _db.seriesTable.contentRating.isIn(
            contentPreferences.map((e) => e.toLowerCase()).toList(),
          ),
        );
      }

      query
        ..orderBy([
          drift.OrderingTerm(
            expression: _db.ownedLibraryEntries.numberOfRereads,
            mode: drift.OrderingMode.desc,
          ),
          drift.OrderingTerm(
            expression: _db.seriesTable.title,
            mode: drift.OrderingMode.asc,
          ),
        ])
        ..limit(1);

      final row = await query.getSingleOrNull();
      if (row == null || !identical(lease, _auth.libraryLease)) {
        _logger.fine('No reread series found for most reread check');
        return null;
      }

      final entry = (
        entry: row.readTable(_db.ownedLibraryEntries),
        series: row.readTable(_db.seriesTable),
      );
      _logger.fine('Most reread series found');
      return entry;
    } catch (e, st) {
      _logger.severe(
        'Failed to get most reread series from DB (${e.runtimeType})',
      );
      throw DatabaseException(
        message: 'Failed to get most reread series',
        originalError: e,
        stackTrace: st,
      );
    }
  }
}
