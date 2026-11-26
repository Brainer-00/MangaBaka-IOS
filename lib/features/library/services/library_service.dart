import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:mangabaka_app/core/database/database.dart' as db;
import 'package:mangabaka_app/features/library/models/library_entry.dart'
    as api;
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/library/constants/library_constants.dart';
import 'package:mangabaka_app/features/library/services/mappers/db_to_api_mapper.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/mixins/library_crud_mixin.dart';
import 'package:mangabaka_app/features/library/services/mixins/library_sync_mixin.dart';

import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/network/rate_limit_coordinator.dart';

abstract class LibraryServiceBase {
  db.AppDatabase get database;
  http.Client get httpClient;
  ProfileAuthService get auth;
  dynamic get logger;

  ValueNotifier<LibrarySyncStatus> get syncStatus;
  RateLimitCoordinator get rateLimitCoordinator;

  db.LibraryCacheLease? get currentLease => auth.libraryLease;
  db.OwnedLibraryDao get owned => database.ownedLibraryDao;

  db.LibraryCacheLease requireLease() {
    final lease = currentLease;
    if (lease == null) {
      throw AuthException(
        message: 'Library account unavailable',
        code: 'LIBRARY_OWNER_REQUIRED',
      );
    }
    return lease;
  }

  void checkLease(db.LibraryCacheLease lease) {
    if (!identical(currentLease, lease)) {
      throw AuthException(
        message: 'Library session changed',
        code: 'SESSION_CHANGED',
      );
    }
  }

  Future<String> tokenFor(db.LibraryCacheLease lease) async {
    checkLease(lease);
    final token = await auth.getValidAccessToken();
    checkLease(lease);
    return token;
  }

  Future<String> recoverFor(db.LibraryCacheLease lease, String token) async {
    checkLease(lease);
    final recovered = await auth.recoverAfterUnauthorized(token);
    checkLease(lease);
    return recovered;
  }

  Future<void> syncFor(
    db.LibraryCacheLease lease, {
    String? state,
    bool waitForExisting = true,
  });
  void cancelSync();
  void Function() pauseSyncForReconciliation(db.LibraryCacheLease lease);
  Future<bool> confirmLibraryEntryExists(db.LibraryCacheLease lease, String id);
  Future<FetchPageResult> fetchPage(
    db.LibraryCacheLease lease,
    int page, {
    String? state,
  });
}

