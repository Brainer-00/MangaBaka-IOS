import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/auth/auth_network_client.dart';
import 'package:mangabaka_app/features/profile/services/auth/auth_storage.dart';
import 'package:mangabaka_app/features/profile/services/auth/windows_auth_handler.dart';

class ProfileAuthService extends ChangeNotifier {
  final _logger = LoggingService.logger;

  static const _authorizationEndpoint =
      '${AppConstants.authBaseUrl}/authorize';
  static const _tokenEndpoint = '${AppConstants.authBaseUrl}/token';
  static const _endSessionEndpoint =
      '${AppConstants.authBaseUrl}/end-session';

  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final AuthStorage _storage = AuthStorage();
  final AuthNetworkClient _network = AuthNetworkClient();

  MbProfile? _cachedProfile;
  bool _hasSessionCache = false;

  /// True while a desktop sign-in is waiting on the user in their browser.
  ///
  /// Drives the "check your browser" prompt. Only the Windows flow can be
  /// stranded this way; on mobile the system's auth sheet reports its own
  /// dismissal.
  final ValueNotifier<bool> awaitingBrowser = ValueNotifier(false);

  void cancelLogin() => WindowsAuthHandler.cancelPending();

  Future<void> reopenBrowser() => WindowsAuthHandler.reopenBrowser();

  bool get isLoggedIn => _hasSessionCache;

  MbProfile? get cachedProfile => _cachedProfile;

  String get _clientId =>
      dotenv.env['MANGABAKA_APP_CLIENT_ID'] ?? '';

  String get _redirectUri =>
      dotenv.env['MANGABAKA_APP_REDIRECT_URI'] ?? '';

  AuthorizationServiceConfiguration get _serviceConfig =>
      const AuthorizationServiceConfiguration(
        authorizationEndpoint: _authorizationEndpoint,
        tokenEndpoint: _tokenEndpoint,
        endSessionEndpoint: _endSessionEndpoint,
      );

  Future<void> init() async {
    _logger.info('Initializing ProfileAuthService...');

    try {
      _hasSessionCache = await hasSession();

      if (_hasSessionCache) {
        _logger.info('Found active session in storage');

        _cachedProfile = await _storage.getCachedProfile();

        if (_cachedProfile != null) {
          _logger.fine('Loaded cached profile');
        }

        // Refresh profile in the background so avatar and details stay current.
        fetchProfile(forceRefresh: true).then(
          (_) {},
          onError: (e) {
            _logger.fine(
              'Background profile refresh on init failed '
              '(${e.runtimeType})',
            );
          },
        );
      } else {
        _logger.fine('No active session found');
      }
    } catch (e) {
      _logger.warning(
        'Failed to load cached profile during init '
        '(${e.runtimeType})',
      );
    }
  }

  Future<bool> hasSession() async {
    final token = await _storage.read(
      AuthStorage.kAccessToken,
    );

    return token != null && token.isNotEmpty;
  }

  Future<void> login() async {
    _logger.info('Starting OAuth2 login flow...');

    try {
      if (_clientId.isEmpty || _redirectUri.isEmpty) {
        _logger.severe(
          'OAuth configuration missing from .env',
        );

        throw AuthException(
          message:
              'Missing MANGABAKA_APP_CLIENT_ID or '
              'MANGABAKA_APP_REDIRECT_URI in .env',
          code: 'MISSING_CONFIG',
        );
      }

      TokenResponse? response;

      if (Platform.isWindows) {
        response =
            await WindowsAuthHandler.authorizeAndExchangeCode(
          clientId: _clientId,
          redirectUri: _redirectUri,
          authorizationEndpoint: _authorizationEndpoint,
          tokenEndpoint: _tokenEndpoint,
          scopes: AppConstants.oauthScopes,
          onBrowserOpened: () {
            awaitingBrowser.value = true;
          },
        );
      } else {
        response = await _appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            _clientId,
            _redirectUri,
            serviceConfiguration: _serviceConfig,
            scopes: AppConstants.oauthScopes,
            promptValues: const ['consent'],
          ),
        );
      }

