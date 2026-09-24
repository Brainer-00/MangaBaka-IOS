import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/network/rate_limit_coordinator.dart';
import 'package:mangabaka_app/features/series/services/series_autocomplete_service.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SeriesAutocompleteService service;
  late DateTime now;
  late RateLimitCoordinator rateLimits;
  late int requests;
  late List<http.Response> responses;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
    SharedPreferences.setMockInitialValues({});
    await SettingsManager().init();
    now = DateTime.utc(2026, 9, 24, 12);
    rateLimits = RateLimitCoordinator(clock: () => now, delay: (_) async {});
    requests = 0;
    responses = [];
    service = SeriesAutocompleteService(
      debounceDuration: Duration.zero,
      rateLimitCoordinator: rateLimits,
      clientFactory: () => MockClient((_) async {
        requests++;
        return responses.removeAt(0);
      }),
    );
  });

  tearDown(() => service.dispose());

  group('SeriesAutocompleteService', () {
    test('search returns empty for short queries', () {
      List<AutocompleteSeriesResult>? results;
      service.search('a', onResults: (res) => results = res);
      expect(results, isEmpty);
    });

    test('a 429 records cooldown and preserves existing suggestions', () async {
      responses.add(http.Response('{}', 429, headers: {'retry-after': '12'}));
      final existing = <AutocompleteSeriesResult>[
        AutocompleteSeriesResult.fromJson({
          'id': 1,
          'title': 'Existing',
          'type': 'manga',
        }),
      ];
      var displayed = existing;
      String? error;

      service.search(
        'existing',
        onResults: (results) => displayed = results,
        onError: (message) => error = message,
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(requests, 1);
      expect(error, 'rate_limited');
      expect(displayed, same(existing));
      expect(rateLimits.remainingCooldown, const Duration(seconds: 12));
    });

    test(
      'active cooldown prevents a fresh request and preserves suggestions',
      () async {
        rateLimits.updateFromRetryAfter('10');
        final existing = <AutocompleteSeriesResult>[
          AutocompleteSeriesResult.fromJson({
            'id': 2,
            'title': 'Still visible',
            'type': 'manga',
          }),
        ];
        var displayed = existing;
        String? error;

        service.search(
          'blocked',
          onResults: (results) => displayed = results,
          onError: (message) => error = message,
        );
        await Future<void>.delayed(Duration.zero);

        expect(requests, 0);
        expect(error, 'rate_limited');
        expect(displayed, same(existing));
      },
    );

    test('successful response still returns and caches results', () async {
      responses.add(
        http.Response(
          jsonEncode({
            'data': [
              {'id': 3, 'title': 'Result', 'type': 'manga'},
            ],
          }),
          200,
        ),
      );
      List<AutocompleteSeriesResult>? displayed;

      service.search('result', onResults: (results) => displayed = results);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(requests, 1);
      expect(displayed, hasLength(1));
    });
  });
}