class LibraryService extends LibraryServiceBase
    with LibraryCrudMixin, LibrarySyncMixin {
  final _logger = LoggingService.logger;
  final ProfileAuthService _auth;
  final db.AppDatabase _db;
  final http.Client _httpClient;

  @visibleForTesting
  final LibraryWatchInstrumentation? watchInstrumentation;

  @override
  final RateLimitCoordinator rateLimitCoordinator;

  @override
  db.AppDatabase get database => _db;

  @override
  http.Client get httpClient => _httpClient;

  @override
  ProfileAuthService get auth => _auth;

  @override
  dynamic get logger => _logger;

  @override
  ValueNotifier<LibrarySyncStatus> get syncStatus => _syncStatus;

  final _syncStatus = ValueNotifier(const LibrarySyncStatus());

  Future<void> saveEntries(List<api.LibraryEntry> entries) async {
    final lease = requireLease();
    await owned.upsertEntries(
      lease,
      entries,
      beforeCommit: () => checkLease(lease),
    );
    checkLease(lease);
  }

  LibraryService({
    required ProfileAuthService auth,
    db.AppDatabase? database,
    http.Client? httpClient,
    RateLimitCoordinator? rateLimitCoordinator,
    this.watchInstrumentation,
  }) : _auth = auth,
       _db = database ?? getIt<db.AppDatabase>(),
       _httpClient = httpClient ?? http.Client(),
       rateLimitCoordinator =
           rateLimitCoordinator ?? RateLimitCoordinator.shared {
    _observedLease = currentLease;
    _auth.addListener(_sessionChanged);
  }

  db.LibraryCacheLease? _observedLease;

  void _sessionChanged() {
    final lease = currentLease;
    if (identical(lease, _observedLease)) return;
    _observedLease = lease;
    cancelSync();
  }

  void dispose() {
    _auth.removeListener(_sessionChanged);
    cancelSync();
    _httpClient.close();
    _syncStatus.dispose();
  }

  Future<Set<String>> existingSeriesIds(
    db.LibraryCacheLease lease,
    Iterable<String> ids,
  ) async {
    checkLease(lease);
    final state = await owned.readState(lease.owner);
    checkLease(lease);
    if (state?.initialized != true ||
        state?.active != true ||
        state?.generation != lease.generation) {
      throw AuthException(
        message: 'Library cache unavailable',
        code: 'LIBRARY_CACHE_REQUIRED',
      );
    }
    final result = await owned.existingSeriesIds(lease.owner, ids);
    checkLease(lease);
    return result;
  }

  Stream<api.LibraryEntry?> watchEntryFromDb(String seriesId) => _watchOwned(
    (owner) => owned
        .watchEntry(owner, seriesId)
        .map((row) => row == null ? null : DbToApiMapper.ownedEntryFromDb(row)),
    followSession: true,
    onInvalidated: (stream) => stream.addSync(null),
  );

  Stream<List<api.LibraryEntry>> watchEntriesFromDb() {
    final stream = _watchOwned(
      (owner) => owned.watchEntries(owner).map((rows) {
        watchInstrumentation?.queryExecutions++;
        watchInstrumentation?.mappingPasses++;
        return rows.map(DbToApiMapper.ownedEntryFromDb).toList();
      }),
    );
    final instrumentation = watchInstrumentation;
    return instrumentation == null
        ? stream
        : _SubscriptionCountingStream(stream, instrumentation);
  }

  // No rows are advertised until the cache has a complete baseline. A
  // detached Drift subscription may still have events queued, so guard delivery.
  Stream<T> _watchOwned<T>(
    Stream<T> Function(db.VerifiedLibraryOwner) query, {
    bool followSession = false,
    void Function(MultiStreamController<T>)? onInvalidated,
  }) {
    final initial = currentLease;
    return Stream.multi((out) {
      StreamSubscription<db.LibraryCacheState?>? stateSubscription;
      StreamSubscription<T>? rows;
      db.LibraryCacheLease? bound;
      var started = false;
      void detach() {
        unawaited(stateSubscription?.cancel());
        unawaited(rows?.cancel());
        stateSubscription = null;
        rows = null;
      }

      void update() {
        final lease = currentLease;
        if (started && identical(lease, bound)) return;
        final changed = started;
        started = true;
        bound = lease;
        detach();
        if (!followSession && (lease == null || !identical(lease, initial))) {
          out.closeSync();
          return;
        }
        if (changed || lease == null) onInvalidated?.call(out);
        if (lease == null) return;
        bool live() =>
            identical(currentLease, lease) && identical(bound, lease);
        void error(Object error, StackTrace stack) {
          if (live()) out.addErrorSync(error, stack);
        }

        stateSubscription = owned.watchState(lease.owner).listen((state) {
          if (!live()) return;
          if (state?.active != true || state?.generation != lease.generation) {
            // A newly attached subscriber can receive Drift's earlier cached
            // state before the activation update is reflected in the query.
            if (rows == null) return;
            detach();
            if (followSession) {
              onInvalidated?.call(out);
            } else {
              out.closeSync();
            }
            return;
          }
          if (state?.initialized != true || rows != null) return;
          rows = query(lease.owner).listen((value) {
            if (live()) out.addSync(value);
          }, onError: error);
        }, onError: error);
      }

      _auth.addListener(update);
      out.onCancel = () {
        _auth.removeListener(update);
        detach();
      };
      update();
    });
  }

  @override
  Future<FetchPageResult> fetchPage(
    db.LibraryCacheLease lease,
    int page, {
    String? state,
  }) async {
    final token = await tokenFor(lease);
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': LibraryConstants.pageLimit.toString(),
    };
    if (state != null) queryParams['state'] = state;
    queryParams['sort_by'] = 'updated_at_desc';

    final uri = Uri.parse(
      LibraryConstants.baseUrl,
    ).replace(queryParameters: queryParams);
    _logger.info('Fetching library page $page');

    try {
      var currentToken = token;
      var unauthorizedRecoveryAttempted = false;
      var admissionRequired = false;
      for (var retries = 0; ;) {
        final waitedForCooldown = await rateLimitCoordinator.waitForCooldown();
        if (waitedForCooldown || admissionRequired) {
          await rateLimitCoordinator.waitForRetryAdmission();
        }
        admissionRequired = false;
        checkLease(lease);
        final response = await _httpClient
            .get(
              uri,
              headers: {
                'Authorization': 'Bearer $currentToken',
                'User-Agent': LibraryConstants.userAgent,
              },
            )
            .timeout(Duration(seconds: AppConstants.networkTimeoutSeconds));

        _logger.fine(
          'Library page $page fetch completed with status ${response.statusCode}',
        );

        checkLease(lease);
        if (response.statusCode == 429) {
          rateLimitCoordinator.updateFromRetryAfter(
            RateLimitCoordinator.retryAfterHeader(response.headers),
          );
          if (retries >= AppConstants.maxRetries) {
            _logger.severe(
              'Rate limited while fetching library page $page after bounded retries',
            );
            throw ApiException(
              message: 'Too many requests. Please try again later.',
              statusCode: 429,
              code: 'RATE_LIMITED',
            );
          }
          retries++;
          admissionRequired = true;
          _logger.warning(
            'Rate limited while fetching library page $page; retrying after cooldown',
          );
          continue;
        }

        if (response.statusCode == 401) {
          _logger.severe('Unauthorized fetch request for library page $page');
          if (!unauthorizedRecoveryAttempted) {
            unauthorizedRecoveryAttempted = true;
            currentToken = await recoverFor(lease, currentToken);
            continue;
          }
          throw AuthException(message: 'Auth failed', code: 'AUTH_FAILED');
        }
        if (response.statusCode == 400) {
          _logger.warning('Bad request for library page $page (HTTP 400)');
          return FetchPageResult(entries: [], isError: true);
        }
        if (response.statusCode != 200) {
          _logger.severe(
            'Failed to fetch library page $page '
            '(HTTP ${response.statusCode})',
          );
          throw ApiException(
            message: 'Fetch failed',
            statusCode: response.statusCode,
          );
        }

        final result = await compute(_parseLibraryPage, response.body);
        checkLease(lease);
        final next = result.next;
        if (next != null) {
          final continuation = uri.resolve(next);
          if (continuation.origin != uri.origin ||
              continuation.path != uri.path ||
              continuation.hasFragment ||
              continuation.userInfo.isNotEmpty ||
              (continuation.queryParameters.containsKey('state') &&
                  continuation.queryParameters['state'] != state) ||
              continuation.queryParameters['page'] != '${page + 1}') {
            throw const FormatException('Unexpected Library pagination link');
          }
        }
        _logger.info(
          'Successfully parsed ${result.entries.length} entries for library page $page',
        );
        return result;
      }
    } catch (e) {
      _logger.severe(
        'Exception occurred while fetching library page $page '
        '(${e.runtimeType})',
      );
      rethrow;
    }
  }
}

