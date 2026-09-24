import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/features/profile/services/auth/windows_auth_handler.dart';

void main() {
  group('raw authorization endpoint validation', () {
    const validEndpoint = '${AppConstants.authBaseUrl}/authorize';

    bool trusted(String value) =>
        WindowsAuthHandler.isTrustedAuthorizationEndpoint(Uri.parse(value));

    test('correct production endpoint remains allowed', () {
      expect(trusted(validEndpoint), isTrue);
    });

    final rejectedEndpoints = <String, String>{
      'HTTP': 'http://mangabaka.org/auth/oauth2/authorize',
      'wrong host': 'https://example.org/auth/oauth2/authorize',
      'deceptive host': 'https://mangabaka.org.evil.test/auth/oauth2/authorize',
      'non-443 port': 'https://mangabaka.org:444/auth/oauth2/authorize',
      'wrong path': 'https://mangabaka.org/auth/oauth2/other',
      'userInfo': 'https://user@mangabaka.org/auth/oauth2/authorize',
      'query': 'https://mangabaka.org/auth/oauth2/authorize?next=1',
      'fragment': 'https://mangabaka.org/auth/oauth2/authorize#fragment',
    };

    for (final entry in rejectedEndpoints.entries) {
      test('rejects ${entry.key} before starting authorization', () async {
        expect(trusted(entry.value), isFalse);

        await expectLater(
          WindowsAuthHandler.authorizeAndExchangeCode(
            clientId: 'test-client',
            redirectUri: AppConstants.oauthRedirectUri,
            authorizationEndpoint: entry.value,
            tokenEndpoint: '${AppConstants.authBaseUrl}/token',
            scopes: AppConstants.oauthScopes,
          ),
          throwsA(
            isA<AuthException>().having(
              (error) => error.code,
              'code',
              'INVALID_OAUTH_AUTHORIZATION_ENDPOINT',
            ),
          ),
        );
      });
    }

    test('malformed endpoint uses the stable authorization error', () async {
      await expectLater(
        WindowsAuthHandler.authorizeAndExchangeCode(
          clientId: 'test-client',
          redirectUri: AppConstants.oauthRedirectUri,
          authorizationEndpoint: '%',
          tokenEndpoint: '${AppConstants.authBaseUrl}/token',
          scopes: AppConstants.oauthScopes,
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'INVALID_OAUTH_AUTHORIZATION_ENDPOINT',
          ),
        ),
      );
    });
  });

  group('token endpoint validation', () {
    bool trusted(String value) =>
        WindowsAuthHandler.isTrustedTokenEndpoint(Uri.parse(value));

    test('allows the exact production endpoint', () {
      expect(trusted('${AppConstants.authBaseUrl}/token'), isTrue);
    });

    test('rejects HTTP', () {
      expect(trusted('http://mangabaka.org/auth/oauth2/token'), isFalse);
    });

    test('rejects wrong and deceptive hosts', () {
      expect(trusted('https://example.org/auth/oauth2/token'), isFalse);
      expect(
        trusted('https://mangabaka.org.evil.test/auth/oauth2/token'),
        isFalse,
      );
    });

    test('rejects a non-443 port', () {
      expect(trusted('https://mangabaka.org:444/auth/oauth2/token'), isFalse);
    });

    test('rejects a wrong path', () {
      expect(trusted('https://mangabaka.org/auth/oauth2/other'), isFalse);
    });

    test('rejects user info', () {
      expect(trusted('https://user@mangabaka.org/auth/oauth2/token'), isFalse);
    });

    test('rejects query and fragment', () {
      expect(
        trusted('https://mangabaka.org/auth/oauth2/token?next=1'),
        isFalse,
      );
      expect(
        trusted('https://mangabaka.org/auth/oauth2/token#fragment'),
        isFalse,
      );
    });

    test('malformed token endpoint uses the stable token error', () async {
      await expectLater(
        WindowsAuthHandler.authorizeAndExchangeCode(
          clientId: 'test-client',
          redirectUri: AppConstants.oauthRedirectUri,
          authorizationEndpoint: '${AppConstants.authBaseUrl}/authorize',
          tokenEndpoint: '%',
          scopes: AppConstants.oauthScopes,
        ),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'INVALID_OAUTH_TOKEN_ENDPOINT',
          ),
        ),
      );
    });
  });

  test('redirect URI validation allows only the registered URI', () {
    expect(
      WindowsAuthHandler.isExpectedRedirectUri(
        Uri.parse(AppConstants.oauthRedirectUri),
      ),
      isTrue,
    );
    expect(
      WindowsAuthHandler.isExpectedRedirectUri(
        Uri.parse('wrong.scheme://oauthredirect'),
      ),
      isFalse,
    );
    expect(
      WindowsAuthHandler.isExpectedRedirectUri(
        Uri.parse('io.github.brainer00.mangabaka-ios://wrong-path'),
      ),
      isFalse,
    );
  });

  test('refresh errors use only explicit OAuth error identifiers', () {
    expect(
      WindowsAuthHandler.refreshErrorCodeForTesting(
        '{"error":"invalid_grant","error_description":"ignored"}',
      ),
      'INVALID_GRANT',
    );
    expect(
      WindowsAuthHandler.refreshErrorCodeForTesting(
        '{"error":"invalid_token"}',
      ),
      'INVALID_TOKEN',
    );
    expect(
      WindowsAuthHandler.refreshErrorCodeForTesting(
        '{"error":"temporarily_unavailable"}',
      ),
      'TOKEN_REFRESH_FAILED',
    );
    expect(
      WindowsAuthHandler.refreshErrorCodeForTesting('not-json'),
      'TOKEN_REFRESH_FAILED',
    );
  });
}
