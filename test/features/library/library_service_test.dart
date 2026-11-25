import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/network/rate_limit_coordinator.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/controllers/library_session.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:drift/native.dart';

class MockProfileAuthService extends ProfileAuthService {
  String accessToken = 'access-old';
  String recoveredToken = 'access-new';
  Object? recoveryError;
  final rejectedTokens = <String>[];

  @override
  bool get isLoggedIn => libraryLease != null;

  @override
  LibraryCacheLease? libraryLease;

  void useLease(LibraryCacheLease? lease) {
    libraryLease = lease;
    notifyListeners();
  }

  @override
  Future<String> getValidAccessToken() async => accessToken;

  @override
  Future<String> recoverAfterUnauthorized(String rejectedAccessToken) async {
    rejectedTokens.add(rejectedAccessToken);
    final error = recoveryError;
    if (error != null) throw error;
    accessToken = recoveredToken;
    return recoveredToken;
  }
}

class _PauseOwnedInsert extends QueryInterceptor {
  final inserted = Completer<void>();
  final release = Completer<void>();

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runInsert(executor, statement, args);
    if (statement.contains('owned_library_entries') && !inserted.isCompleted) {
      inserted.complete();
      await release.future;
    }
    return result;
  }
}

class _CappedLibraryService extends LibraryService {
  _CappedLibraryService({required super.auth, required super.httpClient});

  @override
  int get maxSyncPages => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LibraryService service;
  late MockProfileAuthService mockAuth;

