import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_keys.dart';
import 'package:mangabaka_app/features/profile/services/auth/auth_storage.dart';
import 'package:mangabaka_app/features/profile/services/auth/installation_session_guard.dart';

class _RecordingAuthStorage extends Fake implements AuthStorage {
  _RecordingAuthStorage(this.events, {this.failure});

  final List<String> events;
  final Object? failure;
  bool hasAuth = true;

  @override
  Future<void> clearAuthenticationData() async {
    events.add('clear');
    if (failure case final failure?) throw failure;
    hasAuth = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(resetServiceLocator);

  test('fresh iOS install clears auth before restoring the session', () async {
    final events = <String>[];
    final storage = _RecordingAuthStorage(events);
    var restoredStaleAuth = false;
    final guard = InstallationSessionGuard(isIOS: true, authStorage: storage);

    final restored = await guard.restoreSessionIfSafe(() async {
      events.add('restore');
      restoredStaleAuth = storage.hasAuth;
    });

    final preferences = await SharedPreferences.getInstance();
    expect(restored, isTrue);
    expect(events, ['clear', 'restore']);
    expect(restoredStaleAuth, isFalse);
    expect(
      preferences.getBool(InstallationSessionGuard.installationSentinelKey),
      isTrue,
    );
  });

  test(
    'pre-sentinel upgrade migrates legacy state without clearing auth',
    () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.onboardingCompleted: true,
      });
      final events = <String>[];
      final storage = _RecordingAuthStorage(events);
      var restoredExistingAuth = false;
      final guard = InstallationSessionGuard(isIOS: true, authStorage: storage);

      final restored = await guard.restoreSessionIfSafe(() async {
        events.add('restore');
        restoredExistingAuth = storage.hasAuth;
      });

      final preferences = await SharedPreferences.getInstance();
      expect(restored, isTrue);
      expect(events, ['restore']);
      expect(restoredExistingAuth, isTrue);
      expect(
        preferences.getBool(InstallationSessionGuard.installationSentinelKey),
        isTrue,
      );
    },
  );

  test(
    'valid legacy library sync also proves a pre-sentinel install',
    () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.lastSyncKey: '2026-09-26T12:00:00.000Z',
      });
      final events = <String>[];
      final guard = InstallationSessionGuard(
        isIOS: true,
        authStorage: _RecordingAuthStorage(events),
      );

      final restored = await guard.restoreSessionIfSafe(() async {
        events.add('restore');
      });

      expect(restored, isTrue);
      expect(events, ['restore']);
    },
  );

  test('subsequent iOS launch preserves an existing session', () async {
    SharedPreferences.setMockInitialValues({
      InstallationSessionGuard.installationSentinelKey: true,
    });
    final events = <String>[];
    final guard = InstallationSessionGuard(
      isIOS: true,
      authStorage: _RecordingAuthStorage(events),
    );

    final restored = await guard.restoreSessionIfSafe(() async {
      events.add('restore');
    });

    expect(restored, isTrue);
    expect(events, ['restore']);
  });

  test(
    'sentinel takes precedence without consulting legacy evidence',
    () async {
      SharedPreferences.setMockInitialValues({
        InstallationSessionGuard.installationSentinelKey: true,
        SettingsKeys.onboardingCompleted: false,
        AppConstants.lastSyncKey: 'not-a-date',
      });
      final events = <String>[];
      final guard = InstallationSessionGuard(
        isIOS: true,
        authStorage: _RecordingAuthStorage(events),
      );

      await guard.restoreSessionIfSafe(() async {
        events.add('restore');
      });

      expect(events, ['restore']);
    },
  );

  test(
    'arbitrary preference keys are not legacy installation evidence',
    () async {
      SharedPreferences.setMockInitialValues({
        'mangabaka_app_unknown_future_key': true,
        'third_party_plugin_default': 'value',
        AppConstants.lastSyncKey: 'invalid',
      });
      final events = <String>[];
      final storage = _RecordingAuthStorage(events);
      final guard = InstallationSessionGuard(isIOS: true, authStorage: storage);

      await guard.restoreSessionIfSafe(() async {
        events.add('restore');
      });

      expect(events, ['clear', 'restore']);
      expect(storage.hasAuth, isFalse);
    },
  );

  test('uninstall and reinstall clears retained Keychain auth', () async {
    final events = <String>[];
    final storage = _RecordingAuthStorage(events);
    final guard = InstallationSessionGuard(isIOS: true, authStorage: storage);

    await guard.restoreSessionIfSafe(() async {
      events.add('restore');
    });

    expect(events, ['clear', 'restore']);
    expect(storage.hasAuth, isFalse);
  });

  test('non-iOS launch does not inspect install state or clear auth', () async {
    final events = <String>[];
    final guard = InstallationSessionGuard(
      isIOS: false,
      authStorage: _RecordingAuthStorage(events),
      loadPreferences: () async {
        events.add('preferences');
        return SharedPreferences.getInstance();
      },
    );

    final restored = await guard.restoreSessionIfSafe(() async {
      events.add('restore');
    });

    expect(restored, isTrue);
    expect(events, ['restore']);
  });

  test(
    'failed fresh-install cleanup blocks stale session restoration',
    () async {
      final events = <String>[];
      final guard = InstallationSessionGuard(
        isIOS: true,
        authStorage: _RecordingAuthStorage(
          events,
          failure: StateError('cleanup failed'),
        ),
      );

      final restored = await guard.restoreSessionIfSafe(() async {
        events.add('restore');
      });

      final preferences = await SharedPreferences.getInstance();
      expect(restored, isFalse);
      expect(events, ['clear']);
      expect(
        preferences.getBool(InstallationSessionGuard.installationSentinelKey),
        isNull,
      );
    },
  );
}
