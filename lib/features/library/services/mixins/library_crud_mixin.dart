import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/network/rate_limit_coordinator.dart';
import 'package:mangabaka_app/features/library/constants/library_constants.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/features/library/services/mappers/db_to_api_mapper.dart';
import 'package:mangabaka_app/features/series/services/series_service.dart';

part 'library_collections.dart';

mixin LibraryCrudMixin on LibraryServiceBase {
  static const int batchLimit = 100;
  static const _collectionsKey = 'collections';
  final _tails = <(LibraryCacheLease, String), Future<void>>{};
  final collectionsRevision = ValueNotifier<int>(0);

  // Reserve all participating series before waiting. New sessions have their
  // own queue and an old callback always retains its original lease.
  Future<T> _enqueue<T>(
    Iterable<String> seriesIds,
    Future<T> Function(LibraryCacheLease) action, {
    LibraryCacheLease? originalLease,
  }) async {
    final lease = originalLease ?? requireLease();
    checkLease(lease);
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
    Uri? uri,
    void Function(http.Response)? onResponse,
  }) async {
    try {
      final token = await tokenFor(lease);
      final url = uri ?? Uri.parse('${LibraryConstants.baseUrl}/$seriesId');
      final headers = {
        'Authorization': 'Bearer $token',
        'User-Agent': LibraryConstants.userAgent,
        if (body != null) 'Content-Type': 'application/json',
      };
      checkLease(lease);
      final encoded = body == null ? null : jsonEncode(body);
      final response =
          await (uri != null
                  ? _request(method, url, headers, body: encoded)
                  : switch (method) {
                      'PUT' => httpClient.put(
                        url,
                        headers: headers,
                        body: encoded,
                      ),
                      'POST' =>
                        onResponse == null
                            ? httpClient.post(
                                url,
                                headers: headers,
                                body: encoded,
                              )
                            : _request('POST', url, headers, body: encoded),
                      'DELETE' => httpClient.delete(url, headers: headers),
                      'PATCH' => _request('PATCH', url, headers, body: encoded),
                      _ => throw ArgumentError('Unsupported Library method'),
                    })
              .timeout(
                const Duration(seconds: AppConstants.networkTimeoutSeconds),
              );

      onResponse?.call(response);
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

  Future<http.Response> _request(
    String method,
    Uri uri,
    Map<String, String> headers, {
    String? body,
  }) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) request.body = body;
    return http.Response.fromStream(await httpClient.send(request));
  }

  Future<http.Response> _read(LibraryCacheLease lease, Uri uri) async {
    var token = await tokenFor(lease);
    var recovered = false;
    var retries = 0;
    try {
      while (true) {
        final waited = await rateLimitCoordinator.waitForCooldown();
        if (waited || retries > 0) {
          await rateLimitCoordinator.waitForRetryAdmission();
        }
        checkLease(lease);
        final response = await _request('GET', uri, {
          'Authorization': 'Bearer $token',
          'User-Agent': LibraryConstants.userAgent,
        }).timeout(const Duration(seconds: AppConstants.networkTimeoutSeconds));
        checkLease(lease);
        if (response.statusCode == 401) {
          if (recovered) {
            throw AuthException(
              message: 'Authentication failed',
              code: 'AUTH_FAILED',
            );
          }
          token = await recoverFor(lease, token);
          recovered = true;
          continue;
        }
        if (response.statusCode == 429 && retries < AppConstants.maxRetries) {
          retries++;
          rateLimitCoordinator.updateFromRetryAfter(
            RateLimitCoordinator.retryAfterHeader(response.headers),
          );
          continue;
        }
        rateLimitCoordinator.throwIfRateLimited(
          statusCode: response.statusCode,
          headers: response.headers,
        );
        return response;
      }
    } on TimeoutException {
      throw NetworkException(message: 'Request timed out.', code: 'TIMEOUT');
    } on SocketException {
      throw NetworkException(message: 'Network error.', code: 'NETWORK_ERROR');
    } on http.ClientException {
      throw NetworkException(message: 'Network error.', code: 'NETWORK_ERROR');
    }
  }

  int _seriesNumber(String id) {
    final value = int.tryParse(id);
    if (value == null || value <= 0 || value > 2147483647 || '$value' != id) {
      throw ArgumentError('Invalid Library series ID');
    }
    return value;
  }

  Map<String, dynamic> _editorEnvelope(
    http.Response response, {
    bool requiresData = true,
  }) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic> &&
          json['status'] == response.statusCode &&
          (!requiresData || json.containsKey('data'))) {
        return json;
      }
    } on FormatException {
      // Retain a safe error message without the response content.
    }
    throw const FormatException('Invalid Library response envelope');
  }

  Future<LibraryEntry?> fetchAuthoritativeLibraryEntry(
    String seriesId, {
    LibraryCacheLease? lease,
  }) => _enqueue(
    [seriesId, _collectionsKey],
    (captured) => _readEntry(captured, seriesId, reconcile: true),
    originalLease: lease,
  );

  // The snapshot owns the transaction and run fence for these reads.
  @override
  Future<bool> confirmLibraryEntryExists(
    LibraryCacheLease lease,
    String id,
  ) async => await _readEntry(lease, id, reconcile: false) != null;

  Future<LibraryEntry?> _readEntry(
    LibraryCacheLease lease,
    String seriesId, {
    required bool reconcile,
  }) async {
    final number = _seriesNumber(seriesId);
    final response = await _read(
      lease,
      Uri.parse('${LibraryConstants.baseUrl}/$number'),
    );
    if (response.statusCode == 404) {
      Object? error;
      try {
        error = jsonDecode(response.body);
      } on FormatException {
        throw const FormatException('Invalid Library not-found response');
      }
      if (error is! Map || error['status'] != 404) {
        throw const FormatException('Invalid Library not-found response');
      }
      if (reconcile) {
        final resume = pauseSyncForReconciliation(lease);
        try {
          await owned.deleteEntry(
            lease,
            seriesId,
            beforeCommit: () => checkLease(lease),
          );
          checkLease(lease);
        } finally {
          resume();
        }
      }
      return null;
    }
    if (response.statusCode != 200) {
      throw ApiException(
        message: 'Library entry read failed',
        statusCode: response.statusCode,
      );
    }
    final data = _editorEnvelope(response)['data'];
    if (data is! Map<String, dynamic> ||
        !_validEditorId(data['series_id']) ||
        data['series_id'] != number ||
        data['user_id'] != lease.owner.id ||
        !_validEditorId(data['id']) ||
        !LibraryEntryDraft.states.contains(data['state'])) {
      throw const FormatException('Invalid Library entry identity or state');
    }
    final memberships = data['Entries'];
    List<int>? listIds;
    if (data.containsKey('Entries')) {
      if (memberships is! List) {
        throw const FormatException('Invalid Library memberships');
      }
      listIds = [
        for (final item in memberships)
          if (item is Map &&
              _validEditorId(item['library_entry_id']) &&
              item['library_entry_id'] == data['id'] &&
              _validEditorId(item['library_list_id']))
            item['library_list_id'] as int
          else
            throw const FormatException('Invalid Library membership'),
      ];
      if (listIds.length > 30 || listIds.toSet().length != listIds.length) {
        throw const FormatException('Invalid Library membership count');
      }
    }
    final cached = await database.seriesDao.findSeries(seriesId);
    checkLease(lease);
    final series = cached == null
        ? await getIt<SeriesService>().fetchSeries(seriesId)
        : DbToApiMapper.seriesFromDb(cached);
    checkLease(lease);
    if (series.id != seriesId) {
      throw const FormatException('Invalid Library series metadata');
    }
    LibraryEntry entry;
    try {
      entry = LibraryEntry(
        id: '${data['id']}',
        state: data['state'] as String,
        series: series,
        note: data['note'] as String?,
        readLink: data['read_link'] as String?,
        progressChapter: _wholeTrackingValue(data['progress_chapter']),
        progressVolume: _wholeTrackingValue(data['progress_volume']),
        numberOfRereads: _wholeTrackingValue(data['number_of_rereads']),
        rating: _wholeTrackingValue(data['rating']),
        priority: (data['priority'] as num?)?.toDouble(),
        startDate: data['start_date'] as String?,
        finishDate: data['finish_date'] as String?,
        isPrivate: data['is_private'] as bool?,
        listIds: listIds,
        explicitNullFields: {
          for (final field in data.entries)
            if (field.value == null) field.key,
        },
      );
    } on TypeError {
      throw const FormatException('Invalid Library tracking fields');
    }
    if (reconcile) {
      // An older page may already be waiting to commit. Invalidate that sync
      // before persisting this snapshot through the owned transaction.
      final resume = pauseSyncForReconciliation(lease);
      try {
        await owned.upsertEntries(lease, [
          entry,
        ], beforeCommit: () => checkLease(lease));
        checkLease(lease);
      } finally {
        resume();
      }
    }
    return entry;
  }

  bool _validEditorId(Object? id) => id is int && id > 0 && id <= 2147483647;

  int? _wholeTrackingValue(Object? value) {
    if (value == null) return null;
    // The tracking model and Drift columns store whole numbers.
    if (value is num && value.isFinite && value == value.toInt()) {
      return value.toInt();
    }
    throw const FormatException('Unsupported Library tracking number');
  }

  Future<List<AccountLibraryList>> fetchAccountLibraryLists(
    LibraryCacheLease lease,
  ) => _enqueue(
    [_collectionsKey],
    (lease) => _fetchAccountLibraryLists(lease, strict: false),
    originalLease: lease,
  );

  Future<List<AccountLibraryList>> _fetchAccountLibraryLists(
    LibraryCacheLease lease, {
    required bool strict,
  }) => _collectionPages<AccountLibraryList, int>(
    lease,
    _collectionUri(LibraryCollections._listsPath),
    (item) => _parseAccountList(item, strict: strict),
    (item) => item.id,
    strict: strict,
  );

  Future<LibrarySaveResult> createCompleteLibraryEntry(
    LibraryEntryDraft draft,
  ) => _saveDraft(draft, create: true);

  Future<LibrarySaveResult> updateCompleteLibraryEntry(
    LibraryEntryDraft draft,
  ) => _saveDraft(draft, create: false);

  Future<LibrarySaveResult> _saveDraft(
    LibraryEntryDraft draft, {
    required bool create,
  }) => _enqueue([draft.seriesId, _collectionsKey], (lease) async {
    _seriesNumber(draft.seriesId);
    final payload = draft.toJson();
    final originalLists = draft.originalListIds;
    if (!create && draft.lists.supplied && originalLists != null) {
      final latest = await _readEntry(lease, draft.seriesId, reconcile: false);
      if (latest == null) {
        throw ApiException(message: 'Library entry not found', statusCode: 404);
      }
      final current = latest.listIds;
      if (current == null) {
        throw ApiException(
          message: 'Library memberships unavailable',
          statusCode: 409,
        );
      }
      final selected = draft.lists.value!.toSet();
      final rebased = current.toSet()
        ..removeAll(originalLists.difference(selected))
        ..addAll(selected.difference(originalLists));
      if (rebased.length > 30) {
        throw ArgumentError('Too many Library memberships');
      }
      if (rebased.length == current.length && rebased.containsAll(current)) {
        payload.remove('lists');
      } else {
        payload['lists'] = rebased.toList()..sort();
      }
    }
    if (!create && payload.isEmpty) {
      final entry = await _readEntry(lease, draft.seriesId, reconcile: true);
      if (entry == null) {
        throw ApiException(message: 'Library entry not found', statusCode: 404);
      }
      return LibrarySaveResult(LibrarySaveOutcome.saved, entry: entry);
    }
    if (create) {
      // Do not turn an explicit create into an edit of a known entry.
      final existing = await _readEntry(
        lease,
        draft.seriesId,
        reconcile: false,
      );
      if (existing != null) {
        throw ApiException(
          message: 'Library entry already exists',
          statusCode: 409,
          code: 'ENTRY_EXISTS',
        );
      }
    }
    var accepted = false;
    var outcome = LibrarySaveOutcome.saved;
    try {
      {
        final status = create ? 201 : 200;
        final result = await _send(
          lease,
          draft.seriesId,
          method: create ? 'POST' : 'PATCH',
          success: {status},
          failureCode: create ? 'CREATE_ENTRY_FAILED' : 'UPDATE_ENTRY_FAILED',
          body: payload,
          onResponse: (response) {
            if (response.statusCode != status) return;
            try {
              accepted = _editorEnvelope(response)['data'] == true;
            } on FormatException {
              // A malformed success response is ambiguous.
            }
          },
        );
        final confirmed = _editorEnvelope(result)['data'];
        if (confirmed == false) {
          throw ApiException(
            message: 'Library write declined',
            statusCode: status,
            code: 'WRITE_DECLINED',
          );
        }
        if (!accepted) outcome = LibrarySaveOutcome.uncertain;
      }
    } on NetworkException {
      outcome = LibrarySaveOutcome.uncertain;
    } on FormatException {
      outcome = LibrarySaveOutcome.uncertain;
    } on ApiException catch (error) {
      if (error.statusCode < 500 || error.statusCode >= 600) rethrow;
      outcome = LibrarySaveOutcome.uncertain;
    } on AuthException {
      if (!accepted) rethrow;
      return const LibrarySaveResult(LibrarySaveOutcome.refreshPending);
    }
    if (identical(currentLease, lease) && draft.lists.supplied) {
      collectionsRevision.value++;
    }
    try {
      final entry = await _readEntry(lease, draft.seriesId, reconcile: true);
      if (entry != null) return LibrarySaveResult(outcome, entry: entry);
    } on Exception {
      // The write outcome is independent of a failed readback or cache write.
    }
    return LibrarySaveResult(
      accepted
          ? LibrarySaveOutcome.refreshPending
          : LibrarySaveOutcome.uncertain,
    );
  }, originalLease: draft.lease);

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
        final resume = pauseSyncForReconciliation(lease);
        try {
          await owned.updateQuickFields(
            lease,
            seriesId,
            state: Value(state),
            beforeCommit: () => checkLease(lease),
          );
        } finally {
          resume();
        }
        checkLease(lease);
      });

  Future<LibrarySaveResult> updateLibraryEntryRating(
    String seriesId,
    int rating, {
    LibraryCacheLease? lease,
  }) async {
    final result = await updateCompleteLibraryEntry(
      LibraryEntryDraft(
        lease: lease ?? requireLease(),
        seriesId: seriesId,
        rating: EntryField.set(rating),
      ),
    );
    if (result.outcome == LibrarySaveOutcome.saved &&
        result.entry?.rating != (rating == 0 ? null : rating)) {
      return LibrarySaveResult(
        LibrarySaveOutcome.refreshPending,
        entry: result.entry,
      );
    }
    return result;
  }

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
    final resume = pauseSyncForReconciliation(lease);
    try {
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
    } finally {
      resume();
    }
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
      _enqueue([seriesId, _collectionsKey], (lease) async {
        await _send(
          lease,
          seriesId,
          method: 'DELETE',
          success: {200, 404},
          failureCode: 'DELETE_ENTRY_FAILED',
        );
        final resume = pauseSyncForReconciliation(lease);
        try {
          await owned.deleteEntry(
            lease,
            seriesId,
            beforeCommit: () => checkLease(lease),
          );
        } finally {
          resume();
        }
        checkLease(lease);
        collectionsRevision.value++;
      });
}