      if (response == null) {
        throw AuthException(
          message: 'Login failed: No response from auth server',
          code: 'EMPTY_AUTH_RESPONSE',
        );
      }

      _logger.info(
        'OAuth2 authorization successful. Persisting tokens...',
      );

      await _persistTokens(response);

      _hasSessionCache = true;

      await fetchProfile(
        forceRefresh: true,
      );

      _logger.info('Login complete');

      notifyListeners();
    } catch (e) {
      if (e is AuthCancelledException) {
        _logger.info('Login cancelled by user');
        rethrow;
      }

      if (e is PlatformException &&
          (e.code == 'authorize_and_exchange_code_failed' ||
              e.code == 'user_cancelled')) {
        final msg = e.message?.toLowerCase() ?? '';

        if (msg.contains('cancelled') ||
            msg.contains('canceled') ||
            msg.contains('user')) {
          _logger.info('Login cancelled by user');
          throw AuthCancelledException();
        }
      }

      _logger.severe(
        'Login flow failed (${e.runtimeType})',
      );

      if (e is AppException) {
        rethrow;
      }

      throw AuthException(
        message: 'Login failed',
        code: 'LOGIN_FAILED',
      );
    } finally {
      awaitingBrowser.value = false;
    }
  }

  Future<void> _persistTokens(
    TokenResponse response,
  ) async {
    try {
      await _storage.write(
        AuthStorage.kAccessToken,
        response.accessToken,
      );

      await _storage.write(
        AuthStorage.kRefreshToken,
        response.refreshToken,
      );

      await _storage.write(
        AuthStorage.kIdToken,
        response.idToken,
      );

      final exp = response.accessTokenExpirationDateTime
          ?.toUtc()
          .toIso8601String();

      if (exp != null) {
        _logger.fine(
          'Access token expiration stored',
        );

        await _storage.write(
          AuthStorage.kAccessTokenExp,
          exp,
        );
      }
    } catch (e) {
      _logger.severe(
        'Failed to persist tokens (${e.runtimeType})',
      );

      throw AuthException(
        message: 'Failed to persist tokens',
        code: 'TOKEN_PERSIST_FAILED',
      );
    }
  }

  /// Guards against concurrent refreshes. With rotating refresh tokens, two
  /// parallel refreshes would race: the first invalidates the token the second
  /// is still using, permanently breaking the session. Callers share one
  /// in-flight refresh instead.
  Future<void>? _refreshInFlight;

  Future<void> _refreshIfNeeded() {
    return _refreshInFlight ??=
        _runRefresh().whenComplete(
      () => _refreshInFlight = null,
    );
  }

  Future<void> _runRefresh() async {
    final expRaw = await _storage.read(
      AuthStorage.kAccessTokenExp,
    );

    if (expRaw == null) {
      _logger.fine(
        'No token expiration found, assuming refresh not needed',
      );
      return;
    }

    final exp = DateTime.tryParse(expRaw);

    if (exp == null) {
      return;
    }

    final now = DateTime.now().toUtc();

    final threshold = exp.subtract(
      const Duration(minutes: 5),
    );

    if (now.isBefore(threshold)) {
      _logger.fine('Access token still valid');
      return;
    }

    _logger.info(
      'Access token expiring soon or already expired. '
      'Attempting refresh...',
    );

    final refreshToken = await _storage.read(
      AuthStorage.kRefreshToken,
    );

    if (refreshToken == null || refreshToken.isEmpty) {
      _logger.warning(
        'No refresh token available to perform refresh',
      );

      await _clearSession();

      throw SessionExpiredException();
    }

    TokenResponse? response;

    try {
      if (Platform.isWindows) {
        response = await WindowsAuthHandler.refresh(
          clientId: _clientId,
          redirectUri: _redirectUri,
          tokenEndpoint: _tokenEndpoint,
          refreshToken: refreshToken,
          scopes: AppConstants.oauthScopes,
        );
      } else {
        response = await _appAuth.token(
          TokenRequest(
            _clientId,
            _redirectUri,
            serviceConfiguration: _serviceConfig,
            refreshToken: refreshToken,
            scopes: AppConstants.oauthScopes,
          ),
        );
      }
    } catch (e) {
      _logger.severe(
        'Token refresh failed (${e.runtimeType})',
      );

      // An invalid_grant (HTTP 400/401) means the refresh token is dead and no
      // amount of retrying will help. Clear the session and force re-login.
      if (_isInvalidGrant(e)) {
        await _clearSession();
        throw SessionExpiredException();
      }

      throw AuthException(
        message: 'Failed to refresh tokens',
        code: 'TOKEN_REFRESH_FAILED',
      );
    }

    if (response == null) {
      throw AuthException(
        message:
            'Token refresh failed: No response from auth server',
        code: 'EMPTY_REFRESH_RESPONSE',
      );
    }

    _logger.info('Token refresh successful');

    await _persistTokens(response);
  }

  /// Detects an unrecoverable `invalid_grant` from either the Windows handler
  /// (typed [ApiException]) or flutter_appauth (a [PlatformException] whose
  /// payload carries the OAuth error).
  bool _isInvalidGrant(Object e) {
    if (e is ApiException) {
      return e.statusCode == 400 ||
          e.statusCode == 401;
    }

    if (e is PlatformException) {
      final blob =
          '${e.code} ${e.message ?? ''} ${e.details ?? ''}'
              .toLowerCase();

      return blob.contains('invalid_grant') ||
          blob.contains('invalid_token') ||
          blob.contains(' 400') ||
          blob.contains(' 401');
    }

    return false;
  }

  /// Drops the local credentials and flips state to logged-out so the UI can
  /// route the user back to login. Library data is left intact because it is
  /// server-backed and re-syncs on the next login. Explicit [logout] also
  /// clears the local library.
  Future<void> _clearSession() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      _logger.warning(
        'Failed to clear storage during session expiry '
        '(${e.runtimeType})',
      );
    }

    _cachedProfile = null;
    _hasSessionCache = false;

    notifyListeners();
  }

  Future<MbProfile> fetchProfile({
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _cachedProfile != null) {
        return _cachedProfile!;
      }

      await _refreshIfNeeded();

      final accessToken = await _storage.read(
        AuthStorage.kAccessToken,
      );

      if (accessToken == null ||
          accessToken.isEmpty) {
        throw AuthException(
          message: 'Not logged in',
          code: 'NOT_LOGGED_IN',
        );
      }

      _cachedProfile =
          await _network.fetchProfile(accessToken);

      await _storage.cacheProfile(
        _cachedProfile!,
      );

      notifyListeners();

      return _cachedProfile!;
    } catch (e) {
      _logger.severe(
        'Failed to fetch profile (${e.runtimeType})',
      );

      if (e is AppException) {
        rethrow;
      }

      throw AuthException(
        message: 'Failed to fetch profile',
        code: 'PROFILE_FETCH_FAILED',
      );
    }
  }

  Future<String> getValidAccessToken() async {
    try {
      await _refreshIfNeeded();

      final token = await _storage.read(
        AuthStorage.kAccessToken,
      );

      if (token == null || token.isEmpty) {
        throw AuthException(
          message: 'Not logged in',
          code: 'NOT_LOGGED_IN',
        );
      }

      return token;
    } catch (e) {
      _logger.severe(
        'Failed to get valid access token '
        '(${e.runtimeType})',
      );

      if (e is AppException) {
        rethrow;
      }

      throw AuthException(
        message: 'Failed to get valid access token',
        code: 'ACCESS_TOKEN_FAILED',
      );
    }
  }

  Future<void> logout() async {
    try {
      await _storage.deleteAll();

      _cachedProfile = null;
      _hasSessionCache = false;

      try {
        await getIt<LibraryService>()
            .clearLibrary();
      } catch (e) {
        _logger.warning(
          'Failed to clear library on logout '
          '(${e.runtimeType})',
        );
      }

      notifyListeners();
    } catch (e) {
      _logger.severe(
        'Failed to logout (${e.runtimeType})',
      );

      throw AuthException(
        message: 'Failed to logout',
        code: 'LOGOUT_FAILED',
      );
    }
  }
}