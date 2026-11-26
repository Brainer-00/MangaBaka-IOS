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
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
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

class _HeldReconciliationService extends LibraryService {
  _HeldReconciliationService({required super.auth, required super.httpClient});

  final releases = <void Function()>[];

  @override
  void Function() pauseSyncForReconciliation(LibraryCacheLease lease) {
    final release = super.pauseSyncForReconciliation(lease);
    return () => releases.add(release);
  }
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
    test('quick rating uses PATCH and reconciles a confirmed rating', () async {
      await seedEntry(state: 'reading', chapter: 21);
      final methods = <String>[];
      await runWithServiceClient(
        () => service.updateLibraryEntryRating('1', 78),
        () => MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'PUT') return http.Response('', 405);
          if (request.method == 'PATCH') {
            expect(jsonDecode(request.body), {'rating': 78});
            return http.Response('{"status":200,"data":true}', 200);
          }
          return http.Response(
            '{"status":200,"data":{"id":1,"series_id":1,"user_id":"account-a",'
            '"state":"reading","rating":78,"progress_chapter":21}}',
            200,
          );
        }),
      );
      expect(methods, ['PATCH', 'GET']);
      expect((await storedEntry()).rating, 78);
      expect((await storedEntry()).progressChapter, 21);
    });

    test(
      'explicit sync removes an entry from a complete empty snapshot',
      () async {
        await seedEntry(state: 'reading');
        await runWithServiceClient(
          () => service.reconcileLibrary(mockAuth.libraryLease!),
          () => MockClient((request) async {
            if (request.url.path.endsWith('/1')) {
              return http.Response('{"status":404,"message":"Not Found"}', 404);
            }
            return http.Response(
              '{"status":200,"data":[],"pagination":{"next":null,"count":0}}',
              200,
            );
          }),
        );
        expect(
          await getIt<AppDatabase>()
              .select(getIt<AppDatabase>().ownedLibraryEntries)
              .get(),
          isEmpty,
        );
      },
    );

    test(
      'startup and manual reconciliation share an equal-count replacement',
      () async {
        await seedEntry(state: 'reading');
        final lease = mockAuth.libraryLease!;
        final request = Completer<http.Response>();
        final started = Completer<void>();
        var calls = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((_) {
            calls++;
            if (!started.isCompleted) started.complete();
            return request.future;
          }),
        );
        final startup = service.performInitialSyncIfNeeded();
        await started.future;
        final manual = service.reconcileLibrary(lease);
        final home = service.reconcileLibrary(lease);
        expect(home, same(manual));
        request.complete(
          http.Response(
            '{"status":200,"data":[{"id":2,"state":"paused","Series":{"id":2,"title":"Replacement"}}],'
            '"pagination":{"next":null,"count":1}}',
            200,
          ),
        );
        await Future.wait([startup, manual, home]);
        final entries = await getIt<AppDatabase>().ownedLibraryDao.listEntries(
          lease.owner,
        );
        expect(entries.map((row) => row.entry.seriesId), ['2']);
        expect(calls, 1);
      },
    );

    for (final confirmedMissing in [false, true]) {
      test(
        'multi-page absence is confirmed before deleting ($confirmedMissing)',
        () async {
          await seedEntry(state: 'reading', chapter: 3);
          final lease = mockAuth.libraryLease!;
          final requests = <String>[];
          await runWithServiceClient(
            () async {
              final refresh = service.reconcileLibrary(lease);
              if (confirmedMissing) {
                await refresh;
              } else {
                await expectLater(refresh, throwsA(isA<FormatException>()));
              }
            },
            () => MockClient((request) async {
              final page = request.url.queryParameters['page'];
              requests.add(page ?? request.url.path);
              if (page == null) {
                return http.Response(
                  confirmedMissing
                      ? '{"status":404,"message":"Not Found"}'
                      : '{}',
                  404,
                );
              }
              final seriesId = page == '1' ? 2 : 3;
              return http.Response(
                jsonEncode({
                  'status': 200,
                  'data': [
                    {
                      'id': seriesId,
                      'state': 'reading',
                      'Series': {'id': seriesId, 'title': 'Remote'},
                    },
                  ],
                  'pagination': {
                    'next': page == '1' ? '?page=2' : null,
                    'count': 2,
                  },
                }),
                200,
              );
            }),
          );
          final owned = getIt<AppDatabase>().ownedLibraryDao;
          expect(
            await owned.findEntry(lease.owner, '1'),
            confirmedMissing ? isNull : isNotNull,
          );
          expect(requests, ['1', '2', '/v1/my/library/1']);
        },
      );
    }

    test(
      'rating rejection envelope preserves the cache and skips readback',
      () async {
        await seedEntry(state: 'reading', chapter: 21);
        final methods = <String>[];
        await runWithServiceClient(
          () => expectLater(
            service.updateLibraryEntryRating('1', 78),
            throwsA(
              isA<ApiException>().having(
                (error) => error.code,
                'code',
                'WRITE_DECLINED',
              ),
            ),
          ),
          () => MockClient((request) async {
            methods.add(request.method);
            return http.Response('{"status":200,"data":false}', 200);
          }),
        );
        expect(methods, ['PATCH']);
        expect((await storedEntry()).rating, isNull);
      },
    );

    for (final scenario in ['timeout', 'malformed', 'failed readback']) {
      test(
        'quick rating handles $scenario without reissuing the write',
        () async {
          await seedEntry(state: 'reading', chapter: 21);
          final methods = <String>[];
          late LibrarySaveResult result;
          await runWithServiceClient(
            () async {
              result = await service.updateLibraryEntryRating('1', 71);
            },
            () => MockClient((request) async {
              methods.add(request.method);
              if (request.method == 'GET') return http.Response('{}', 503);
              if (scenario == 'timeout') {
                throw TimeoutException('mock rating time limit');
              }
              return http.Response(
                scenario == 'malformed' ? '{}' : '{"status":200,"data":true}',
                200,
              );
            }),
          );
          expect(methods, ['PATCH', 'GET']);
          expect(
            result.outcome,
            scenario == 'failed readback'
                ? LibrarySaveOutcome.refreshPending
                : LibrarySaveOutcome.uncertain,
          );
          expect((await storedEntry()).rating, isNull);
          expect((await storedEntry()).progressChapter, 21);
        },
      );
    }

    test('quick rating cannot read back under a replacement account', () async {
      await seedEntry();
      final before = mockAuth.libraryLease!;
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final methods = <String>[];
      service = LibraryService(
        auth: mockAuth,
        httpClient: MockClient((request) {
          methods.add(request.method);
          if (!started.isCompleted) started.complete();
          return response.future;
        }),
      );
      final update = service.updateLibraryEntryRating('1', 41, lease: before);
      await started.future;
      final owned = getIt<AppDatabase>().ownedLibraryDao;
      final next = await owned.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId(
          'rating-after-account-switch',
        ),
      );
      mockAuth.useLease(next);
      response.complete(http.Response('{"status":200,"data":true}', 200));
      expect((await update).outcome, LibrarySaveOutcome.refreshPending);
      expect(methods, ['PATCH']);
      expect(await owned.listEntries(next.owner), isEmpty);
      expect((await owned.findEntry(before.owner, '1'))!.entry.rating, isNull);
    });

    group('complete entry editor API', () {
      http.Response syncPage({int? chapter, String? timestamp}) =>
          http.Response(
            jsonEncode({
              'pagination': {'next': null, 'count': chapter == null ? 0 : 1},
              'data': [
                if (chapter != null)
                  {
                    'id': 'entry-1',
                    'state': 'reading',
                    'progress_chapter': chapter,
                    'updated_at': timestamp,
                    'Series': {'id': '1', 'title': 'Series One'},
                  },
              ],
            }),
            200,
          );

      test(
        'different-series editor writes keep refresh paused until both release',
        () async {
          await seedEntry(chapter: 3);
          final db = getIt<AppDatabase>();
          await db.customStatement(
            "INSERT INTO series_table (id, title, cover_url, description) VALUES ('2', 'Two', '', '')",
          );
          final lease = mockAuth.libraryLease!;
          final started = Completer<void>();
          final oldPage = Completer<http.Response>();
          final freshPageStarted = Completer<void>();
          final freshPage = Completer<http.Response>();
          var pages = 0;
          final editor = _HeldReconciliationService(
            auth: mockAuth,
            httpClient: MockClient((request) async {
              final id = int.tryParse(request.url.pathSegments.last);
              if (id == null) {
                expect(request.url.queryParameters['state'], 'reading');
                if (++pages == 1) {
                  started.complete();
                  return oldPage.future;
                }
                freshPageStarted.complete();
                return freshPage.future;
              }
              return http.Response(
                jsonEncode({
                  'status': 200,
                  'data': {
                    'id': 30 + id,
                    'series_id': id,
                    'user_id': lease.owner.id,
                    'state': 'reading',
                    'progress_chapter': id + 6,
                  },
                }),
                200,
              );
            }),
          );
          final sync = editor.syncLibrary(state: 'reading');
          await started.future;
          await Future.wait([
            editor.fetchAuthoritativeLibraryEntry('1'),
            editor.fetchAuthoritativeLibraryEntry('2'),
          ]);
          expect(editor.releases, hasLength(2));
          final refresh = editor.syncLibrary();
          editor.releases.first();
          oldPage.complete(
            syncPage(chapter: 99, timestamp: '2026-01-09T00:00:00Z'),
          );
          expect(
            (await db.ownedLibraryDao.findEntry(
              lease.owner,
              '1',
            ))!.entry.progressChapter,
            7,
          );
          expect(pages, 1);
          editor.releases.last();
          await freshPageStarted.future;
          freshPage.complete(syncPage());
          await Future.wait([sync, refresh]);
          expect(pages, 2);
          expect(
            (await db.ownedLibraryDao.findEntry(
              lease.owner,
              '1',
            ))!.entry.progressChapter,
            7,
          );
          expect(
            (await db.ownedLibraryDao.findEntry(
              lease.owner,
              '2',
            ))!.entry.progressChapter,
            8,
          );
          expect(
            (await db.ownedLibraryDao.readState(lease.owner))!.watermark,
            isNull,
          );
        },
      );

      test(
        'overlapping and repeated pauses share one incremental bootstrap',
        () async {
          await seedEntry(chapter: 3);
          final lease = mockAuth.libraryLease!;
          final dao = getIt<AppDatabase>().ownedLibraryDao;
          await dao.finishFullImport(
            lease,
            completeSeriesIds: {'1'},
            watermark: '2026-01-01T00:00:00.000Z',
          );
          final starts = List.generate(3, (_) => Completer<void>());
          final pages = List.generate(3, (_) => Completer<http.Response>());
          var requests = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((_) {
              final index = requests++;
              starts[index].complete();
              return pages[index].future;
            }),
          );
          final bootstrap = service.performInitialSyncIfNeeded();
          expect(service.performInitialSyncIfNeeded(), same(bootstrap));
          final finished = Completer<void>();
          unawaited(bootstrap.then((_) => finished.complete()));
          await starts[0].future;
          final releaseFirst = service.pauseSyncForReconciliation(lease);
          final releaseSecond = service.pauseSyncForReconciliation(lease);
          final manual = service.syncLibrary();
          releaseFirst();
          pages[0].complete(
            syncPage(chapter: 1, timestamp: '2026-01-09T00:00:00Z'),
          );
          expect(
            (await dao.readState(lease.owner))!.watermark,
            '2026-01-01T00:00:00.000Z',
          );
          expect(requests, 1);
          expect(finished.isCompleted, isFalse);
          releaseSecond();
          await starts[1].future;
          final releaseThird = service.pauseSyncForReconciliation(lease);
          pages[1].complete(http.Response('{}', 503));
          expect((await storedEntry()).progressChapter, 3);
          expect(requests, 2);
          releaseThird();
          await starts[2].future;
          expect(finished.isCompleted, isFalse);
          pages[2].complete(
            syncPage(chapter: 7, timestamp: '2026-01-02T00:00:00Z'),
          );
          await Future.wait([bootstrap, manual, finished.future]);
          await service.performInitialSyncIfNeeded();
          expect(requests, 3);
          expect((await storedEntry()).progressChapter, 7);
          expect(
            (await dao.readState(lease.owner))!.watermark,
            '2026-01-02T00:00:00.000Z',
          );
        },
      );

      test(
        'resumed failure reaches both bootstrap callers and leaves retry available',
        () async {
          await seedEntry(chapter: 3);
          final lease = mockAuth.libraryLease!;
          final dao = getIt<AppDatabase>().ownedLibraryDao;
          final first = Completer<void>();
          final oldPage = Completer<http.Response>();
          var requests = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((_) async {
              switch (++requests) {
                case 1:
                  first.complete();
                  return oldPage.future;
                case 2:
                  return http.Response('{}', 503);
                default:
                  return syncPage(
                    chapter: 8,
                    timestamp: '2026-01-03T00:00:00Z',
                  );
              }
            }),
          );
          final a = service.performInitialSyncIfNeeded();
          final b = service.performInitialSyncIfNeeded();
          final failures = Future.wait([
            expectLater(a, throwsA(isA<ApiException>())),
            expectLater(b, throwsA(isA<ApiException>())),
          ]);
          await first.future;
          final release = service.pauseSyncForReconciliation(lease);
          release();
          await failures;
          expect((await storedEntry()).progressChapter, 3);
          expect((await dao.readState(lease.owner))!.watermark, isNull);
          oldPage.complete(
            syncPage(chapter: 1, timestamp: '2026-01-09T00:00:00Z'),
          );
          await service.performInitialSyncIfNeeded();
          expect(requests, 3);
          expect((await storedEntry()).progressChapter, 8);
          expect(
            (await dao.readState(lease.owner))!.watermark,
            '2026-01-03T00:00:00.000Z',
          );
        },
      );

      for (final switchAccount in [false, true]) {
        test('paused bootstrap settles on switch=$switchAccount', () async {
          await seedEntry(chapter: 3);
          final lease = mockAuth.libraryLease!;
          final dao = getIt<AppDatabase>().ownedLibraryDao;
          final started = Completer<void>();
          final oldPage = Completer<http.Response>();
          var requests = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((_) {
              requests++;
              started.complete();
              return oldPage.future;
            }),
          );
          final bootstrap = service.performInitialSyncIfNeeded();
          final settled = switchAccount
              ? expectLater(bootstrap, throwsA(isA<AuthException>()))
              : expectLater(bootstrap, completes);
          await started.future;
          final release = service.pauseSyncForReconciliation(lease);
          final refresh = service.syncLibrary();
          final refreshSettled = switchAccount
              ? expectLater(refresh, throwsA(isA<AuthException>()))
              : expectLater(refresh, completes);
          if (switchAccount) {
            final next = await dao.activate(
              VerifiedLibraryOwner.fromVerifiedAccountId('paused-b'),
            );
            mockAuth.useLease(next);
          } else {
            service.cancelSync();
          }
          await Future.wait([settled, refreshSettled]);
          release();
          oldPage.complete(
            syncPage(chapter: 1, timestamp: '2026-01-09T00:00:00Z'),
          );
          expect((await storedEntry()).progressChapter, 3);
          expect((await dao.readState(lease.owner))!.watermark, isNull);
          expect(requests, 1);
        });
      }

      test('stale page cannot resurrect validated remote absence', () async {
        await seedEntry(chapter: 3);
        final lease = mockAuth.libraryLease!;
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final started = Completer<void>();
        final oldPage = Completer<http.Response>();
        var pages = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/my/library/1')) {
              return http.Response('{"status":404}', 404);
            }
            if (++pages == 1) {
              started.complete();
              return oldPage.future;
            }
            return syncPage();
          }),
        );
        final sync = service.syncLibrary();
        await started.future;
        expect(await service.fetchAuthoritativeLibraryEntry('1'), isNull);
        oldPage.complete(
          syncPage(chapter: 99, timestamp: '2026-01-09T00:00:00Z'),
        );
        await sync;
        expect(await dao.findEntry(lease.owner, '1'), isNull);
        expect((await dao.readState(lease.owner))!.watermark, isNull);
        expect(await getIt<AppDatabase>().seriesDao.findSeries('1'), isNotNull);
        expect(pages, 2);
      });
      test('editor read restarts an interrupted initial import', () async {
        final dao = getIt<AppDatabase>().ownedLibraryDao;
        final lease = await dao.activate(
          VerifiedLibraryOwner.fromVerifiedAccountId('initial-resume'),
        );
        mockAuth.useLease(lease);
        await getIt<AppDatabase>().customStatement(
          "INSERT INTO series_table (id, title, cover_url, description) VALUES ('1', 'One', '', '')",
        );
        final firstStarted = Completer<void>();
        final oldPage = Completer<http.Response>();
        final resumed = Completer<void>();
        var pageCalls = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/my/library')) {
              pageCalls++;
              if (pageCalls == 1) {
                firstStarted.complete();
                return oldPage.future;
              }
              resumed.complete();
              return http.Response(
                '{"pagination":{"next":null,"count":1},"data":[{"id":"34","state":"reading","progress_chapter":7,"Series":{"id":"1","title":"One"}}]}',
                200,
              );
            }
            return http.Response(
              '{"status":200,"data":{"id":34,"series_id":1,"user_id":"initial-resume","state":"reading","progress_chapter":7}}',
              200,
            );
          }),
        );
        final old = service.performInitialSyncIfNeeded();
        await firstStarted.future;
        expect(
          (await service.fetchAuthoritativeLibraryEntry('1'))!.progressChapter,
          7,
        );
        await resumed.future;
        oldPage.complete(
          http.Response(
            '{"pagination":{"next":null,"count":0},"data":[]}',
            200,
          ),
        );
        await old;
        await service.watchEntriesFromDb().first;
        expect(
          (await dao.findEntry(lease.owner, '1'))!.entry.progressChapter,
          7,
        );
        expect((await dao.readState(lease.owner))!.initialized, isTrue);
        expect(pageCalls, 2);
      });
      for (final status in [500, 502, 503, 504]) {
        test('HTTP $status write remains uncertain without replay', () async {
          await seedEntry();
          var writes = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((request) async {
              if (request.method == 'PATCH') {
                writes++;
                return http.Response('{}', status);
              }
              return http.Response('{}', 503);
            }),
          );
          final result = await service.updateCompleteLibraryEntry(
            LibraryEntryDraft(
              lease: mockAuth.libraryLease!,
              seriesId: '1',
              rating: const EntryField.set(20),
            ),
          );
          expect(result.outcome, LibrarySaveOutcome.uncertain);
          expect(writes, 1);
          expect((await storedEntry()).progressChapter, 0);
        });
      }

      test(
        'validated absence removes only owned entry and preserves metadata',
        () async {
          await seedEntry();
          var response = http.Response('{}', 404);
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((_) async => response),
          );
          await expectLater(
            service.fetchAuthoritativeLibraryEntry('1'),
            throwsFormatException,
          );
          expect(await storedEntry(), isNotNull);
          response = http.Response('{"status":404}', 404);
          expect(await service.fetchAuthoritativeLibraryEntry('1'), isNull);
          expect(
            await getIt<AppDatabase>().ownedLibraryDao.findEntry(
              mockAuth.libraryLease!.owner,
              '1',
            ),
            isNull,
          );
          expect(
            await getIt<AppDatabase>().seriesDao.findSeries('1'),
            isNotNull,
          );
        },
      );
      http.Response entryResponse([Map<String, Object?> fields = const {}]) =>
          http.Response(
            jsonEncode({
              'status': 200,
              'data': {
                'id': 34,
                'series_id': 1,
                'user_id': 'account-a',
                'state': 'reading',
                'progress_chapter': 7,
                'priority': 20,
                'rating': null,
                'progress_volume': null,
                'number_of_rereads': 2,
                'note': 'private',
                'start_date': '2026-02-21T00:00:00.000Z',
                'finish_date': null,
                'read_link': 'https://example.org/read',
                'is_private': true,
                ...fields,
              },
            }),
            200,
          );

      LibraryEntryDraft draft() => LibraryEntryDraft(
        lease: mockAuth.libraryLease!,
        seriesId: '1',
        state: const EntryField.set('reading'),
        priority: const EntryField.set(25),
        startDate: const EntryField.set('2026-02-21'),
        finishDate: const EntryField.set(null),
        progressChapter: const EntryField.set(7),
        progressVolume: const EntryField.set(0),
        numberOfRereads: const EntryField.set(2),
        rating: const EntryField.set(0),
        readLink: const EntryField.set('https://example.org/read'),
        note: const EntryField.set(null),
        isPrivate: const EntryField.set(true),
        lists: const EntryField.set([5, 7]),
      );

      test(
        'an authoritative cache write rolls back if its lease is revoked at commit',
        () async {
          final pause = _PauseOwnedInsert();
          final db = AppDatabase.forTesting(
            NativeDatabase.memory().interceptWith(pause),
          );
          addTearDown(db.close);
          await db.customStatement(
            "INSERT INTO series_table (id, title, cover_url, description) VALUES ('1', 'One', '', '')",
          );
          final dao = db.ownedLibraryDao;
          final lease = await dao.activate(
            VerifiedLibraryOwner.fromVerifiedAccountId('account-a'),
          );
          mockAuth.useLease(lease);
          service = LibraryService(
            database: db,
            auth: mockAuth,
            httpClient: MockClient((_) async => entryResponse()),
          );
          final pending = expectLater(
            service.fetchAuthoritativeLibraryEntry('1'),
            throwsA(isA<AuthException>()),
          );
          await pause.inserted.future;
          mockAuth.useLease(null);
          pause.release.complete();
          await pending;
          expect(await dao.findEntry(lease.owner, '1'), isNull);
        },
      );

      test('entry transport failure differs from a missing entry', () async {
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        );
        await expectLater(
          service.fetchAuthoritativeLibraryEntry('1'),
          throwsA(isA<NetworkException>()),
        );
      });
      test(
        'an older Library page cannot overwrite the confirmed edit',
        () async {
          await seedEntry(chapter: 2);
          final started = Completer<void>();
          final older = Completer<http.Response>();
          var pages = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((request) async {
              if (request.url.path.endsWith('/my/library')) {
                if (++pages > 1) return syncPage();
                started.complete();
                return older.future;
              }
              if (request.method == 'PATCH') {
                return http.Response('{"status":200,"data":true}', 200);
              }
              return entryResponse({
                'Entries': [
                  {'library_entry_id': 34, 'library_list_id': 5},
                ],
              });
            }),
          );
          final refresh = service.syncLibrary();
          await started.future;
          expect(
            (await service.updateCompleteLibraryEntry(draft())).outcome,
            LibrarySaveOutcome.saved,
          );
          older.complete(
            http.Response(
              jsonEncode({
                'pagination': {'next': null, 'count': 1},
                'data': [
                  {
                    'id': '34',
                    'state': 'reading',
                    'progress_chapter': 2,
                    'Series': {'id': '1', 'title': 'Series One'},
                  },
                ],
              }),
              200,
            ),
          );
          await refresh;
          expect((await storedEntry()).progressChapter, 7);
          expect((await storedEntry()).listIdsJson, '[5]');
          expect(pages, 2);
        },
      );

      test(
        'accepted write after an account switch returns refresh pending',
        () async {
          final started = Completer<void>();
          final reply = Completer<http.Response>();
          var requests = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((request) {
              requests++;
              started.complete();
              return reply.future;
            }),
          );
          final save = service.updateCompleteLibraryEntry(draft());
          await started.future;
          final dao = getIt<AppDatabase>().ownedLibraryDao;
          final lease = await dao.activate(
            VerifiedLibraryOwner.fromVerifiedAccountId('account-b'),
          );
          mockAuth.useLease(lease);
          reply.complete(http.Response('{"status":200,"data":true}', 200));
          expect((await save).outcome, LibrarySaveOutcome.refreshPending);
          expect(requests, 1);
          expect(await dao.findEntry(lease.owner, '1'), isNull);
        },
      );

      for (final status in [400, 403, 404, 409, 429]) {
        test('rejected PATCH preserves owned fields (HTTP $status)', () async {
          await seedEntry(chapter: 3);
          final lease = mockAuth.libraryLease!;
          await getIt<AppDatabase>().customStatement(
            "UPDATE owned_library_entries SET list_ids_json = '[5]' WHERE owner_id = ?",
            [lease.owner.id],
          );
          var calls = 0;
          service = LibraryService(
            auth: mockAuth,
            rateLimitCoordinator: RateLimitCoordinator(),
            httpClient: MockClient((request) async {
              calls++;
              expect(request.method, 'PATCH');
              return http.Response('{}', status, headers: {'retry-after': '0'});
            }),
          );
          await expectLater(
            service.updateCompleteLibraryEntry(draft()),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', status),
            ),
          );
          expect(calls, 1);
          expect((await storedEntry()).progressChapter, 3);
          expect((await storedEntry()).listIdsJson, '[5]');
        });
      }

      test('401 recovers credentials without replaying the PATCH', () async {
        var calls = 0;
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('{}', 401);
          }),
        );
        await expectLater(
          service.updateCompleteLibraryEntry(draft()),
          throwsA(isA<AuthException>()),
        );
        expect(calls, 1);
        expect(mockAuth.rejectedTokens, ['access-old']);
      });

      test(
        'queued quick progress waits for the full edit and its readback',
        () async {
          await seedEntry();
          final started = Completer<void>();
          final reply = Completer<http.Response>();
          final methods = <String>[];
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((request) async {
              methods.add(request.method);
              if (request.method == 'PATCH') {
                started.complete();
                return reply.future;
              }
              return request.method == 'GET'
                  ? entryResponse()
                  : http.Response('{}', 200);
            }),
          );
          final edit = service.updateCompleteLibraryEntry(draft());
          await started.future;
          final quick = service.updateLibraryEntryProgress(
            '1',
            progressChapter: 8,
          );
          expect(methods, ['PATCH']);
          reply.complete(http.Response('{"status":200,"data":true}', 200));
          expect((await edit).outcome, LibrarySaveOutcome.saved);
          await quick;
          expect(methods, ['PATCH', 'GET', 'PUT']);
          expect((await storedEntry()).progressChapter, 8);
        },
      );

      test(
        'stale draft and late GET cannot write after switching accounts',
        () async {
          await seedEntry(chapter: 2);
          final oldDraft = draft();
          final started = Completer<void>();
          final reply = Completer<http.Response>();
          var calls = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((_) {
              calls++;
              started.complete();
              return reply.future;
            }),
          );
          final read = expectLater(
            service.fetchAuthoritativeLibraryEntry('1'),
            throwsA(isA<AuthException>()),
          );
          await started.future;
          final dao = getIt<AppDatabase>().ownedLibraryDao;
          final newLease = await dao.activate(
            VerifiedLibraryOwner.fromVerifiedAccountId('account-b'),
          );
          mockAuth.useLease(newLease);
          reply.complete(entryResponse());
          await read;
          await expectLater(
            service.updateCompleteLibraryEntry(oldDraft),
            throwsA(isA<AuthException>()),
          );
          expect(calls, 1);
          expect((await storedEntry()).progressChapter, 2);
          expect(await dao.findEntry(newLease.owner, '1'), isNull);
        },
      );

      test(
        'validates and reconciles authoritative identity and memberships',
        () async {
          await seedEntry();
          var reply = entryResponse();
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((_) async => reply),
          );
          final entry = (await service.fetchAuthoritativeLibraryEntry('1'))!;
          expect(entry.listIds, isNull);
          expect(entry.startDate, '2026-02-21');
          expect(entry.priority, 20);
          expect(entry.numberOfRereads, 2);
          expect(entry.note, 'private');
          expect(entry.readLink, 'https://example.org/read');
          expect(entry.isPrivate, isTrue);
          expect(entry.progressChapter, 7);
          reply = entryResponse({
            'Entries': [
              {'library_entry_id': 34, 'library_list_id': 5},
            ],
          });
          expect((await service.fetchAuthoritativeLibraryEntry('1'))!.listIds, [
            5,
          ]);
          reply = entryResponse();
          expect(
            (await service.fetchAuthoritativeLibraryEntry('1'))!.listIds,
            isNull,
          );
          expect((await storedEntry()).listIdsJson, '[5]');
          reply = entryResponse({'Entries': []});
          expect(
            (await service.fetchAuthoritativeLibraryEntry('1'))!.listIds,
            isEmpty,
          );
          reply = entryResponse({'progress_chapter': 7.5});
          await expectLater(
            service.fetchAuthoritativeLibraryEntry('1'),
            throwsFormatException,
          );
          expect((await storedEntry()).progressChapter, 7);
          for (final bad in [
            {'user_id': 'other'},
            {'series_id': 2},
          ]) {
            reply = entryResponse(bad);
            await expectLater(
              service.fetchAuthoritativeLibraryEntry('1'),
              throwsFormatException,
            );
          }
          reply = http.Response('{"status":404}', 404);
          expect(await service.fetchAuthoritativeLibraryEntry('1'), isNull);
        },
      );

      test('lists follow trusted links and reject another origin', () async {
        final paths = <Uri>[];
        var next = '?page=2';
        service = LibraryService(
          auth: mockAuth,
          httpClient: MockClient((request) async {
            paths.add(request.url);
            final first = request.url.queryParameters['page'] == null;
            return http.Response(
              jsonEncode({
                'status': 200,
                'pagination': {'next': first ? next : null},
                'data': [
                  {'id': first ? 1 : 2, 'name': 'List', 'is_private': first},
                ],
              }),
              200,
            );
          }),
        );
        final lease = mockAuth.libraryLease!;
        final lists = await service.fetchAccountLibraryLists(lease);
        expect(lists.map((list) => list.id), [1, 2]);
        expect(lists.map((list) => list.isPrivate), [true, false]);
        next = 'https://elsewhere.example/v2/my/library/lists?page=2';
        await expectLater(
          service.fetchAccountLibraryLists(lease),
          throwsFormatException,
        );
        expect(paths, hasLength(3));
      });

      test(
        'create and patch send intentional fields and use normalized GET',
        () async {
          await seedEntry();
          final methods = <String>[];
          final payloads = <Object?>[];
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((request) async {
              methods.add(request.method);
              if (methods.length == 1) {
                return http.Response('{"status":404}', 404);
              }
              if (request.method == 'POST') {
                expect((await storedEntry()).id, 'entry-1');
              }
              if (request.method == 'GET') {
                return entryResponse({'Entries': []});
              }
              payloads.add(jsonDecode(request.body));
              final status = request.method == 'POST' ? 201 : 200;
              return http.Response('{"status":$status,"data":true}', status);
            }),
          );
          final created = await service.createCompleteLibraryEntry(draft());
          expect(created.outcome, LibrarySaveOutcome.saved);
          expect(created.entry!.rating, isNull);
          expect(created.entry!.progressVolume, isNull);
          expect(payloads.single, {
            'state': 'reading',
            'priority': 25,
            'start_date': '2026-02-21',
            'finish_date': null,
            'progress_chapter': 7,
            'progress_volume': 0,
            'number_of_rereads': 2,
            'read_link': 'https://example.org/read',
            'is_private': true,
            'rating': 0,
            'note': null,
            'lists': [5, 7],
          });
          final updated = await service.updateCompleteLibraryEntry(
            LibraryEntryDraft(
              lease: mockAuth.libraryLease!,
              seriesId: '1',
              lists: const EntryField.set([]),
            ),
          );
          expect(updated.entry!.listIds, isEmpty);
          expect(payloads.last, {'lists': []});
          expect(methods, ['GET', 'POST', 'GET', 'PATCH', 'GET']);
        },
      );

      test(
        'validates dates, ranges and list count without dropping explicit nulls',
        () {
          final lease = mockAuth.libraryLease!;
          expect(
            LibraryEntryDraft(
              lease: lease,
              seriesId: '1',
              note: const EntryField.set(null),
            ).toJson(),
            {'note': null},
          );
          expect(
            () => LibraryEntryDraft(
              lease: lease,
              seriesId: '1',
              startDate: const EntryField.set('2026-02-30'),
            ).toJson(),
            throwsArgumentError,
          );
          expect(
            () => LibraryEntryDraft(
              lease: lease,
              seriesId: '1',
              rating: const EntryField.set(101),
            ).toJson(),
            throwsArgumentError,
          );
          expect(
            () => LibraryEntryDraft(
              lease: lease,
              seriesId: '1',
              lists: EntryField.set(List.generate(31, (i) => i + 1)),
            ).toJson(),
            throwsArgumentError,
          );
        },
      );

      test(
        'distinguishes duplicate, uncertain create and accepted write awaiting refresh',
        () async {
          await seedEntry();
          var exists = true;
          var ambiguous = false;
          var writes = 0;
          service = LibraryService(
            auth: mockAuth,
            httpClient: MockClient((request) async {
              if (request.method == 'POST') {
                writes++;
                if (ambiguous) {
                  exists = true;
                  throw http.ClientException('disconnected');
                }
                return http.Response('{"status":201,"data":true}', 201);
              }
              return exists
                  ? entryResponse()
                  : http.Response('{"status":404}', 404);
            }),
          );
          await expectLater(
            service.createCompleteLibraryEntry(draft()),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 409),
            ),
          );
          expect(writes, 0);
          exists = false;
          expect(
            (await service.createCompleteLibraryEntry(draft())).outcome,
            LibrarySaveOutcome.refreshPending,
          );
          ambiguous = true;
          final result = await service.createCompleteLibraryEntry(draft());
          expect(result.outcome, LibrarySaveOutcome.uncertain);
          expect(result.entry, isNotNull);
          expect(writes, 2);
        },
      );
    });
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
        expect((await dao.readState(b.owner))!.watermark, isNull);
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
      'PATCH rating': () => service.updateLibraryEntryRating('1', 8),
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
      // mutation itself still contributes exactly one request, and the rating
      // change also makes its authoritative readback.
      expect(calls, 9);
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
