import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/network/rate_limit_coordinator.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:drift/native.dart';

class MockProfileAuthService extends Fake implements ProfileAuthService {
  String accessToken = 'access-old';
  String recoveredToken = 'access-new';
  Object? recoveryError;
  final rejectedTokens = <String>[];

  @override
  bool get isLoggedIn => false;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LibraryService service;
  late MockProfileAuthService mockAuth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<AppDatabase>(
      AppDatabase.forTesting(NativeDatabase.memory()),
    );

    mockAuth = MockProfileAuthService();
    service = LibraryService(auth: mockAuth);
  });

  tearDown(() async {
    await getIt<AppDatabase>().close();
    await resetServiceLocator();
  });

  group('LibraryService', () {
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
              : http.Response('{"data":[]}', 200);
        }),
      );

      final result = await service.fetchPage('token', 1);

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
        service.fetchPage('token', 1),
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
              : http.Response('{"data":[]}', 200);
        }),
      );

      final result = await service.fetchPage('access-old', 1);

      expect(result.entries, isEmpty);
      expect(authorizationHeaders, ['Bearer access-old', 'Bearer access-new']);
      expect(mockAuth.rejectedTokens, ['access-old']);
    });

    test('fetchPage propagates session expiry from 401 recovery', () async {
      mockAuth.recoveryError = SessionExpiredException();
      service = LibraryService(
        auth: mockAuth,
        database: getIt<AppDatabase>(),
        httpClient: MockClient((_) async => http.Response('', 401)),
      );

      await expectLater(
        service.fetchPage('access-old', 1),
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
        service.fetchPage('access-old', 1),
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
          return http.Response('{"data":[]}', 200);
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

    for (final operation in mutationOperations.entries) {
      test('${operation.key} is not replayed after 401', () async {
        mockAuth.rejectedTokens.clear();
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return http.Response('', 401);
        });

        await expectLater(
          http.runWithClient(operation.value, () => client),
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
        http.runWithClient(
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

    test('optimistic progress rolls back when 401 is not replayed', () async {
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
          .into(database.libraryEntriesTable)
          .insert(
            LibraryEntriesTableCompanion.insert(
              id: 'entry-1',
              seriesId: '1',
              state: 'reading',
              progressChapter: const Value(2),
            ),
          );
      var calls = 0;

      await expectLater(
        http.runWithClient(
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
        database.libraryEntriesTable,
      )..where((row) => row.seriesId.equals('1'))).getSingle();
      expect(entry.progressChapter, 2);
      expect(calls, 1);
    });
  });
}
