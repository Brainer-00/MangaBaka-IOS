import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/network/rate_limit_coordinator.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:drift/native.dart';

class MockProfileAuthService extends Fake implements ProfileAuthService {
  @override
  bool get isLoggedIn => false;
}

void main() {
  late LibraryService service;
  late MockProfileAuthService mockAuth;

  setUp(() async {
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
  });
}
