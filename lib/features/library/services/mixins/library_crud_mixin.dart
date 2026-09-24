import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:mangabaka_app/features/library/constants/library_constants.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart' as db;
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _isIncompleteKey = '${AppConstants.prefixStorageKey}library_is_incomplete';

mixin LibraryCrudMixin on LibraryServiceBase {

  // ── Shared HTTP helpers ───────────────────────────────────────────────────

  /// Standard headers for every library API request.
  Map<String, String> _buildAuthHeaders(String token, {bool json = true}) => {
        'Authorization': 'Bearer $token',
        'User-Agent': LibraryConstants.userAgent,
        if (json) 'Content-Type': 'application/json',
      };

  /// Throws [AuthException] when the server returns 401.
  void _assertAuthorized(http.Response response, String seriesId) {
    if (response.statusCode == 401) {
      logger.severe('Unauthorized library request');
      throw AuthException(message: 'Authentication failed.', code: 'AUTH_FAILED');
    }
  }

  /// Re-throws [e] as an appropriate [AppException] subtype.
  /// Call this from the catch block of every CRUD operation.
  Never _rethrowAsAppException(
    Object e,
    StackTrace st,
    String seriesId,
    String operation,
  ) {
    logger.severe('$operation failed (${e.runtimeType})');
    if (e is AppException) throw e;
    if (e is http.ClientException || e is SocketException) {
      throw NetworkException(
        message: 'Network error.',
        code: 'NETWORK_ERROR',
        originalError: e,
        stackTrace: st,
      );
    }
    if (e is TimeoutException) {
      throw NetworkException(
        message: 'Request timed out.',
        code: 'TIMEOUT',
        originalError: e,
        stackTrace: st,
      );
    }
    throw AppError(message: 'Failed to $operation', originalError: e, stackTrace: st);
  }

  // ── CRUD operations ───────────────────────────────────────────────────────

  Future<void> updateLibraryEntryState(String seriesId, String state) async {
    logger.info('Updating library entry state');
    final token = await auth.getValidAccessToken();
    final url = Uri.parse('${LibraryConstants.baseUrl}/$seriesId');
    try {
      final response = await http
          .put(url, headers: _buildAuthHeaders(token), body: jsonEncode({'state': state}))
          .timeout(
            const Duration(seconds: AppConstants.networkTimeoutSeconds),
            onTimeout: () => throw TimeoutException('Update state request timed out'),
          );

      _assertAuthorized(response, seriesId);
      if (response.statusCode != 200) {
        logger.severe(
          'Failed to update entry state (HTTP ${response.statusCode})',
        );
        throw ApiException(
          message: 'Failed to update entry state',
          statusCode: response.statusCode,
          responseBody: response.body,
          code: 'UPDATE_STATE_FAILED',
        );
      }

      await database.libraryEntriesDao.updateEntryState(seriesId, state);
      logger.info('Successfully updated library entry state in DB');
    } catch (e, st) {
      _rethrowAsAppException(e, st, seriesId, 'update entry state');
    }
  }

  Future<void> updateLibraryEntryRating(String seriesId, int rating) async {
    logger.info('Updating library entry rating');
    final token = await auth.getValidAccessToken();
    final url = Uri.parse('${LibraryConstants.baseUrl}/$seriesId');
    try {
      final response = await http
          .put(url, headers: _buildAuthHeaders(token), body: jsonEncode({'rating': rating}))
          .timeout(
            const Duration(seconds: AppConstants.networkTimeoutSeconds),
            onTimeout: () => throw TimeoutException('Update rating request timed out'),
          );

      _assertAuthorized(response, seriesId);
      if (response.statusCode != 200) {
        logger.severe(
          'Failed to update entry rating (HTTP ${response.statusCode})',
        );
        throw ApiException(
          message: 'Failed to update entry rating',
          statusCode: response.statusCode,
          responseBody: response.body,
          code: 'UPDATE_RATING_FAILED',
        );
      }

      await database.libraryEntriesDao.updateEntryRating(seriesId, rating);
      logger.info('Successfully updated library entry rating in DB');
    } catch (e, st) {
      _rethrowAsAppException(e, st, seriesId, 'update entry rating');
    }
  }

  /// Restores local progress to the values captured before an optimistic update.
  Future<void> _rollbackProgress(String seriesId, db.LibraryEntryWithSeries? snapshot) async {
    if (snapshot == null) return;
    await database.libraryEntriesDao.updateEntryProgress(
      seriesId,
      progressChapter: snapshot.libraryEntry.progressChapter,
      progressVolume: snapshot.libraryEntry.progressVolume,
    );
  }

  Future<void> updateLibraryEntryProgress(
    String seriesId, {
    int? progressChapter,
    int? progressVolume,
  }) async {
    logger.info('Updating library entry progress (optimistic)');

    // Capture state for rollback, then apply optimistic local update.
    final snapshot = await database.libraryEntriesDao.getEntryBySeriesId(seriesId);
    await database.libraryEntriesDao.updateEntryProgress(
      seriesId,
      progressChapter: progressChapter,
      progressVolume: progressVolume,
    );

    try {
      final token = await auth.getValidAccessToken();
      final url = Uri.parse('${LibraryConstants.baseUrl}/$seriesId');

      final body = <String, dynamic>{
        'progress_chapter': ?progressChapter,
        'progress_volume': ?progressVolume,
      };

      final response = await http
          .put(url, headers: _buildAuthHeaders(token), body: jsonEncode(body))
          .timeout(
            const Duration(seconds: AppConstants.networkTimeoutSeconds),
            onTimeout: () => throw TimeoutException('Update progress request timed out'),
          );

      _assertAuthorized(response, seriesId);

      if (response.statusCode != 200) {
        logger.severe(
          'Failed to update entry progress (HTTP ${response.statusCode})',
        );
        await _rollbackProgress(seriesId, snapshot);
        throw ApiException(
          message: 'Failed to update entry progress',
          statusCode: response.statusCode,
          responseBody: response.body,
          code: 'UPDATE_PROGRESS_FAILED',
        );
      }

      logger.info('Successfully updated library entry progress on server');
    } catch (e, st) {
      logger.severe('Error updating entry progress (${e.runtimeType})');
      await _rollbackProgress(seriesId, snapshot);
      _rethrowAsAppException(e, st, seriesId, 'update entry progress');
    }
  }

  Future<void> createLibraryEntry(String seriesId, String state) async {
    logger.info('Creating library entry');
    final token = await auth.getValidAccessToken();
    final url = Uri.parse('${LibraryConstants.baseUrl}/$seriesId');
    try {
      final response = await http
          .post(url, headers: _buildAuthHeaders(token), body: jsonEncode({'state': state}))
          .timeout(
            const Duration(seconds: AppConstants.networkTimeoutSeconds),
            onTimeout: () => throw TimeoutException('Create entry request timed out'),
          );

      _assertAuthorized(response, seriesId);
      if (response.statusCode == 201) {
        logger.info('Successfully created library entry; syncing local DB');
        await syncLibrary();
      } else {
        logger.severe(
          'Failed to create library entry (HTTP ${response.statusCode})',
        );
        throw ApiException(
          message: 'Failed to create library entry',
          statusCode: response.statusCode,
          responseBody: response.body,
          code: 'CREATE_ENTRY_FAILED',
        );
      }
    } catch (e, st) {
      _rethrowAsAppException(e, st, seriesId, 'create library entry');
    }
  }

  /// Most entries the batch endpoint takes in one request.
  static const int batchLimit = 100;

  /// Adds many series to the library at once, each in [state].
  ///
  /// Uses `POST /my/library/batch`, which creates missing entries but *patches*
  /// existing ones - so callers should leave out series already in the library,
  /// or their state would be overwritten. Each request is atomic (one bad
  /// series fails its whole chunk of up to [batchLimit]); chunks already
  /// accepted stay accepted, and the local database is re-synced either way.
  ///
  /// Returns how many entries the server reports as newly created.
  Future<int> createLibraryEntriesBatch(
    List<String> seriesIds,
    String state,
  ) async {
    final ids = [
      for (final id in seriesIds)
        if (int.tryParse(id) != null) int.parse(id),
    ];
    if (ids.isEmpty) return 0;

    logger.info('Batch-adding ${ids.length} series');
    final token = await auth.getValidAccessToken();
    final url = Uri.parse('${LibraryConstants.baseUrl}/batch');
    var created = 0;
    var anyAccepted = false;

    try {
      for (var i = 0; i < ids.length; i += batchLimit) {
        final chunk = ids.sublist(i, min(i + batchLimit, ids.length));
        final response = await http
            .post(
              url,
              headers: _buildAuthHeaders(token),
              body: jsonEncode([
                for (final id in chunk) {'series_id': id, 'state': state},
              ]),
            )
            .timeout(
              const Duration(seconds: AppConstants.networkTimeoutSeconds),
              onTimeout: () =>
                  throw TimeoutException('Batch add request timed out'),
            );

        _assertAuthorized(response, 'batch');
        if (response.statusCode != 200) {
          logger.severe('Batch add failed. Status: ${response.statusCode}');
          throw ApiException(
            message: 'Failed to add series to library',
            statusCode: response.statusCode,
            responseBody: response.body,
            code: 'BATCH_CREATE_FAILED',
          );
        }
        anyAccepted = true;
        final data = (jsonDecode(response.body) as Map)['data'];
        if (data is List) {
          created += data.where((e) => e is Map && e['action'] == 'created').length;
        }
      }
    } catch (e, st) {
      _rethrowAsAppException(e, st, 'batch', 'batch add to library');
    } finally {
      if (anyAccepted) {
        try {
          await syncLibrary();
        } catch (e) {
          logger.warning('Sync after batch add failed (${e.runtimeType})');
        }
      }
    }
    return created;
  }

  Future<void> deleteEntry(String seriesId) async {
    logger.info('Deleting library entry');
    final token = await auth.getValidAccessToken();
    final url = Uri.parse('${LibraryConstants.baseUrl}/$seriesId');
    try {
      // Headers without Content-Type — DELETE has no body.
      final response = await http
          .delete(url, headers: _buildAuthHeaders(token, json: false))
          .timeout(
            const Duration(seconds: AppConstants.networkTimeoutSeconds),
            onTimeout: () => throw TimeoutException('Delete entry request timed out'),
          );

      _assertAuthorized(response, seriesId);
      if (response.statusCode == 200 || response.statusCode == 404) {
        // 404 means already deleted on the server — still clean up locally.
        logger.info(
          'Library entry deleted from server (or already gone); updating DB',
        );
        await database.libraryEntriesDao.deleteEntry(seriesId);
      } else {
        logger.severe(
          'Failed to delete library entry (HTTP ${response.statusCode})',
        );
        throw ApiException(
          message: 'Failed to delete library entry',
          statusCode: response.statusCode,
          responseBody: response.body,
          code: 'DELETE_ENTRY_FAILED',
        );
      }
    } catch (e, st) {
      _rethrowAsAppException(e, st, seriesId, 'delete library entry');
    }
  }

  Future<void> clearLibrary() async {
    logger.info('User requested full library clear');
    try {
      setIsSyncCancelled(true);
      resetInitialSyncTask();
      await database.libraryEntriesDao.deleteAllEntries();
      logger.info('Local library database cleared');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.lastSyncKey);
      await prefs.remove(_isIncompleteKey);
      logger.info('Library sync preferences reset');
    } catch (e) {
      logger.severe('Failed to clear library (${e.runtimeType})');
    }
  }
}
