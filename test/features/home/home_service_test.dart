import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/features/home/services/home_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth extends Fake implements ProfileAuthService {
  String accessToken = 'access-old';
  String recoveredToken = 'access-new';
  Object? recoveryError;
  int validTokenCalls = 0;
  final rejectedTokens = <String>[];

  @override
  bool get isLoggedIn => true;

  @override
  Future<String> getValidAccessToken() async {
    validTokenCalls++;
    return accessToken;
  }

  @override
  Future<String> recoverAfterUnauthorized(String rejectedAccessToken) async {
    rejectedTokens.add(rejectedAccessToken);
    final error = recoveryError;
    if (error != null) throw error;
    accessToken = recoveredToken;
    return recoveredToken;
  }
}

http.Response _readinessResponse() => http.Response(
  jsonEncode({
    'data': {'cold_start': false, 'profile_stale': false, 'library_count': 4},
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
  });

  group('HomeService authenticated GET recovery', () {
    test(
      'successful authenticated GET sends the initial bearer token',
      () async {
        final auth = _FakeAuth();
        String? authorization;
        final service = HomeService(
          auth: auth,
          client: MockClient((request) async {
            authorization = request.headers['Authorization'];
            return _readinessResponse();
          }),
        );

        final result = await service.fetchForYouReadiness();

        expect(result, isNotNull);
        expect(authorization, 'Bearer access-old');
        expect(auth.rejectedTokens, isEmpty);
      },
    );

    test(
      'first 401 recovers once and retries with the recovered token',
      () async {
        final auth = _FakeAuth();
        final authorizationHeaders = <String?>[];
        final service = HomeService(
          auth: auth,
          client: MockClient((request) async {
            authorizationHeaders.add(request.headers['Authorization']);
            return authorizationHeaders.length == 1
                ? http.Response('', 401)
                : _readinessResponse();
          }),
        );

        final result = await service.fetchForYouReadiness();

        expect(result, isNotNull);
        expect(authorizationHeaders, [
          'Bearer access-old',
          'Bearer access-new',
        ]);
        expect(auth.rejectedTokens, ['access-old']);
      },
    );

    test('second consecutive 401 stops without another recovery', () async {
      final auth = _FakeAuth();
      var requests = 0;
      final service = HomeService(
        auth: auth,
        client: MockClient((_) async {
          requests++;
          return http.Response('', 401);
        }),
      );

      expect(await service.fetchForYouReadiness(), isNull);
      expect(requests, 2);
      expect(auth.rejectedTokens, ['access-old']);
    });

    for (final statusCode in [403, 500]) {
      test('HTTP $statusCode does not trigger auth recovery', () async {
        final auth = _FakeAuth();
        var requests = 0;
        final service = HomeService(
          auth: auth,
          client: MockClient((_) async {
            requests++;
            return http.Response('', statusCode);
          }),
        );

        expect(await service.fetchForYouReadiness(), isNull);
        expect(requests, 1);
        expect(auth.rejectedTokens, isEmpty);
      });
    }

    test(
      'session expiry during recovery does not issue another request',
      () async {
        final auth = _FakeAuth()..recoveryError = SessionExpiredException();
        var requests = 0;
        final service = HomeService(
          auth: auth,
          client: MockClient((_) async {
            requests++;
            return http.Response('', 401);
          }),
        );

        expect(await service.fetchForYouReadiness(), isNull);
        expect(requests, 1);
        expect(auth.rejectedTokens, ['access-old']);
      },
    );

    test(
      'transient refresh failure during recovery does not retry or loop',
      () async {
        final auth = _FakeAuth()
          ..recoveryError = AuthException(
            message: 'Refresh temporarily failed',
            code: 'TOKEN_REFRESH_FAILED',
          );
        var requests = 0;
        final service = HomeService(
          auth: auth,
          client: MockClient((_) async {
            requests++;
            return http.Response('', 401);
          }),
        );

        expect(await service.fetchForYouReadiness(), isNull);
        expect(requests, 1);
        expect(auth.rejectedTokens, ['access-old']);
      },
    );

    test('public rails work without auth registration or injection', () async {
      final service = HomeService(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], isNull);
          return http.Response(jsonEncode({'data': <Object>[]}), 200);
        }),
      );

      expect(await service.fetchRising(), isEmpty);
    });

    test(
      'personalized rail remains empty after recovery ultimately fails',
      () async {
        final auth = _FakeAuth();
        var requests = 0;
        final service = HomeService(
          auth: auth,
          client: MockClient((_) async {
            requests++;
            return http.Response('', 401);
          }),
        );

        expect(await service.fetchForYou(), isEmpty);
        expect(requests, 2);
        expect(auth.rejectedTokens, ['access-old']);
      },
    );
  });
}