@visibleForTesting
class LibraryWatchInstrumentation {
  int subscriptions = 0;
  int queryExecutions = 0;
  int mappingPasses = 0;
}

class _SubscriptionCountingStream<T> extends Stream<T> {
  _SubscriptionCountingStream(this._source, this._instrumentation);

  final Stream<T> _source;
  final LibraryWatchInstrumentation _instrumentation;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _instrumentation.subscriptions++;
    return _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class FetchPageResult {
  final List<api.LibraryEntry> entries;
  final bool isError;
  final String? next;
  final int? count;
  FetchPageResult({
    required this.entries,
    this.isError = false,
    this.next,
    this.count,
  });
}

FetchPageResult _parseLibraryPage(String responseBody) {
  final body = jsonDecode(responseBody) as Map<String, dynamic>;
  if (body.containsKey('status') && body['status'] != 200) {
    throw const FormatException('Invalid Library page status');
  }
  final data = body['data'];
  if (data is! List) throw const FormatException('Invalid Library page');
  final pagination = body['pagination'];
  if (pagination is! Map || !pagination.containsKey('next')) {
    throw const FormatException('Library page has no pagination metadata');
  }
  final next = pagination['next'];
  final count = pagination['count'];
  if ((next != null && (next is! String || next.isEmpty)) ||
      (count != null && (count is! int || count < 0))) {
    throw const FormatException('Invalid Library pagination metadata');
  }
  final entries = data
      .map((item) => api.LibraryEntry.fromJson(item as Map<String, dynamic>))
      .toList();
  return FetchPageResult(
    entries: entries,
    next: next as String?,
    count: count as int?,
  );
}
