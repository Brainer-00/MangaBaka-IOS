import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/auth/auth_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthStorage storage;

  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());

    // Force FlutterSecureStorage to fail with a PlatformException so the
    // SharedPreferences fallback path is exercised.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async {
            throw PlatformException(code: 'no-secure-storage');
          },
        );

    SharedPreferences.setMockInitialValues({});

    storage = AuthStorage(
      allowInsecureFallbackForTesting: true,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  group('AuthStorage (fallback path)', () {
    test('deleteAll preserves unrelated SharedPreferences values', () async {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('unrelated_setting', 'keep-me');
      await storage.write(AuthStorage.kAccessToken, 'token');

      await storage.deleteAll();

      expect(await storage.read(AuthStorage.kAccessToken), isNull);
      expect(prefs.getString('unrelated_setting'), 'keep-me');
    });

    test('write + read round-trip via SharedPreferences', () async {
      await storage.write(AuthStorage.kAccessToken, 'tok-123');

      expect(
        await storage.read(AuthStorage.kAccessToken),
        'tok-123',
      );
    });

    test('read returns null for unknown key', () async {
      expect(await storage.read('unknown-key'), isNull);
    });

    test('write(null) removes the value', () async {
      await storage.write(AuthStorage.kAccessToken, 'tok');
      await storage.write(AuthStorage.kAccessToken, null);

      expect(await storage.read(AuthStorage.kAccessToken), isNull);
    });

    test('delete removes a specific key but leaves others', () async {
      await storage.write(AuthStorage.kAccessToken, 'a');
      await storage.write(AuthStorage.kRefreshToken, 'b');

      await storage.delete(AuthStorage.kAccessToken);

      expect(await storage.read(AuthStorage.kAccessToken), isNull);
      expect(await storage.read(AuthStorage.kRefreshToken), 'b');
    });

    test('deleteAll clears every auth key', () async {
      await storage.write(AuthStorage.kAccessToken, 'a');
      await storage.write(AuthStorage.kRefreshToken, 'b');

      await storage.deleteAll();

      expect(await storage.read(AuthStorage.kAccessToken), isNull);
      expect(await storage.read(AuthStorage.kRefreshToken), isNull);
    });

    test('cacheProfile stores JSON and getCachedProfile decodes it', () async {
      final profile = MbProfile(
        id: 'user-1',
        role: 'user',
        scopes: ['openid', 'profile'],
        nickname: 'Test',
      );

      await storage.cacheProfile(profile);

      final raw = await storage.read(AuthStorage.kProfileCache);

      expect(raw, isNotNull);
      expect(jsonDecode(raw!)['id'], 'user-1');

      final cached = await storage.getCachedProfile();

      expect(cached, isNotNull);
      expect(cached!.id, 'user-1');
      expect(cached.role, 'user');
      expect(cached.scopes, ['openid', 'profile']);
      expect(cached.nickname, 'Test');
    });

    test('getCachedProfile returns null when nothing is cached', () async {
      expect(await storage.getCachedProfile(), isNull);
    });

    test('getCachedProfile returns null on malformed cache', () async {
      await storage.write(
        AuthStorage.kProfileCache,
        'not-json',
      );

      expect(await storage.getCachedProfile(), isNull);
    });
  });

  test(
    'secure storage failure does not fall back when fallback is disabled',
    () async {
      final secureOnlyStorage = AuthStorage();

      await expectLater(
        secureOnlyStorage.write(
          AuthStorage.kAccessToken,
          'secret-token',
        ),
        throwsA(isA<PlatformException>()),
      );

      final prefs = await SharedPreferences.getInstance();

      expect(
        prefs.getString(AuthStorage.kAccessToken),
        isNull,
      );
    },
  );
}