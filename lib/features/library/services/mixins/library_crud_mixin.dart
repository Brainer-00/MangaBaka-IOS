import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/features/library/constants/library_constants.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';

mixin LibraryCrudMixin on LibraryServiceBase {
  static const int batchLimit = 100;
  final _tails = <(LibraryCacheLease, String), Future<void>>{};

  // Reserve all participating series before waiting. New sessions have their
  // own queue and an old callback always retains its original lease.
  Future<T> _enqueue<T>(
    Iterable<String> seriesIds,
    Future<T> Function(LibraryCacheLease) action,
  ) async {
    final lease = requireLease();
    final keys = seriesIds.toSet().map((id) => (lease, id)).toList();
    final pending = keys.map((key) => _tails[key]).whereType<Future<void>>();
    final ready = Future.wait(pending);
    final operation = ready.then((_) {
      checkLease(lease);
      return action(lease);
    });
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    for (final key in keys) {
      _tails[key] = tail;
    }
    try {
      return await operation;
    } finally {
      for (final key in keys) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }
    }
  }

  Future<http.Response> _send(
    LibraryCacheLease lease,
    String seriesId, {
    required String method,
    required Set<int> success,
    required String failureCode,
    Object? body,
  }) async {
    try {
      final token = await tokenFor(lease);
      final url = Uri.parse('${LibraryConstants.baseUrl}/$seriesId');
      final headers = {
        'Authorization': 'Bearer $token',
        'User-Agent': LibraryConstants.userAgent,
        if (body != null) 'Content-Type': 'application/json',
      };
      checkLease(lease);
      final encoded = body == null ? null : jsonEncode(body);
      final response = await (switch (method) {
        'PUT' => httpClient.put(url, headers: headers, body: encoded),
        'POST' => httpClient.post(url, headers: headers, body: encoded),
        'DELETE' => httpClient.delete(url, headers: headers),
        _ => throw ArgumentError('Unsupported Library method'),
      }).timeout(const Duration(seconds: AppConstants.networkTimeoutSeconds));

      checkLease(lease);
      if (response.statusCode == 401) {
        await recoverFor(lease, token);
        throw AuthException(
          message: 'Authentication was refreshed. Please retry the action.',
          code: 'AUTH_RETRY_REQUIRED',
        );
      }
      rateLimitCoordinator.throwIfRateLimited(
        statusCode: response.statusCode,
        headers: response.headers,
      );
      if (!success.contains(response.statusCode)) {
        throw ApiException(
          message: 'Library operation failed',
          statusCode: response.statusCode,
          code: failureCode,
        );
      }
      return response;
    } on TimeoutException {
      throw NetworkException(message: 'Request timed out.', code: 'TIMEOUT');
    } on SocketException {
      throw NetworkException(message: 'Network error.', code: 'NETWORK_ERROR');
    } on http.ClientException {
      throw NetworkException(message: 'Network error.', code: 'NETWORK_ERROR');
    }
  }

  Future<void> updateLibraryEntryState(String seriesId, String state) =>
      _enqueue([seriesId], (lease) async {
        await _send(
          lease,
          seriesId,
          method: 'PUT',
          success: {200},
          failureCode: 'UPDATE_STATE_FAILED',
          body: {'state': state},
        );
        await owned.updateQuickFields(
          lease,
          seriesId,
          state: Value(state),
          beforeCommit: () => checkLease(lease),
        );
        checkLease(lease);
      });

  Future<void> updateLibraryEntryRating(String seriesId, int rating) =>
      _enqueue([seriesId], (lease) async {
        await _send(
          lease,
          seriesId,
          method: 'PUT',
          success: {200},
          failureCode: 'UPDATE_RATING_FAILED',
          body: {'rating': rating},
        );
        await owned.updateQuickFields(
          lease,
          seriesId,
          rating: Value(rating == 0 ? null : rating),
          beforeCommit: () => checkLease(lease),
        );
        checkLease(lease);
      });

  Future<void> updateLibraryEntryProgress(
    String seriesId, {
    int? progressChapter,
    int? progressVolume,
  }) => _enqueue([seriesId], (lease) async {
    final snapshot = (await owned.findEntry(lease.owner, seriesId))?.entry;
    checkLease(lease);
    final startsReading =
        snapshot?.state == 'plan_to_read' &&
        ((progressChapter ?? 0) > 0 || (progressVolume ?? 0) > 0);
    final nextState = startsReading ? 'reading' : null;
    if (progressChapter == null && progressVolume == null) return;
    // The quick-action widget owns optimistic display and rollback. Keep the
    // durable row confirmed so logout cannot strand speculative progress.
    await _send(
      lease,
      seriesId,
      method: 'PUT',
      success: {200},
      failureCode: 'UPDATE_PROGRESS_FAILED',
      body: {
        'progress_chapter': ?progressChapter,
        'progress_volume': ?progressVolume,
        'state': ?nextState,
      },
    );
    await owned.updateQuickFields(
      lease,
      seriesId,
      progressChapter: progressChapter == null
          ? const Value.absent()
          : Value(progressChapter == 0 ? null : progressChapter),
      progressVolume: progressVolume == null
          ? const Value.absent()
          : Value(progressVolume == 0 ? null : progressVolume),
      state: nextState == null ? const Value.absent() : Value(nextState),
      beforeCommit: () => checkLease(lease),
    );
    checkLease(lease);
  });

  Future<void> createLibraryEntry(String seriesId, String state) =>
      _enqueue([seriesId], (lease) async {
        await _send(
          lease,
          seriesId,
          method: 'POST',
          success: {201},
          failureCode: 'CREATE_ENTRY_FAILED',
          body: {'state': state},
        );
        await syncFor(lease);
        checkLease(lease);
      });

  Future<int> createLibraryEntriesBatch(
    List<String> seriesIds,
    String state,
  ) async {
    final ids = seriesIds.map(int.tryParse).whereType<int>().toSet().toList();
    if (ids.isEmpty) return 0;
    return _enqueue(ids.map((id) => '$id'), (lease) async {
      var created = 0;
      var anyAccepted = false;
      try {
        for (var i = 0; i < ids.length; i += batchLimit) {
          final chunk = ids.skip(i).take(batchLimit);
          final response = await _send(
            lease,
            'batch',
            method: 'POST',
            success: {200},
            failureCode: 'BATCH_CREATE_FAILED',
            body: [
              for (final id in chunk) {'series_id': id, 'state': state},
            ],
          );
          anyAccepted = true;
          final data = (jsonDecode(response.body) as Map)['data'];
          if (data is List) {
            created += data
                .where((e) => e is Map && e['action'] == 'created')
                .length;
          }
        }
      } finally {
        if (anyAccepted && identical(lease, currentLease)) {
          try {
            await syncFor(lease);
          } catch (error) {
            logger.warning(
              'Sync after batch add failed (${error.runtimeType})',
            );
          }
        }
      }
      checkLease(lease);
      return created;
    });
  }

  Future<void> deleteEntry(String seriesId) =>
      _enqueue([seriesId], (lease) async {
        await _send(
          lease,
          seriesId,
          method: 'DELETE',
          success: {200, 404},
          failureCode: 'DELETE_ENTRY_FAILED',
        );
        await owned.deleteEntry(
          lease,
          seriesId,
          beforeCommit: () => checkLease(lease),
        );
        checkLease(lease);
      });
}
