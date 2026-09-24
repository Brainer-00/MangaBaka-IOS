import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/utils/external_url_launcher.dart';
import 'package:win32_registry/win32_registry.dart';

class WindowsAuthHandler {
  static final _logger = LoggingService.logger;

  /// The sign-in currently waiting on the browser, if any.
  ///
  /// The browser is a separate application on Windows, so closing its tab
  /// does not automatically notify this application.
  static Completer<String?>? _pending;

  /// Authorization URL retained only so the user can reopen the browser while
  /// an authorization attempt is still pending.
  ///
  /// This value must never be logged because it contains OAuth state and PKCE
  /// request metadata.
  static Uri? _pendingAuthUri;

  /// Ends a pending sign-in as cancelled.
  ///
  /// No-op when there is no authorization attempt waiting for completion.
  static void cancelPending() {
    final pending = _pending;

    if (pending != null && !pending.isCompleted) {
      pending.completeError(AuthCancelledException());
    }
  }

  /// Reopens the authorization page if a sign-in is still pending.
  static Future<void> reopenBrowser() async {
    final uri = _pendingAuthUri;

    if (uri != null && _isTrustedAuthorizationUri(uri)) {
      await ExternalUrlLauncher.launchUri(
        uri,
        allowedHosts: const {'mangabaka.org'},
      );
    }
  }

  /// Registers the custom OAuth callback protocol in the Windows Registry.
  static Future<void> registerProtocol(String scheme) async {
    try {
      final appPath = Platform.resolvedExecutable;
      final protocolRegKey = 'Software\\Classes\\$scheme';

      // Do not log the executable path. Local filesystem paths may contain
      // user-identifying information.
      _logger.info('Registering Windows OAuth callback protocol');

      final key = CURRENT_USER.create(protocolRegKey);
      key.setValue('URL Protocol', RegistryValue.string(''));

      final commandKey = key.create('shell\\open\\command');
      commandKey.setValue('', RegistryValue.string('"$appPath" "%1"'));

      commandKey.close();
      key.close();

      _logger.info('Windows OAuth callback protocol registered');
    } catch (e) {
      // Keep diagnostic usefulness without persisting exception text that
      // could contain local paths or other environment information.
      _logger.severe(
        'Failed to register Windows OAuth callback protocol '
        '(${e.runtimeType})',
      );
    }
  }

  /// Performs Authorization Code + PKCE authentication on Windows.
  static Future<TokenResponse?> authorizeAndExchangeCode({
    required String clientId,
    required String redirectUri,
    required String authorizationEndpoint,
    required String tokenEndpoint,
    required List<String> scopes,
    VoidCallback? onBrowserOpened,
  }) async {
    final parsedAuthorizationEndpoint = _tryParseUri(authorizationEndpoint);
    if (parsedAuthorizationEndpoint == null ||
        !isTrustedAuthorizationEndpoint(parsedAuthorizationEndpoint)) {
      throw AuthException(
        message: 'Invalid OAuth authorization endpoint',
        code: 'INVALID_OAUTH_AUTHORIZATION_ENDPOINT',
      );
    }

    final parsedTokenEndpoint = _tryParseUri(tokenEndpoint);
    if (parsedTokenEndpoint == null ||
        !isTrustedTokenEndpoint(parsedTokenEndpoint)) {
      throw AuthException(
        message: 'Invalid OAuth token endpoint',
        code: 'INVALID_OAUTH_TOKEN_ENDPOINT',
      );
    }

    final redirect = Uri.parse(redirectUri);

    if (!isExpectedRedirectUri(redirect)) {
      throw AuthException(
        message: 'Invalid OAuth redirect URI',
        code: 'INVALID_OAUTH_REDIRECT_URI',
      );
    }

    final scheme = redirect.scheme;

    if (scheme.isNotEmpty) {
      await registerProtocol(scheme);
    }

    final appLinks = AppLinks();

    // Generate a fresh PKCE verifier/challenge and OAuth state for every
    // authorization attempt.
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);
    final state = _generateRandomString(32);

