import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_keys.dart';
import 'package:mangabaka_app/features/profile/services/auth/auth_storage.dart';

typedef PreferencesLoader = Future<SharedPreferences> Function();

/// Prevents iOS Keychain credentials from being restored after an uninstall.
///
/// iOS may retain Keychain values when an app is deleted, while the app's
/// SharedPreferences are removed. A dedicated preference therefore marks the
/// current installation without coupling session behavior to onboarding or
/// any other user setting after migration.
///
/// Builds predating the sentinel need a one-time migration path: an exact,
/// validated allowlist of MangaBaka-owned legacy preferences distinguishes an
/// upgrade from a reinstall. Arbitrary preference keys and prefix matches are
/// deliberately not accepted. Once written, the sentinel is the only signal
/// consulted on future launches.
class InstallationSessionGuard {
  InstallationSessionGuard({
    bool? isIOS,
    AuthStorage? authStorage,
    PreferencesLoader? loadPreferences,
  }) : _isIOS = isIOS ?? Platform.isIOS,
       _authStorage = authStorage ?? AuthStorage(),
       _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const installationSentinelKey =
      '${AppConstants.prefixStorageKey}installation_session_sentinel_v1';

  final bool _isIOS;
  final AuthStorage _authStorage;
  final PreferencesLoader _loadPreferences;
  final _logger = LoggingService.logger;

  /// Restores the session only when doing so is safe for this installation.
  ///
  /// Returns false when fresh-install cleanup or sentinel persistence fails.
  /// The caller must then leave the in-memory auth state logged out. Because
  /// the sentinel remains absent, the cleanup is retried on the next launch.
  Future<bool> restoreSessionIfSafe(
    Future<void> Function() restoreSession,
  ) async {
    if (_isIOS && !await _prepareIOSInstallation()) {
      return false;
    }

    await restoreSession();
    return true;
  }

  Future<bool> _prepareIOSInstallation() async {
    try {
      final preferences = await _loadPreferences();
      if (preferences.getBool(installationSentinelKey) == true) {
        return true;
      }

      if (_hasLegacyInstallationEvidence(preferences)) {
        _logger.info(
          'Pre-sentinel iOS installation detected; migrating install state',
        );
        return await _persistSentinel(preferences);
      }

      _logger.info(
        'Fresh iOS installation detected; clearing retained auth data',
      );
      await _authStorage.clearAuthenticationData();
      return await _persistSentinel(preferences);
    } catch (error) {
      _logger.severe(
        'Installation session preparation failed (${error.runtimeType}); '
        'session restoration blocked',
      );
      return false;
    }
  }

  bool _hasLegacyInstallationEvidence(SharedPreferences preferences) {
    if (preferences.getBool(SettingsKeys.onboardingCompleted) == true) {
      return true;
    }

    final lastSync = preferences.getString(AppConstants.lastSyncKey);
    return lastSync != null &&
        lastSync.isNotEmpty &&
        DateTime.tryParse(lastSync) != null;
  }

  Future<bool> _persistSentinel(SharedPreferences preferences) async {
    final saved = await preferences.setBool(installationSentinelKey, true);
    if (!saved) {
      throw StateError('Installation sentinel was not persisted');
    }
    return true;
  }
}
