import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/theme/ios_home_icon.dart';
import 'package:mangabaka_app/core/theme/ios_icon_variants.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('eirenyu/home_icon');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('all thirteen swatches map in order and Crimson Moon is primary', () {
    expect(iosIconVariants.length, 13);
    for (var i = 0; i < 13; i++) {
      expect(iosIconVariants[i].$1, ThemePresets.accentSwatches[i].toARGB32());
    }
    expect(iosIconVariants.where((entry) => entry.$2 == null).length, 1);
    expect(iosIconForColor(0xFFA82F4F), isNull);
    expect(iosIconForColor(0xFF123456), isNull);
    expect(iosIconForColor(0xFF4CC9FF), 'IconHorizonBlue');
  });

  test(
    'rapid changes finish at latest icon and avoid redundant sets',
    () async {
      final settings = SettingsManager();
      final theme = ThemeController()..init();
      final calls = <String?>[];
      String? actual;
      final firstChange = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'supported':
                return true;
              case 'current':
                return actual;
              case 'set':
                calls.add(call.arguments as String?);
                if (calls.length == 1) await firstChange.future;
                actual = call.arguments as String?;
                return null;
            }
            throw StateError(call.method);
          });
      final coordinator = IosHomeIcon(theme, channel: channel)..start();
      await settings.setMatchLogoToAccent(false);
      await settings.setManualLogoColor(0xFF22D3EE);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['IconCyan']);
      await settings.setManualLogoColor(0xFF4CC9FF);
      await settings.setManualLogoColor(0xFF8B7CF6);
      firstChange.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, ['IconCyan', 'IconTwilightLavender']);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, 2);
      coordinator.dispose();
      theme.dispose();
    },
  );

  test(
    'unsupported platform and channel error leave preferences intact',
    () async {
      final settings = SettingsManager();
      final theme = ThemeController()..init();
      var setCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'supported') return false;
            setCalls++;
            return null;
          });
      final coordinator = IosHomeIcon(theme, channel: channel)..start();
      await settings.setMatchLogoToAccent(false);
      await settings.setManualLogoColor(0xFF4CC9FF);
      await Future<void>.delayed(Duration.zero);
      expect(setCalls, 0);
      expect(settings.manualLogoColor, 0xFF4CC9FF);
      coordinator.dispose();
      theme.dispose();
    },
  );

  test(
    'custom accent retains exact in-app color and uses primary icon',
    () async {
      final settings = SettingsManager();
      final theme = ThemeController()..init();
      await settings.setAccentOverride(0xFF123456);
      expect(theme.currentLogoColor.toARGB32(), 0xFF123456);
      expect(iosIconForColor(theme.currentLogoColor.toARGB32()), isNull);
      await settings.setAccentOverride(0xFF22D3EE);
      expect(iosIconForColor(theme.currentLogoColor.toARGB32()), 'IconCyan');
      await settings.setThemeMode(AppThemeMode.light);
      expect(iosIconForColor(theme.currentLogoColor.toARGB32()), 'IconCyan');
      await settings.setAccentOverride(null);
      expect(iosIconForColor(theme.currentLogoColor.toARGB32()), isNull);
      theme.dispose();
    },
  );

  test(
    'stale native current after success does not repeat confirmation',
    () async {
      final settings = SettingsManager();
      final theme = ThemeController()..init();
      final requests = <String?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'supported':
                return true;
              case 'current':
                return null; // UIKit has not published its new value yet.
              case 'set':
                requests.add(call.arguments as String?);
                return null;
            }
            throw StateError(call.method);
          });
      final coordinator = IosHomeIcon(theme, channel: channel)..start();
      await settings.setMatchLogoToAccent(false);
      await settings.setManualLogoColor(0xFF22D3EE);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, ['IconCyan']);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(requests, ['IconCyan']);
      await settings.setManualLogoColor(0xFF4CC9FF);
      await Future<void>.delayed(Duration.zero);
      expect(requests, ['IconCyan', 'IconHorizonBlue']);
      coordinator.dispose();
      theme.dispose();
    },
  );
}
