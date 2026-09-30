import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/features/series/services/metadata_cache.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';

class _MetadataCache extends Fake implements MetadataCache {
  @override
  Future<List<Map<String, dynamic>>?> read(String key) async => const [];
}

void main() {
  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
  });

  group('MetadataService', () {
    test('getGenreLabel formats fallback correctly', () {
      final service = MetadataService();
      expect(service.getGenreLabel('action_adventure'), 'Action Adventure');
      expect(service.getGenreLabel('slice_of_life'), 'Slice Of Life');
    });

    test('initial state is not initialized', () {
      final service = MetadataService();
      expect(service.isInitialized, isFalse);
    });

    test('cache initialization does not start its network refresh', () async {
      var calls = 0;
      final service = MetadataService(
        cache: _MetadataCache(),
        client: MockClient((_) async {
          calls++;
          return http.Response('{"data":[]}', 200);
        }),
      );

      await service.init();

      expect(service.isInitialized, isTrue);
      expect(calls, 0);

      await Future.wait([
        service.refreshInBackground(),
        service.refreshInBackground(),
      ]);

      expect(calls, 2);
    });
  });
}