  Future<T> runWithServiceClient<T>(
    Future<T> Function() operation,
    http.Client Function() clientFactory,
  ) {
    final client = clientFactory();
    service = LibraryService(
      auth: mockAuth,
      database: getIt<AppDatabase>(),
      httpClient: client,
    );
    return operation();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<AppDatabase>(
      AppDatabase.forTesting(NativeDatabase.memory()),
    );

    mockAuth = MockProfileAuthService();
    final owned = getIt<AppDatabase>().ownedLibraryDao;
    final lease = await owned.activate(
      VerifiedLibraryOwner.fromVerifiedAccountId('account-a'),
    );
    mockAuth.useLease(lease);
    await owned.finishFullImport(lease, completeSeriesIds: {}, watermark: null);
    service = LibraryService(auth: mockAuth);
  });

  tearDown(() async {
    await getIt<AppDatabase>().close();
    await resetServiceLocator();
  });

  Future<void> seedEntry({
    String state = 'plan_to_read',
    int chapter = 0,
    int volume = 0,
  }) async {
    final database = getIt<AppDatabase>();
    await database
        .into(database.seriesTable)
        .insert(
          SeriesTableCompanion.insert(
            id: '1',
            title: 'Series One',
            coverUrl: 'cover',
            description: 'description',
          ),
        );
    await database
        .into(database.ownedLibraryEntries)
        .insert(
          OwnedLibraryEntriesCompanion.insert(
            ownerId: mockAuth.libraryLease!.owner.id,
            id: 'entry-1',
            seriesId: '1',
            state: state,
            progressChapter: Value(chapter),
            progressVolume: Value(volume),
          ),
        );
  }

  Future<OwnedLibraryEntry> storedEntry() async {
    final database = getIt<AppDatabase>();
    return (database.select(
      database.ownedLibraryEntries,
    )..where((row) => row.seriesId.equals('1'))).getSingle();
  }

  group('LibraryService', () {
    test(
      'new lease catches up initialized cache once and retries failures',
      () async {
        await seedEntry(state: 'reading', chapter: 2);
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final original = mockAuth.libraryLease!;
        await dao.finishFullImport(
          original,
          completeSeriesIds: {'1'},
          watermark: '2026-01-01T00:00:00Z',
        );
        final lease = await dao.activate(original.owner);
        mockAuth.useLease(lease);
        final pending = Completer<http.Response>();
        final started = Completer<void>();
        var calls = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((_) {
            calls++;
            if (calls == 1) return Future.value(http.Response('{}', 503));
            started.complete();
            return pending.future;
          }),
        );
        await expectLater(
          service.performInitialSyncIfNeeded(),
          throwsA(isA<ApiException>()),
        );
        expect(
          (await dao.findEntry(lease.owner, '1'))!.entry.progressChapter,
          2,
        );
        final a = service.performInitialSyncIfNeeded();
        final b = service.performInitialSyncIfNeeded();
        await started.future;
        expect(calls, 2);
        pending.complete(
          http.Response(
            '{"data":[{"id":"entry-1","state":"reading","progress_chapter":7,"updated_at":"2026-01-02T00:00:00Z","Series":{"id":"1","title":"Series One"}}],"pagination":{"next":null,"count":1}}',
            200,
          ),
        );
        await Future.wait([a, b]);
        expect(
          (await dao.findEntry(lease.owner, '1'))!.entry.progressChapter,
          7,
        );
        expect(
          (await dao.readState(lease.owner))!.watermark,
          '2026-01-02T00:00:00.000Z',
        );
        await service.performInitialSyncIfNeeded();
        expect(calls, 2);
      },
    );
    test(
      'old initial completion cannot change a new account session',
      () async {
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final a = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('stale-a'),
        );
        mockAuth.useLease(a);
        final started = Completer<void>();
        final response = Completer<http.Response>();
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((_) {
            if (!started.isCompleted) {
              started.complete();
              return response.future;
            }
            return Future.value(
              http.Response(
                '{"data":[],"pagination":{"next":null,"count":0}}',
                200,
              ),
            );
          }),
        );
        final visible = <List<LibraryEntry>>[];
        final session = LibrarySession(
          auth: mockAuth,
          library: service,
          onEntries: visible.add,
        );
        addTearDown(session.dispose);
        await started.future;
        final old = service.performInitialSyncIfNeeded();
        final oldResult = expectLater(old, throwsA(isA<AuthException>()));
        mockAuth.useLease(null);
        await dao.invalidate(a);
        final b = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('stale-b'),
        );
        await dao.finishFullImport(
          b,
          completeSeriesIds: {},
          watermark: 'b-watermark',
        );
        mockAuth.useLease(b);
        response.complete(
          http.Response(
            '{"data":[],"pagination":{"next":null,"count":0}}',
            200,
          ),
        );
        await oldResult;
        await service.performInitialSyncIfNeeded();
        expect((await dao.readState(b.owner))!.watermark, 'b-watermark');
        expect(await dao.listEntries(b.owner), isEmpty);
        expect(service.syncStatus.value.isSyncing, isFalse);
        expect(session.isIncomplete, isFalse);
        expect(visible.expand((entries) => entries), isEmpty);
      },
    );
    test('failed shared initialization can be retried', () async {
      final dao = getIt<AppDatabase>().ownedLibraryDao;
      mockAuth.useLease(
        await dao.activate(VerifiedLibraryOwner.fromVerifiedAccountId('retry')),
      );
      var requests = 0;
      service = LibraryService(
        auth: mockAuth,
        httpClient: MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('{}', 503)
              : http.Response(
                  '{"data":[],"pagination":{"next":null,"count":0}}',
                  200,
                );
        }),
      );
      final first = service.performInitialSyncIfNeeded();
      final second = service.performInitialSyncIfNeeded();
      await Future.wait([
        expectLater(first, throwsA(isA<ApiException>())),
        expectLater(second, throwsA(isA<ApiException>())),
      ]);
      await service.performInitialSyncIfNeeded();
      expect(requests, 2);
      expect(await service.isLibraryIncomplete(), isFalse);
    });

    test(
      'manual refresh and LibrarySession share bootstrap completion',
      () async {
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final lease = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('manual'),
        );
        mockAuth.useLease(lease);
        final response = Completer<http.Response>();
        final started = Completer<void>();
        var requests = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((_) {
            requests++;
            started.complete();
            return response.future;
          }),
        );
        final manual = service.syncLibrary();
        await started.future;
        final session = LibrarySession(
          auth: mockAuth,
          library: service,
          onEntries: (_) {},
        );
        addTearDown(session.dispose);
        final initial = service.performInitialSyncIfNeeded();
        expect((await dao.readState(lease.owner))!.initialized, isFalse);
        response.complete(
          http.Response(
            '{"data":[],"pagination":{"next":null,"count":0}}',
            200,
          ),
        );
        await Future.wait([manual, initial]);
        await Future<void>.delayed(Duration.zero);
        expect(requests, 1);
        expect(await service.isLibraryIncomplete(), isFalse);
        expect(session.isIncomplete, isFalse);
      },
    );
    test(
      'concurrent initial sync callers wait for one import and can retry failures',
      () async {
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final lease = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('initial'),
        );
        mockAuth.useLease(lease);
        final response = Completer<http.Response>();
        final started = Completer<void>();
        var calls = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((_) {
            calls++;
            if (!started.isCompleted) started.complete();
            return response.future;
          }),
        );
        var finished = 0;
        final first = service.performInitialSyncIfNeeded().then(
          (_) => finished++,
        );
        final second = service.performInitialSyncIfNeeded().then(
          (_) => finished++,
        );
        await started.future;
        expect(calls, 1);
        expect(finished, 0);
        response.complete(
          http.Response(
            '{"data":[],"pagination":{"next":null,"count":0}}',
            200,
          ),
        );
        await Future.wait([first, second]);
        expect(finished, 2);
        expect((await dao.readState(lease.owner))!.initialized, isTrue);
        await service.performInitialSyncIfNeeded();
        expect(calls, 1);
      },
    );
    test(
      'same-account reconnect closes the old stream and reuses saved rows',
      () async {
        await seedEntry();
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final original = mockAuth.libraryLease!;
        await dao.finishFullImport(
          original,
          completeSeriesIds: {'1'},
          watermark: 'saved',
        );
        final firstRows = Completer<List<LibraryEntry>>();
        final oldClosed = Completer<void>();
        final oldStream = service.watchEntriesFromDb().listen((rows) {
          if (!firstRows.isCompleted) firstRows.complete(rows);
        }, onDone: oldClosed.complete);
        addTearDown(oldStream.cancel);
        expect((await firstRows.future).single.series.id, '1');

        mockAuth.useLease(null);
        final reconnected = await dao.activate(original.owner);
        mockAuth.useLease(reconnected);
        expect(reconnected.generation, greaterThan(original.generation));
        expect(
          (await service.watchEntriesFromDb().first).single.series.id,
          '1',
        );
        expect((await dao.readState(reconnected.owner))!.watermark, 'saved');
        await oldClosed.future;
      },
    );

    test(
      'bulk-import membership requires the current initialized owner',
      () async {
        await seedEntry();
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final a = mockAuth.libraryLease!;
        await dao.finishFullImport(
          a,
          completeSeriesIds: {'1'},
          watermark: null,
        );
        expect(await service.existingSeriesIds(a, ['1', '2']), {'1'});

        final b = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('B'),
        );
        mockAuth.useLease(b);
        await expectLater(
          service.existingSeriesIds(a, ['1']),
          throwsA(isA<AuthException>()),
        );
        await expectLater(
          service.existingSeriesIds(b, ['1']),
          throwsA(isA<AuthException>()),
        );

        await dao.finishFullImport(
          b,
          completeSeriesIds: {'2'},
          watermark: null,
          entries: [
            LibraryEntry.fromJson({
              'id': 'entry-1',
              'state': 'reading',
              'Series': {'id': '2', 'title': 'Series Two'},
            }),
          ],
        );
        expect(await service.existingSeriesIds(b, ['1', '2']), {'2'});
      },
    );

    test(
      'bootstraps 2,000 entries, then accepts a complete empty snapshot',
      () async {
        var empty = false;
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final lease = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('large-owner'),
        );
        mockAuth.useLease(lease);
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((request) async {
            final page = int.parse(request.url.queryParameters['page']!);
            return http.Response(
              jsonEncode({
                'pagination': {
                  'count': empty ? 0 : 2000,
                  'next': empty || page == 20
                      ? null
                      : request.url
                            .replace(
                              queryParameters: {
                                ...request.url.queryParameters,
                                'page': '${page + 1}',
                              },
                            )
                            .toString(),
                },
                'data': [
                  if (!empty)
                    for (var i = (page - 1) * 100; i < page * 100; i++)
                      {
                        'id': 'entry-$i',
                        'state': 'reading',
                        'Series': {'id': 'series-$i', 'title': 'Series $i'},
                      },
                ],
              }),
              200,
            );
          }),
        );
        expect(await service.isLibraryIncomplete(), isTrue);
        await service.syncLibrary();
        expect((await dao.readState(lease.owner))!.initialized, isTrue);
        expect(await service.watchEntriesFromDb().first, hasLength(2000));
        empty = true;
        await service.importFullLibrary();
        expect(await dao.listEntries(lease.owner), isEmpty);
        expect((await dao.readState(lease.owner))!.initialized, isTrue);
      },
    );

    test(
      'failed full import and malformed empty page cannot erase known data',
      () async {
        await seedEntry();
        final lease = mockAuth.libraryLease!;
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        await dao.finishFullImport(
          lease,
          completeSeriesIds: {'1'},
          watermark: '2026-01-01T00:00:00Z',
        );
        var response = http.Response('{"data":[]}', 200);
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((_) async => response),
        );
        await expectLater(service.importFullLibrary(), throwsFormatException);
        response = http.Response(
          '{"data":[],"pagination":{"next":null,"count":1}}',
          200,
        );
        await expectLater(service.importFullLibrary(), throwsFormatException);
        response = http.Response('{}', 503);
        await expectLater(
          service.importFullLibrary(),
          throwsA(isA<ApiException>()),
        );
        expect(await dao.listEntries(lease.owner), hasLength(1));
        expect(
          (await dao.readState(lease.owner))!.watermark,
          '2026-01-01T00:00:00Z',
        );
      },
    );

    test('capped full import keeps previous rows and watermark', () async {
      await seedEntry();
      final lease = mockAuth.libraryLease!;
      final dao = getIt<AppDatabase>().ownedLibraryDao;
      await dao.finishFullImport(
        lease,
        completeSeriesIds: {'1'},
        watermark: 'original',
      );
      service = _CappedLibraryService(
        auth: mockAuth,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"pagination":{"next":"?page=2","count":2},"data":[{"id":"other","state":"reading","Series":{"id":"2","title":"Two"}}]}',
            200,
          ),
        ),
      );
      await expectLater(
        service.importFullLibrary(),
        throwsA(isA<ApiException>()),
      );
      expect(
        (await dao.listEntries(lease.owner)).map((row) => row.entry.seriesId),
        unorderedEquals(['1', '2']),
      );
      expect((await dao.readState(lease.owner))!.watermark, 'original');
    });

    test(
      'session invalidation during an actual insert rolls back the sync page',
      () async {
        final pause = _PauseOwnedInsert();
        final database = AppDatabase.forTesting(
          NativeDatabase.memory().interceptWith(pause),
        );
        addTearDown(database.close);
        final dao = database.ownedLibraryDao;
        final lease = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('paused-owner'),
        );
        mockAuth.useLease(lease);
        service = LibraryService(
          auth: mockAuth,
          database: database,
          httpClient: MockClient(
            (_) async => http.Response(
              '{"pagination":{"next":null,"count":1},"data":[{"id":"1","state":"reading","Series":{"id":"1","title":"One"}}]}',
              200,
            ),
          ),
        );
        final sync = service.importFullLibrary();
        await pause.inserted.future;
        mockAuth.useLease(null);
        final revocation = dao.invalidate(lease);
        pause.release.complete();
        await sync;
        await revocation;
        expect(await dao.listEntries(lease.owner), isEmpty);
        expect((await dao.readState(lease.owner))!.initialized, isFalse);
      },
    );

    test(
      'late A import, queued mutation and rollback cannot change B',
      () async {
        await seedEntry();
        final leaseA = mockAuth.libraryLease!;
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final getArrived = Completer<void>();
        final putArrived = Completer<void>();
        final page = Completer<http.Response>();
        final put = Completer<http.Response>();
        var mutationRequests = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((request) {
            if (request.method == 'GET') {
              getArrived.complete();
              return page.future;
            }
            mutationRequests++;
            putArrived.complete();
            return put.future;
          }),
        );
        final oldStream = service.watchEntriesFromDb().toList();
        final oldImport = service.importFullLibrary();
        await getArrived.future;
        final oldProgress = service.updateLibraryEntryProgress(
          '1',
          progressChapter: 3,
        );
        final oldProgressError = expectLater(
          oldProgress,
          throwsA(isA<AuthException>()),
        );
        await putArrived.future;
        final queued = service.updateLibraryEntryRating('1', 99);
        final queuedError = expectLater(queued, throwsA(isA<AuthException>()));

        mockAuth.useLease(null);
        await dao.invalidate(leaseA);
        final leaseB = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('account-b'),
        );
        await dao.finishFullImport(
          leaseB,
          completeSeriesIds: {'1'},
          watermark: 'B',
          entries: [
            LibraryEntry.fromJson({
              'id': 'entry-1',
              'state': 'completed',
              'progress_chapter': 77,
              'Series': {'id': '1', 'title': 'Series One'},
            }),
          ],
        );
        mockAuth.accessToken = 'B-token';
        mockAuth.useLease(leaseB);
        page.complete(
          http.Response('{"data":[],"pagination":{"next":null}}', 200),
        );
        put.complete(http.Response('{}', 401));
        await Future.wait([oldImport, oldProgressError, queuedError]);
        final entryB = (await service
            .watchEntryFromDb('1')
            .firstWhere((entry) => entry != null))!;
        expect(entryB.progressChapter, 77);
        expect(entryB.rating, isNull);
        expect(
          (await dao.findEntry(leaseA.owner, '1'))!.entry.progressChapter,
          0,
        );
        expect(mutationRequests, 1);
        expect(mockAuth.rejectedTokens, isEmpty);
        expect((await dao.readState(leaseB.owner))!.watermark, 'B');
        expect(
          (await oldStream)
              .expand((entries) => entries)
              .any((entry) => entry.progressChapter == 77),
          isFalse,
        );
      },
    );
    test('initial sync status is idle', () {
      expect(service.syncStatus.value.isSyncing, isFalse);
      expect(service.syncStatus.value.error, isNull);
    });

    test('cancelSync resets status', () {
      // Simulate syncing state
      service.syncStatus.value = service.syncStatus.value.copyWith(
        isSyncing: true,
      );

      service.cancelSync();

      expect(service.syncStatus.value.isSyncing, isFalse);
    });

    test('fetchPage retries 429 through the shared cooldown', () async {
      var calls = 0;
      var now = DateTime.utc(2026, 9, 24, 12);
      final delays = <Duration>[];
      final rateLimits = RateLimitCoordinator(
        clock: () => now,
        delay: (duration) async {
          delays.add(duration);
          now = now.add(duration);
        },
      );
      service = LibraryService(
        auth: mockAuth,
        database: getIt<AppDatabase>(),
        rateLimitCoordinator: rateLimits,
        httpClient: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('{}', 429, headers: {'retry-after': '4'})
              : http.Response('{"data":[],"pagination":{"next":null}}', 200);
        }),
      );

      final result = await service.fetchPage(mockAuth.libraryLease!, 1);

      expect(result.entries, isEmpty);
      expect(result.isError, isFalse);
      expect(calls, 2);
      expect(delays, [const Duration(seconds: 4)]);
    });

    test('fetchPage stops after maxRetries with RATE_LIMITED', () async {
      var calls = 0;
      final rateLimits = RateLimitCoordinator(
        clock: () => DateTime.utc(2026, 9, 24, 12),
        delay: (_) async {},
      );
      service = LibraryService(
        auth: mockAuth,
        database: getIt<AppDatabase>(),
        rateLimitCoordinator: rateLimits,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 429, headers: {'retry-after': '0'});
        }),
      );

      await expectLater(
        service.fetchPage(mockAuth.libraryLease!, 1),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 429)
              .having((error) => error.code, 'code', 'RATE_LIMITED'),
        ),
      );
      expect(calls, 4);
    });

    test('fetchPage retries one 401 with the recovered token', () async {
      final authorizationHeaders = <String?>[];
      service = LibraryService(
        auth: mockAuth,
        database: getIt<AppDatabase>(),
        httpClient: MockClient((request) async {
          authorizationHeaders.add(request.headers['Authorization']);
          return authorizationHeaders.length == 1
              ? http.Response('', 401)
              : http.Response('{"data":[],"pagination":{"next":null}}', 200);
        }),
      );

      final result = await service.fetchPage(mockAuth.libraryLease!, 1);

      expect(result.entries, isEmpty);
      expect(authorizationHeaders, ['Bearer access-old', 'Bearer access-new']);
      expect(mockAuth.rejectedTokens, ['access-old']);
    });

    test(
      'mutation 429s never replay progress, state, create, or delete',
      () async {
        await seedEntry(state: 'reading');
        final operations = <Future<void> Function()>[
          () => service.updateLibraryEntryProgress('1', progressChapter: 1),
          () => service.updateLibraryEntryState('1', 'paused'),
          () => service.createLibraryEntry('1', 'reading'),
          () => service.deleteEntry('1'),
        ];

        for (final operation in operations) {
          var calls = 0;
          final rateLimits = RateLimitCoordinator(delay: (_) async {});
          service = LibraryService(
            auth: mockAuth,
            database: getIt<AppDatabase>(),
            rateLimitCoordinator: rateLimits,
            httpClient: MockClient((_) async {
              calls++;
              return http.Response('{}', 429, headers: {'retry-after': '1'});
            }),
          );

          await expectLater(
            operation(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.code,
                'code',
                'RATE_LIMITED',
              ),
            ),
          );
          expect(calls, 1);
        }
      },
    );

    test('fetchPage propagates session expiry from 401 recovery', () async {
      mockAuth.recoveryError = SessionExpiredException();
      service = LibraryService(
        auth: mockAuth,
        database: getIt<AppDatabase>(),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      await expectLater(
        service.fetchPage(mockAuth.libraryLease!, 1),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test('fetchPage stops after a second 401', () async {
      var calls = 0;
      service = LibraryService(
        auth: mockAuth,
        database: getIt<AppDatabase>(),
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('', 401);
        }),
      );

      await expectLater(
        service.fetchPage(mockAuth.libraryLease!, 1),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'AUTH_FAILED',
          ),
        ),
      );
      expect(calls, 2);
      expect(mockAuth.rejectedTokens, ['access-old']);
    });

    String fullPageBody() => jsonEncode({
      'pagination': {'next': 'https://api.mangabaka.org/v1/my/library?page=2'},
      'data': [
        for (var index = 0; index < 100; index++)
          {
            'id': 'entry-$index',
            'state': 'reading',
            'updated_at': '2026-09-25T12:00:00Z',
            'Series': {'id': 'series-$index', 'title': 'Series $index'},
          },
      ],
    });

    Future<List<String>> runMultiPageSync({required bool fullImport}) async {
      final requests = <String>[];
      service = LibraryService(
        auth: mockAuth,
        database: getIt<AppDatabase>(),
        httpClient: MockClient((request) async {
          final page = request.url.queryParameters['page'];
          final authorization = request.headers['Authorization'];
          requests.add('$page:$authorization');

          if (page == '1' && authorization == 'Bearer access-old') {
            return http.Response('', 401);
          }
          if (page == '1') {
            return http.Response(fullPageBody(), 200);
          }
          return http.Response('{"data":[],"pagination":{"next":null}}', 200);
        }),
      );

      if (fullImport) {
        await service.importFullLibrary();
      } else {
        await service.syncLibrary();
      }
      return requests;
    }

    test('full import starts the next page with the recovered token', () async {
      expect(await runMultiPageSync(fullImport: true), [
        '1:Bearer access-old',
        '1:Bearer access-new',
        '2:Bearer access-new',
      ]);
    });

    test(
      'incremental sync starts the next page with the recovered token',
      () async {
        expect(await runMultiPageSync(fullImport: false), [
          '1:Bearer access-old',
          '1:Bearer access-new',
          '2:Bearer access-new',
        ]);
      },
    );

    final mutationOperations = <String, Future<void> Function()>{
      'PUT state': () => service.updateLibraryEntryState('1', 'reading'),
      'PUT rating': () => service.updateLibraryEntryRating('1', 8),
      'PUT progress': () =>
          service.updateLibraryEntryProgress('1', progressChapter: 4),
      'POST create': () => service.createLibraryEntry('1', 'reading'),
      'POST batch': () async {
        await service.createLibraryEntriesBatch(['1'], 'reading');
      },
      'DELETE': () => service.deleteEntry('1'),
    };

    test('all mutation kinds use one injected client without replay', () async {
      await seedEntry(state: 'reading');
      var calls = 0;
      var batchRequests = 0;
      final client = MockClient((request) async {
        calls++;
        if (request.method == 'POST') {
          if (request.url.path.endsWith('/batch')) {
            batchRequests++;
            expect(request.method, 'POST');
            expect(request.headers['authorization'], 'Bearer access-old');
            expect(request.headers['content-type'], 'application/json');
            expect(jsonDecode(request.body), [
              {'series_id': 1, 'state': 'reading'},
            ]);
            return http.Response('{"data":[],"pagination":{"next":null}}', 200);
          }
          return http.Response('{}', 201);
        }
        if (request.method == 'GET') {
          return http.Response('{"data":[],"pagination":{"next":null}}', 200);
        }
        return http.Response('{}', 200);
      });

      await runWithServiceClient(() async {
        await service.updateLibraryEntryState('1', 'paused');
        await service.updateLibraryEntryRating('1', 8);
        await service.updateLibraryEntryProgress('1', progressChapter: 1);
        await service.createLibraryEntry('1', 'reading');
        await service.createLibraryEntriesBatch(['1'], 'reading');
        await service.deleteEntry('1');
      }, () => client);

      // The batch create also performs its documented sync GET. Every
      // mutation itself still contributes exactly one request.
      expect(calls, 8);
      expect(batchRequests, 1);
    });

    for (final operation in mutationOperations.entries) {
      test('${operation.key} is not replayed after 401', () async {
        mockAuth.rejectedTokens.clear();
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return http.Response('', 401);
        });

        await expectLater(
          runWithServiceClient(operation.value, () => client),
          throwsA(
            isA<AuthException>().having(
              (error) => error.code,
              'code',
              'AUTH_RETRY_REQUIRED',
            ),
          ),
          reason: operation.key,
        );
        expect(calls, 1, reason: '${operation.key} must not be replayed');
        expect(mockAuth.rejectedTokens, ['access-old']);
      });
    }

    test('mutation 401 propagates SessionExpiredException', () async {
      mockAuth.recoveryError = SessionExpiredException();
      var calls = 0;

      await expectLater(
        runWithServiceClient(
          () => service.updateLibraryEntryState('1', 'reading'),
          () => MockClient((_) async {
            calls++;
            return http.Response('', 401);
          }),
        ),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(calls, 1);
    });

    test('confirmed progress survives a 401 without replay', () async {
      final database = getIt<AppDatabase>();
      await database
          .into(database.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: '1',
              title: 'Series One',
              coverUrl: 'cover',
              description: 'description',
            ),
          );
      await database
          .into(database.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              ownerId: mockAuth.libraryLease!.owner.id,
              id: 'entry-1',
              seriesId: '1',
              state: 'reading',
              progressChapter: const Value(2),
            ),
          );
      var calls = 0;

      await expectLater(
        runWithServiceClient(
          () => service.updateLibraryEntryProgress('1', progressChapter: 3),
          () => MockClient((_) async {
            calls++;
            return http.Response('', 401);
          }),
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'AUTH_RETRY_REQUIRED',
          ),
        ),
      );

      final entry = await (database.select(
        database.ownedLibraryEntries,
      )..where((row) => row.seriesId.equals('1'))).getSingle();
      expect(entry.progressChapter, 2);
      expect(calls, 1);
    });

    test(
      'plan_to_read chapter progress starts reading in one request and locally',
      () async {
        await seedEntry();
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        await runWithServiceClient(
          () => service.updateLibraryEntryProgress('1', progressChapter: 1),
          () => client,
        );

        expect(body, {'progress_chapter': 1, 'state': 'reading'});
        final entry = await storedEntry();
        expect(entry.progressChapter, 1);
        expect(entry.state, 'reading');
      },
    );

    test(
      'plan_to_read volume progress starts reading in one request and locally',
      () async {
        await seedEntry();
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        await runWithServiceClient(
          () => service.updateLibraryEntryProgress('1', progressVolume: 1),
          () => client,
        );

        expect(body, {'progress_volume': 1, 'state': 'reading'});
        final entry = await storedEntry();
        expect(entry.progressVolume, 1);
        expect(entry.state, 'reading');
      },
    );

    test('plan_to_read progress zero stays plan_to_read', () async {
      await seedEntry();
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      await runWithServiceClient(
        () => service.updateLibraryEntryProgress('1', progressChapter: 0),
        () => client,
      );

      expect(body, {'progress_chapter': 0});
      expect((await storedEntry()).state, 'plan_to_read');
    });

    for (final state in [
      'reading',
      'paused',
      'completed',
      'dropped',
      'rereading',
      'considering',
    ]) {
      test('$state progress is not automatically rewritten', () async {
        await seedEntry(state: state);
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        await runWithServiceClient(
          () => service.updateLibraryEntryProgress('1', progressChapter: 1),
          () => client,
        );

        expect(body, {'progress_chapter': 1});
        expect((await storedEntry()).state, state);
      });
    }

    test('server failure restores previous progress and state', () async {
      await seedEntry(chapter: 0);
      final client = MockClient((_) async => http.Response('{}', 500));

      await expectLater(
        runWithServiceClient(
          () => service.updateLibraryEntryProgress('1', progressChapter: 1),
          () => client,
        ),
        throwsA(isA<ApiException>()),
      );

      final entry = await storedEntry();
      expect(entry.progressChapter, 0);
      expect(entry.state, 'plan_to_read');
    });

    test('server failure restores a previously null progress value', () async {
      await seedEntry();
      final database = getIt<AppDatabase>();
      await (database.update(
        database.ownedLibraryEntries,
      )..where((row) => row.seriesId.equals('1'))).write(
        const OwnedLibraryEntriesCompanion(progressChapter: Value(null)),
      );
      final client = MockClient((_) async => http.Response('{}', 500));

      await expectLater(
        runWithServiceClient(
          () => service.updateLibraryEntryProgress('1', progressChapter: 1),
          () => client,
        ),
        throwsA(isA<ApiException>()),
      );

      final entry = await storedEntry();
      expect(entry.progressChapter, isNull);
      expect(entry.state, 'plan_to_read');
    });

    test(
      'same-field progress mutations are serialized after an older failure',
      () async {
        await seedEntry(chapter: 5);
        final firstResponse = Completer<http.Response>();
        final firstRequestStarted = Completer<void>();
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          if (calls == 1) {
            firstRequestStarted.complete();
            return firstResponse.future;
          }
          return http.Response('{}', 200);
        });

        await runWithServiceClient(() async {
          final first = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 6,
          );
          await firstRequestStarted.future;
          final second = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 7,
          );
          await Future<void>.delayed(Duration.zero);
          expect(calls, 1);
          firstResponse.complete(http.Response('{}', 500));

          await expectLater(first, throwsA(isA<ApiException>()));
          await second;
        }, () => client);
        final entry = await storedEntry();
        expect(entry.progressChapter, 7);
        expect(entry.state, 'reading');
        expect(calls, 2);
      },
    );

    test(
      'cross-field progress mutation follows an older failure atomically',
      () async {
        await seedEntry();
        final firstResponse = Completer<http.Response>();
        final firstRequestStarted = Completer<void>();
        final bodies = <Map<String, dynamic>>[];
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (calls == 1) {
            firstRequestStarted.complete();
            return firstResponse.future;
          }
          return http.Response('{}', 200);
        });

        await runWithServiceClient(() async {
          final chapter = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 1,
          );
          await firstRequestStarted.future;
          final volume = service.updateLibraryEntryProgress(
            '1',
            progressVolume: 1,
          );
          await Future<void>.delayed(Duration.zero);
          expect(calls, 1);

          firstResponse.complete(http.Response('{}', 500));
          await expectLater(chapter, throwsA(isA<ApiException>()));
          await volume;
        }, () => client);

        final entry = await storedEntry();
        expect(entry.progressChapter, 0);
        expect(entry.progressVolume, 1);
        expect(entry.state, 'reading');
        expect(bodies, [
          {'progress_chapter': 1, 'state': 'reading'},
          {'progress_volume': 1, 'state': 'reading'},
        ]);
      },
    );

    test(
      'successful rapid progress mutations preserve request order',
      () async {
        await seedEntry(state: 'reading');
        final firstResponse = Completer<http.Response>();
        final firstRequestStarted = Completer<void>();
        final requestedChapters = <int>[];
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requestedChapters.add(body['progress_chapter'] as int);
          if (requestedChapters.length == 1) {
            firstRequestStarted.complete();
            return firstResponse.future;
          }
          return http.Response('{}', 200);
        });

        await runWithServiceClient(() async {
          final first = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 1,
          );
          await firstRequestStarted.future;
          final second = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 2,
          );
          await Future<void>.delayed(Duration.zero);
          expect(requestedChapters, [1]);

          firstResponse.complete(http.Response('{}', 200));
          await Future.wait([first, second]);
        }, () => client);

        expect(requestedChapters, [1, 2]);
        expect((await storedEntry()).progressChapter, 2);
      },
    );

    test('different series mutations are not serialized together', () async {
      await seedEntry(state: 'reading');
      final database = getIt<AppDatabase>();
      await database
          .into(database.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: '2',
              title: 'Series Two',
              coverUrl: 'cover-2',
              description: 'description-2',
            ),
          );
      await database
          .into(database.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              ownerId: mockAuth.libraryLease!.owner.id,
              id: 'entry-2',
              seriesId: '2',
              state: 'reading',
              progressChapter: const Value(0),
              progressVolume: const Value(0),
            ),
          );

      final firstResponse = Completer<http.Response>();
      final firstRequestStarted = Completer<void>();
      final requests = <String>[];
      final client = MockClient((request) async {
        final seriesId = request.url.pathSegments.last;
        requests.add('$seriesId:${request.method}');
        if (seriesId == '1') {
          firstRequestStarted.complete();
          return firstResponse.future;
        }
        return http.Response('{}', 200);
      });

      await runWithServiceClient(() async {
        final first = service.updateLibraryEntryProgress(
          '1',
          progressChapter: 1,
        );
        await firstRequestStarted.future;
        final second = service.updateLibraryEntryState('2', 'paused');
        await Future<void>.delayed(Duration.zero);

        expect(requests, ['1:PUT', '2:PUT']);
        firstResponse.complete(http.Response('{}', 200));
        await Future.wait([first, second]);
      }, () => client);

      final secondEntry = await (database.select(
        database.ownedLibraryEntries,
      )..where((row) => row.seriesId.equals('2'))).getSingle();
      expect(secondEntry.state, 'paused');
    });

    test('failed state does not poison queued progress', () async {
      await seedEntry();
      final firstResponse = Completer<http.Response>();
      final firstRequestStarted = Completer<void>();
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (bodies.length == 1) {
          firstRequestStarted.complete();
          return firstResponse.future;
        }
        return http.Response('{}', 200);
      });

      await runWithServiceClient(() async {
        final state = service.updateLibraryEntryState('1', 'paused');
        await firstRequestStarted.future;
        final progress = service.updateLibraryEntryProgress(
          '1',
          progressChapter: 1,
        );
        await Future<void>.delayed(Duration.zero);
        expect(bodies, [
          {'state': 'paused'},
        ]);

        firstResponse.complete(http.Response('{}', 500));
        await expectLater(state, throwsA(isA<ApiException>()));
        await progress;
      }, () => client);

      expect(bodies, [
        {'state': 'paused'},
        {'progress_chapter': 1, 'state': 'reading'},
      ]);
      final entry = await storedEntry();
      expect(entry.progressChapter, 1);
      expect(entry.state, 'reading');
    });

    test('progress then explicit state preserves invocation order', () async {
      await seedEntry();
      final firstResponse = Completer<http.Response>();
      final firstRequestStarted = Completer<void>();
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (bodies.length == 1) {
          firstRequestStarted.complete();
          return firstResponse.future;
        }
        return http.Response('{}', 200);
      });

      await runWithServiceClient(() async {
        final progress = service.updateLibraryEntryProgress(
          '1',
          progressChapter: 1,
        );
        await firstRequestStarted.future;
        final state = service.updateLibraryEntryState('1', 'paused');
        await Future<void>.delayed(Duration.zero);
        expect(bodies, [
          {'progress_chapter': 1, 'state': 'reading'},
        ]);

        firstResponse.complete(http.Response('{}', 200));
        await Future.wait([progress, state]);
      }, () => client);

      expect(bodies, [
        {'progress_chapter': 1, 'state': 'reading'},
        {'state': 'paused'},
      ]);
      final entry = await storedEntry();
      expect(entry.progressChapter, 1);
      expect(entry.state, 'paused');
    });

    test(
      'failed progress leaves the cache intact before queued state',
      () async {
        await seedEntry();
        final firstResponse = Completer<http.Response>();
        final firstRequestStarted = Completer<void>();
        final bodies = <Map<String, dynamic>>[];
        final client = MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (bodies.length == 1) {
            firstRequestStarted.complete();
            return firstResponse.future;
          }
          return http.Response('{}', 200);
        });

        await runWithServiceClient(() async {
          final progress = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 1,
          );
          await firstRequestStarted.future;
          final state = service.updateLibraryEntryState('1', 'paused');
          await Future<void>.delayed(Duration.zero);
          expect(bodies.length, 1);

          firstResponse.complete(http.Response('{}', 500));
          await expectLater(progress, throwsA(isA<ApiException>()));
          await state;
        }, () => client);

        expect(bodies, [
          {'progress_chapter': 1, 'state': 'reading'},
          {'state': 'paused'},
        ]);
        final entry = await storedEntry();
        expect(entry.progressChapter, 0);
        expect(entry.state, 'paused');
      },
    );

    test(
      'create waits for an older progress mutation on the same series',
      () async {
        await seedEntry(state: 'reading');
        final firstResponse = Completer<http.Response>();
        final firstRequestStarted = Completer<void>();
        final methods = <String>[];
        final client = MockClient((request) async {
          methods.add(request.method);
          if (methods.length == 1) {
            firstRequestStarted.complete();
            return firstResponse.future;
          }
          if (request.method == 'POST') {
            return http.Response('{}', 201);
          }
          return http.Response('{"data":[],"pagination":{"next":null}}', 200);
        });

        await runWithServiceClient(() async {
          final progress = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 1,
          );
          await firstRequestStarted.future;
          final create = service.createLibraryEntry('1', 'reading');
          await Future<void>.delayed(Duration.zero);
          expect(methods, ['PUT']);

          firstResponse.complete(http.Response('{}', 200));
          await Future.wait([progress, create]);
        }, () => client);

        expect(methods.take(2).toList(), ['PUT', 'POST']);
      },
    );

    test(
      'delete waits for an older progress mutation on the same series',
      () async {
        await seedEntry(state: 'reading');
        final firstResponse = Completer<http.Response>();
        final firstRequestStarted = Completer<void>();
        final methods = <String>[];
        final client = MockClient((request) async {
          methods.add(request.method);
          if (methods.length == 1) {
            firstRequestStarted.complete();
            return firstResponse.future;
          }
          return http.Response('{}', 200);
        });

        await runWithServiceClient(() async {
          final progress = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 1,
          );
          await firstRequestStarted.future;
          final delete = service.deleteEntry('1');
          await Future<void>.delayed(Duration.zero);
          expect(methods, ['PUT']);

          firstResponse.complete(http.Response('{}', 200));
          await Future.wait([progress, delete]);
        }, () => client);

        expect(methods, ['PUT', 'DELETE']);
        final database = getIt<AppDatabase>();
        final remaining = await (database.select(
          database.ownedLibraryEntries,
        )..where((row) => row.seriesId.equals('1'))).get();
        expect(remaining, isEmpty);
      },
    );

    test('state then progress uses the completed explicit state', () async {
      await seedEntry();
      final firstResponse = Completer<http.Response>();
      final firstRequestStarted = Completer<void>();
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (bodies.length == 1) {
          firstRequestStarted.complete();
          return firstResponse.future;
        }
        return http.Response('{}', 200);
      });

      await runWithServiceClient(() async {
        final state = service.updateLibraryEntryState('1', 'paused');
        await firstRequestStarted.future;
        final progress = service.updateLibraryEntryProgress(
          '1',
          progressChapter: 1,
        );
        await Future<void>.delayed(Duration.zero);
        expect(bodies, [
          {'state': 'paused'},
        ]);

        firstResponse.complete(http.Response('{}', 200));
        await Future.wait([state, progress]);
      }, () => client);

      expect(bodies, [
        {'state': 'paused'},
        {'progress_chapter': 1},
      ]);
      final entry = await storedEntry();
      expect(entry.progressChapter, 1);
      expect(entry.state, 'paused');
    });
  });
}
