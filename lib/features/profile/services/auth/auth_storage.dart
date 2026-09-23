import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';

class AuthStorage {
  AuthStorage({this.allowInsecureFallbackForTesting = false});

  final bool allowInsecureFallbackForTesting;

  bool get _allowInsecureFallback => allowInsecureFallbackForTesting;

  static const kAccessToken = 'mb_access_token';
  static const kRefreshToken = 'mb_refresh_token';
  static const kIdToken = 'mb_id_token';
  static const kAccessTokenExp = 'mb_access_token_exp';
  static const kProfileCache = 'mb_profile_cache';

  final _logger = LoggingService.logger;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: false,
      resetOnError: true,
      sharedPreferencesName: 'mangabaka_app_secure_storage_v3',
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
      synchronizable: false,
    ),
  );

  Future<String?> read(String key) async {
    try {
      final value = await _storage.read(key: key);

      if (value != null || !_allowInsecureFallback) {
        return value;
      }

      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } on PlatformException catch (e) {
      if (!_allowInsecureFallback) {
        _logger.severe(
          'Secure storage read failed (${e.runtimeType})',
        );
        rethrow;
      }

      _logger.warning(
        'Secure storage read error (${e.runtimeType}); '
        'checking fallback',
      );

      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  Future<void> write(String key, String? value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      if (!_allowInsecureFallback) {
        _logger.severe(
          'Secure storage write failed (${e.runtimeType})',
        );
        rethrow;
      }

      _logger.warning(
        'Secure storage write error (${e.runtimeType}); '
        'falling back to SharedPreferences',
      );

      final prefs = await SharedPreferences.getInstance();

      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (e) {
      if (!_allowInsecureFallback) {
        _logger.severe(
          'Secure storage delete failed (${e.runtimeType})',
        );
        rethrow;
      }

      _logger.warning(
        'Secure storage delete error (${e.runtimeType}); '
        'removing fallback value',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    }
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } on PlatformException catch (e) {
      if (!_allowInsecureFallback) {
        _logger.severe('Secure storage clear failed (${e.runtimeType})');
        rethrow;
      }

      _logger.warning(
        'Secure storage clear error (${e.runtimeType}); removing fallback values',
      );
    }

    if (_allowInsecureFallback) {
      final prefs = await SharedPreferences.getInstance();

      for (final key in [
        kAccessToken,
        kRefreshToken,
        kIdToken,
        kAccessTokenExp,
        kProfileCache,
      ]) {
        await prefs.remove(key);
      }
    }
  }

  Future<MbProfile?> getCachedProfile() async {
    try {
      final cachedString = await read(kProfileCache);

      if (cachedString != null) {
        return MbProfile.fromJson(jsonDecode(cachedString));
      }
    } catch (e) {
      _logger.warning('Failed to load cached profile (${e.runtimeType})');
    }

    return null;
  }

  Future<void> cacheProfile(MbProfile profile) async {
    await write(kProfileCache, jsonEncode(profile.toJson()));
  }
}
