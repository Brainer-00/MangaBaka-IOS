import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/auth/auth_network_client.dart';
import 'package:mangabaka_app/features/profile/services/auth/auth_storage.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';

class MemoryAuthStorage extends AuthStorage {
  final values = <String, String>{};
  String? failOnWriteKey;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (key == failOnWriteKey) {
      throw PlatformException(code: 'write-failed');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();
}

class FakeAuthNetworkClient extends AuthNetworkClient {
  @override
  Future<MbProfile> fetchProfile(String accessToken) async {
    return MbProfile(id: 'user-1', role: 'user', scopes: ['openid']);
  }
}

TokenResponse tokenResponse({
  String? accessToken = 'access-new',
  String? refreshToken,
  String? idToken,
  DateTime? expiration,
}) {
  return TokenResponse(
    accessToken,
    refreshToken,
    expiration,
    idToken,
    'Bearer',
    const ['openid'],
    const {},
  );
}

void main() {
  late MemoryAuthStorage storage;
  late ProfileAuthService auth;

  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    storage = MemoryAuthStorage();
    dotenv.loadFromString(
      envString:
          'MANGABAKA_APP_CLIENT_ID=test-client\n'
          'MANGABAKA_APP_REDIRECT_URI='
          'io.github.brainer00.mangabaka-ios://oauthredirect',
    );
    auth = ProfileAuthService(
      storage: storage,
      network: FakeAuthNetworkClient(),
    );
  });

  ProfileAuthService serviceForLogin(TokenResponse response) {
    return ProfileAuthService(
      storage: storage,
      network: FakeAuthNetworkClient(),
      loginTokens: () async => response,
    );
  }

  group('token persistence', () {
    test('login stores a supplied refresh token', () async {
      auth = serviceForLogin(tokenResponse(refreshToken: 'refresh-new'));
      await auth.login();
      expect(storage.values[AuthStorage.kRefreshToken], 'refresh-new');
    });

    test(
      'initial login without optional tokens removes stale values',
      () async {
        storage.values.addAll({
          AuthStorage.kRefreshToken: 'refresh-old',
          AuthStorage.kIdToken: 'id-old',
          AuthStorage.kAccessTokenExp: 'expiry-old',
        });
        auth = serviceForLogin(tokenResponse());
        await auth.login();
        expect(storage.values[AuthStorage.kRefreshToken], isNull);
        expect(storage.values[AuthStorage.kIdToken], isNull);
        expect(storage.values[AuthStorage.kAccessTokenExp], isNull);
      },
    );

    test('refresh with a rotated refresh token replaces the old one', () async {
      storage.values[AuthStorage.kRefreshToken] = 'refresh-old';
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => tokenResponse(refreshToken: 'refresh-new'),
      );
      storage.values[AuthStorage.kAccessToken] = 'access-old';
      storage.values[AuthStorage.kAccessTokenExp] = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      await auth.getValidAccessToken();
      expect(storage.values[AuthStorage.kRefreshToken], 'refresh-new');
    });

    test('refresh without optional tokens preserves old values', () async {
      storage.values.addAll({
        AuthStorage.kRefreshToken: 'refresh-old',
        AuthStorage.kIdToken: 'id-old',
      });
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => tokenResponse(),
      );
      storage.values[AuthStorage.kAccessToken] = 'access-old';
      storage.values[AuthStorage.kAccessTokenExp] = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      await auth.getValidAccessToken();
      expect(storage.values[AuthStorage.kRefreshToken], 'refresh-old');
      expect(storage.values[AuthStorage.kIdToken], 'id-old');
    });

    test('refresh without expiration removes the old expiration', () async {
      storage.values.addAll({
        AuthStorage.kAccessToken: 'access-old',
        AuthStorage.kRefreshToken: 'refresh-old',
        AuthStorage.kAccessTokenExp: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      });
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => tokenResponse(),
      );
      await auth.getValidAccessToken();
      expect(storage.values[AuthStorage.kAccessTokenExp], isNull);
    });

    test('missing or empty access token is rejected before writes', () async {
      storage.values[AuthStorage.kAccessToken] = 'access-old';
      for (final invalid in <String?>[null, '']) {
        auth = serviceForLogin(tokenResponse(accessToken: invalid));
        await expectLater(
          auth.login(),
          throwsA(
            isA<AuthException>().having(
              (error) => error.code,
              'code',
              'INVALID_TOKEN_RESPONSE',
            ),
          ),
        );
        expect(storage.values[AuthStorage.kAccessToken], 'access-old');
      }
    });

    test(
      'partial persistence failure clears the entire local session',
      () async {
        storage.values[AuthStorage.kProfileCache] = 'cached-profile';
        storage.failOnWriteKey = AuthStorage.kRefreshToken;
        auth = serviceForLogin(tokenResponse(refreshToken: 'refresh-new'));
        await expectLater(
          auth.login(),
          throwsA(
            isA<AuthException>().having(
              (error) => error.code,
              'code',
              'TOKEN_PERSIST_FAILED',
            ),
          ),
        );
        expect(storage.values, isEmpty);
        expect(await auth.hasSession(), isFalse);
        expect(auth.isLoggedIn, isFalse);
      },
    );
  });

  group('refresh failures', () {
    Future<void> seedExpiredSession() async {
      storage.values.addAll({
        AuthStorage.kAccessToken: 'access-old',
        AuthStorage.kRefreshToken: 'refresh-old',
        AuthStorage.kAccessTokenExp: DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      });
    }

    Future<void> expectSessionExpiredFor(Object error) async {
      await seedExpiredSession();
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => throw error,
      );

      await expectLater(
        auth.getValidAccessToken(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(storage.values, isEmpty);
    }

    Future<void> expectRefreshFailedAndSessionPreserved(Object error) async {
      await seedExpiredSession();
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => throw error,
      );

      await expectLater(
        auth.getValidAccessToken(),
        throwsA(
          isA<AuthException>().having(
            (exception) => exception.code,
            'code',
            'TOKEN_REFRESH_FAILED',
          ),
        ),
      );
      expect(storage.values[AuthStorage.kAccessToken], 'access-old');
      expect(storage.values[AuthStorage.kRefreshToken], 'refresh-old');
    }

    test('generic PlatformException code invalid_grant expires session', () {
      return expectSessionExpiredFor(PlatformException(code: 'INVALID_GRANT'));
    });

    test('generic PlatformException details invalid_token expires session', () {
      return expectSessionExpiredFor(
        PlatformException(
          code: 'refresh_failed',
          details: const {'error': 'Invalid_Token'},
        ),
      );
    });

    test('generic PlatformException message mention preserves session', () {
      return expectRefreshFailedAndSessionPreserved(
        PlatformException(
          code: 'refresh_failed',
          message: 'Provider mentioned invalid_grant in prose',
        ),
      );
    });

    test('arbitrary generic PlatformException preserves session', () {
      return expectRefreshFailedAndSessionPreserved(
        PlatformException(code: '401', details: const {'status': 401}),
      );
    });

    test('typed AppAuth invalid_grant expires session', () {
      return expectSessionExpiredFor(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            error: 'invalid_grant',
          ),
        ),
      );
    });

    test('typed AppAuth invalid_token expires session', () {
      return expectSessionExpiredFor(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            error: 'invalid_token',
          ),
        ),
      );
    });

    test('other typed AppAuth OAuth error preserves session', () {
      return expectRefreshFailedAndSessionPreserved(
        FlutterAppAuthPlatformException(
          code: 'token_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
            error: 'temporarily_unavailable',
          ),
        ),
      );
    });

    test('explicit invalid_grant clears session and expires it', () async {
      await seedExpiredSession();
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => throw ApiException(
          message: 'refresh failed',
          statusCode: 400,
          code: 'INVALID_GRANT',
        ),
      );
      await expectLater(
        auth.getValidAccessToken(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(storage.values, isEmpty);
    });

    test('explicit invalid_token clears session and expires it', () async {
      await seedExpiredSession();
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => throw ApiException(
          message: 'refresh failed',
          statusCode: 401,
          code: 'INVALID_TOKEN',
        ),
      );
      await expectLater(
        auth.getValidAccessToken(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(storage.values, isEmpty);
    });

    for (final statusCode in [400, 401]) {
      test('unrelated HTTP $statusCode preserves session', () async {
        await seedExpiredSession();
        auth = ProfileAuthService(
          storage: storage,
          refreshTokens: (_) async => throw ApiException(
            message: 'refresh failed',
            statusCode: statusCode,
            code: 'TOKEN_REFRESH_FAILED',
          ),
        );
        await expectLater(
          auth.getValidAccessToken(),
          throwsA(
            isA<AuthException>().having(
              (error) => error.code,
              'code',
              'TOKEN_REFRESH_FAILED',
            ),
          ),
        );
        expect(storage.values[AuthStorage.kAccessToken], 'access-old');
        expect(storage.values[AuthStorage.kRefreshToken], 'refresh-old');
      });
    }

    test('generic refresh failure preserves session', () async {
      await seedExpiredSession();
      auth = ProfileAuthService(
        storage: storage,
        refreshTokens: (_) async => throw StateError('temporary failure'),
      );
      await expectLater(
        auth.getValidAccessToken(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'TOKEN_REFRESH_FAILED',
          ),
        ),
      );
      expect(storage.values[AuthStorage.kAccessToken], 'access-old');
    });
  });

  test('missing access token does not count as a session', () async {
    storage.values[AuthStorage.kRefreshToken] = 'orphaned';
    expect(await auth.hasSession(), isFalse);
    expect(storage.values, isEmpty);
  });

  test('explicit logout clears local credentials', () async {
    storage.values[AuthStorage.kAccessToken] = 'access';
    await auth.logout();
    expect(storage.values, isEmpty);
    expect(auth.isLoggedIn, isFalse);
  });

  test('typed AppAuth cancellation maps to AuthCancelledException', () async {
    auth = ProfileAuthService(
      storage: storage,
      network: FakeAuthNetworkClient(),
      loginTokens: () async => throw FlutterAppAuthUserCancelledException(
        code: 'user_cancelled',
        platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
      ),
    );

    await expectLater(auth.login(), throwsA(isA<AuthCancelledException>()));
  });
}