    final authUri = parsedAuthorizationEndpoint.replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'prompt': 'consent',
      },
    );

    if (!_isTrustedAuthorizationUri(authUri)) {
      throw AuthException(
        message: 'Invalid OAuth authorization endpoint',
        code: 'INVALID_OAUTH_AUTHORIZATION_ENDPOINT',
      );
    }

    // Never log authUri. It contains OAuth state and PKCE metadata.
    _logger.info('Opening browser for Windows OAuth');

    final completer = Completer<String?>();
    _pending = completer;
    _pendingAuthUri = authUri;

    final sub = appLinks.uriLinkStream.listen(
      (uri) {
        // Never log the callback URI. It may contain the temporary
        // authorization code and OAuth state.
        _logger.fine('Received OAuth callback');

        final isExpectedCallback =
            uri.scheme == redirect.scheme &&
            uri.authority == redirect.authority &&
            uri.path == redirect.path;

        if (!isExpectedCallback) {
          return;
        }

        final receivedState = uri.queryParameters['state'];

        // State must be checked before trusting either a code or an OAuth
        // error returned through the callback.
        if (receivedState != state) {
          _logger.warning('OAuth state validation failed');

          if (!completer.isCompleted) {
            completer.completeError(
              AuthException(
                message: 'OAuth state validation failed',
                code: 'INVALID_OAUTH_STATE',
              ),
            );
          }

          return;
        }

        final oauthError = uri.queryParameters['error'];

        if (oauthError != null) {
          if (!completer.isCompleted) {
            if (oauthError == 'access_denied') {
              completer.completeError(AuthCancelledException());
            } else {
              // Do not persist error_description or the callback URI.
              completer.completeError(
                AuthException(
                  message: 'OAuth authorization failed',
                  code: 'OAUTH_AUTHORIZATION_FAILED',
                ),
              );
            }
          }

          return;
        }

        final code = uri.queryParameters['code'];

        if (code == null || code.isEmpty) {
          if (!completer.isCompleted) {
            completer.completeError(
              AuthException(
                message: 'OAuth callback did not contain an authorization code',
                code: 'MISSING_AUTHORIZATION_CODE',
              ),
            );
          }

          return;
        }

        if (!completer.isCompleted) {
          completer.complete(code);
        }
      },
      onError: (Object error) {
        // Avoid writing raw AppLinks errors because they may include URI data.
        _logger.severe('OAuth callback listener failed (${error.runtimeType})');

        if (!completer.isCompleted) {
          completer.completeError(
            AuthException(
              message: 'OAuth callback failed',
              code: 'OAUTH_CALLBACK_FAILED',
            ),
          );
        }
      },
    );

    try {
      final launched = await ExternalUrlLauncher.launchUri(
        authUri,
        allowedHosts: const {'mangabaka.org'},
      );

      if (!launched) {
        throw AuthException(
          message: 'Could not launch OAuth authorization page',
          code: 'OAUTH_BROWSER_LAUNCH_FAILED',
        );
      }

      onBrowserOpened?.call();

      final code = await completer.future.timeout(const Duration(minutes: 5));

      if (code == null || code.isEmpty) {
        throw AuthException(
          message: 'OAuth authorization did not return a code',
          code: 'MISSING_AUTHORIZATION_CODE',
        );
      }

      _logger.info('OAuth authorization received; exchanging code');

      final response = await http.post(
        parsedTokenEndpoint,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'code': code,
          'code_verifier': codeVerifier,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        _logger.info('OAuth token exchange successful');

        return TokenResponse(
          data['access_token'],
          data['refresh_token'],
          _expirationFromSeconds(data['expires_in']),
          data['id_token'],
          'Bearer',
          scopes,
          data,
        );
      }

      // OAuth error response bodies must not be logged or included in an
      // exception that could later be written into the shareable log file.
      _logger.severe(
        'OAuth token exchange failed with HTTP ${response.statusCode}',
      );

      throw ApiException(
        message: 'OAuth token exchange failed',
        statusCode: response.statusCode,
        code: 'TOKEN_EXCHANGE_FAILED',
      );
    } on TimeoutException {
      _logger.warning('OAuth login timed out');

      throw AuthException(
        message: 'OAuth login timed out',
        code: 'OAUTH_TIMEOUT',
      );
    } finally {
      await sub.cancel();

      _pending = null;
      _pendingAuthUri = null;
    }
  }

  static bool _isTrustedAuthorizationUri(Uri uri) {
    final expected = Uri.parse('${AppConstants.authBaseUrl}/authorize');
    return ExternalUrlLauncher.isAllowedHttpsUri(
          uri,
          allowedHosts: const {'mangabaka.org'},
        ) &&
        uri.scheme == expected.scheme &&
        uri.host.toLowerCase() == expected.host.toLowerCase() &&
        uri.port == expected.port &&
        uri.path == expected.path;
  }

  @visibleForTesting
  static bool isTrustedAuthorizationEndpoint(Uri uri) {
    final expected = Uri.parse('${AppConstants.authBaseUrl}/authorize');
    return _isExactTrustedEndpoint(uri, expected);
  }

  @visibleForTesting
  static bool isTrustedTokenEndpoint(Uri uri) {
    final expected = Uri.parse('${AppConstants.authBaseUrl}/token');
    return _isExactTrustedEndpoint(uri, expected);
  }

  static bool _isExactTrustedEndpoint(Uri uri, Uri expected) {
    return uri.scheme.toLowerCase() == 'https' &&
        uri.host.toLowerCase() == 'mangabaka.org' &&
        uri.port == 443 &&
        uri.scheme == expected.scheme &&
        uri.host.toLowerCase() == expected.host.toLowerCase() &&
        uri.port == expected.port &&
        uri.path == expected.path &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static Uri? _tryParseUri(String value) {
    try {
      return Uri.tryParse(value);
    } on FormatException {
      return null;
    }
  }

  @visibleForTesting
  static bool isExpectedRedirectUri(Uri uri) =>
      uri.toString() == AppConstants.oauthRedirectUri;

  /// Refreshes the OAuth session using the stored refresh token.
  static Future<TokenResponse?> refresh({
    required String clientId,
    required String redirectUri,
    required String tokenEndpoint,
    required String refreshToken,
    required List<String> scopes,
  }) async {
    _logger.info('Refreshing OAuth session on Windows');

    final parsedTokenEndpoint = _tryParseUri(tokenEndpoint);
    if (parsedTokenEndpoint == null ||
        !isTrustedTokenEndpoint(parsedTokenEndpoint)) {
      throw AuthException(
        message: 'Invalid OAuth token endpoint',
        code: 'INVALID_OAUTH_TOKEN_ENDPOINT',
      );
    }

    final response = await http.post(
      parsedTokenEndpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': refreshToken,
        'scope': scopes.join(' '),
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      _logger.info('OAuth session refresh successful');

      return TokenResponse(
        data['access_token'],
        data['refresh_token'] ?? refreshToken,
        _expirationFromSeconds(data['expires_in']),
        data['id_token'],
        'Bearer',
        scopes,
        data,
      );
    }

    // Never persist the token endpoint's response body.
    _logger.severe(
      'OAuth session refresh failed with HTTP ${response.statusCode}',
    );

    final oauthError = _oauthErrorFromBody(response.body);
    final errorCode = switch (oauthError) {
      'invalid_grant' => 'INVALID_GRANT',
      'invalid_token' => 'INVALID_TOKEN',
      _ => 'TOKEN_REFRESH_FAILED',
    };

    throw ApiException(
      message: 'Token refresh failed',
      statusCode: response.statusCode,
      code: errorCode,
    );
  }

  static String? _oauthErrorFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        return error is String ? error : null;
      }
    } on FormatException {
      return null;
    }

    return null;
  }

  @visibleForTesting
  static String refreshErrorCodeForTesting(String body) {
    return switch (_oauthErrorFromBody(body)) {
      'invalid_grant' => 'INVALID_GRANT',
      'invalid_token' => 'INVALID_TOKEN',
      _ => 'TOKEN_REFRESH_FAILED',
    };
  }

  static DateTime? _expirationFromSeconds(Object? expiresIn) {
    if (expiresIn is! num) {
      return null;
    }

    return DateTime.now().add(Duration(seconds: expiresIn.toInt()));
  }

  static String _generateRandomString(int length) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

    final random = Random.secure();

    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static String _generateCodeVerifier() {
    return _generateRandomString(128);
  }

  static String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);

    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}
