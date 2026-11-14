import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_keys.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SettingsManager.resetForTesting());

  test('defaults to EirenYu dark and supports both brightness slots', () async {
    SharedPreferences.setMockInitialValues({});
    await SettingsManager().init();
    final controller = ThemeController()..init();
    addTearDown(controller.dispose);
    expect(controller.mode, AppThemeMode.dark);
    expect(controller.current, EirenYuPalette.dark);
    expect(controller.lightPalette, EirenYuPalette.light);
    await controller.setMode(AppThemeMode.light);
    expect(controller.current, EirenYuPalette.light);
  });

  test('system mode follows the platform brightness', () async {
    SharedPreferences.setMockInitialValues({});
    await SettingsManager().init();
    final controller = ThemeController()..init();
    addTearDown(controller.dispose);
    final binding = TestWidgetsFlutterBinding.instance;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);

    await controller.setMode(AppThemeMode.system);
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    expect(controller.current, EirenYuPalette.light);
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(controller.current, EirenYuPalette.dark);
  });

  test(
    'invalid mode and unsupported preset variant fall back safely',
    () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.themeMode: 'invalid',
        SettingsKeys.darkThemeId: 'retired',
        SettingsKeys.lightThemeId: 'amoled',
      });
      await SettingsManager().init();
      final controller = ThemeController()..init();
      addTearDown(controller.dispose);
      expect(controller.mode, AppThemeMode.dark);
      expect(controller.darkPalette, EirenYuPalette.dark);
      expect(controller.lightPalette, EirenYuPalette.light);
    },
  );

  test('malformed persisted values and legacy accent are safe', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.themeMode: 99,
      SettingsKeys.darkThemeId: false,
      SettingsKeys.accentOverride: 'bad',
      SettingsKeys.legacyAccentTheme: 2,
    });
    await SettingsManager().init();
    final controller = ThemeController()..init();
    addTearDown(controller.dispose);
    expect(controller.mode, AppThemeMode.dark);
    expect(controller.darkPalette, EirenYuPalette.dark);
    expect(SettingsManager().accentOverride, isNull);
  });

  test('legacy accent selection survives when no v2 override exists', () async {
    SharedPreferences.setMockInitialValues({SettingsKeys.legacyAccentTheme: 1});
    await SettingsManager().init();
    final controller = ThemeController()..init();
    addTearDown(controller.dispose);
    expect(controller.darkPalette.accent, EirenYuPalette.twilightLavender);
  });

  test('override is independent of preset and unrelated settings', () async {
    SharedPreferences.setMockInitialValues({});
    await SettingsManager().init();
    final controller = ThemeController()..init();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    await SettingsManager().setShowTooltips(false);
    expect(notifications, 0);
    await controller.select('nord', Brightness.dark);
    await controller.setAccentOverride(const Color(0xFF4CC9FF));
    expect(controller.darkPalette.accent, EirenYuPalette.horizonBlue);
    // Horizon Blue is legible on Nord's dark surface but too light for the
    // EirenYu light surface, so the light slot receives a darker foreground.
    expect(controller.lightPalette.accent, isNot(EirenYuPalette.horizonBlue));
    expect(
      MbPalette.contrastRatio(
        controller.lightPalette.accent,
        controller.lightPalette.surface,
      ),
      greaterThanOrEqualTo(3.0),
    );
    await controller.setAccentOverride(null);
    expect(
      controller.darkPalette.accent,
      ThemePresets.byId('nord')!.dark!.accent,
    );
  });

  test('invalid selections are normalised before persistence', () async {
    SharedPreferences.setMockInitialValues({});
    await SettingsManager().init();
    final controller = ThemeController()..init();
    addTearDown(controller.dispose);

    await controller.select('retired', Brightness.dark);
    await controller.select('amoled', Brightness.light);

    expect(SettingsManager().darkThemeId, ThemePresets.defaultId);
    expect(SettingsManager().lightThemeId, ThemePresets.defaultId);
  });

  test('presets expose only their supported variants', () {
    expect(ThemePresets.all.length, 15);
    expect(ThemePresets.byId('amoled')!.light, isNull);
    expect(ThemePresets.byId('dracula')!.light, isNull);
    expect(ThemePresets.byId('nord')!.light, isNotNull);
    expect(
      MbPalette.readableOn(EirenYuPalette.horizonBlue),
      const Color(0xFF000000),
    );
    expect(
      MbPalette.readableOn(EirenYuPalette.crimsonMoon),
      const Color(0xFFFFFFFF),
    );
    expect(
      MbPalette.readableOn(const Color(0xFF808080)),
      const Color(0xFF000000),
    );
  });

  test('accent overrides meet both ink and surface contrast floors', () {
    final custom = EirenYuPalette.dark.withAccent(const Color(0xFF1B203A));
    expect(custom.accent, isNot(const Color(0xFF1B203A)));
    expect(
      MbPalette.contrastRatio(custom.accent, custom.surface),
      greaterThanOrEqualTo(3.0),
    );
    expect(
      MbPalette.contrastRatio(custom.onAccent, custom.accent),
      greaterThanOrEqualTo(4.5),
    );

    final gray = EirenYuPalette.light.withAccent(const Color(0xFF808080));
    expect(gray.accent, const Color(0xFF808080));
    expect(gray.onAccent, const Color(0xFF000000));
    expect(
      MbPalette.contrastRatio(gray.onAccent, gray.accent),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('palette and ThemeExtension interpolate every semantic color', () {
    final palette = MbPalette.lerp(
      EirenYuPalette.dark,
      EirenYuPalette.light,
      0.25,
    );
    expect(
      palette.background,
      Color.lerp(
        EirenYuPalette.dark.background,
        EirenYuPalette.light.background,
        0.25,
      ),
    );
    expect(
      palette.info,
      Color.lerp(EirenYuPalette.dark.info, EirenYuPalette.light.info, 0.25),
    );
    expect(palette.brightness, Brightness.dark);

    final extension = MbColors(
      EirenYuPalette.dark,
    ).lerp(const MbColors(EirenYuPalette.light), 0.75);
    expect(
      extension.palette.accent,
      Color.lerp(EirenYuPalette.dark.accent, EirenYuPalette.light.accent, 0.75),
    );
    expect(extension.palette.brightness, Brightness.light);
  });

  test('built-in palette text and accent ink meet contrast floors', () {
    for (final preset in ThemePresets.all) {
      for (final palette in [preset.dark, preset.light]) {
        if (palette == null) continue;
        expect(
          MbPalette.contrastRatio(palette.text, palette.background),
          greaterThanOrEqualTo(4.5),
          reason: preset.id,
        );
        expect(
          MbPalette.contrastRatio(palette.onAccent, palette.accent),
          greaterThanOrEqualTo(4.5),
          reason: preset.id,
        );
      }
    }
  });
}
