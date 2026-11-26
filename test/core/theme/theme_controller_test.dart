import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_keys.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SettingsManager.resetForTesting());

  test('light presets retain distinct, readable tonal surfaces', () {
    const expected = <String, (int, int, int, int)>{
      'eirenyu': (0xFFF5EBEF, 0xFFFFF8FA, 0xFFEBDCE3, 0xFFCDB8C2),
      'default': (0xFFE4EFE6, 0xFFF2F8F2, 0xFFD3E5D6, 0xFFB3CDB9),
      'catppuccin': (0xFFEFF1F5, 0xFFF7F3FB, 0xFFE2D9EF, 0xFFC7B9D7),
      'nord': (0xFFE5E9F0, 0xFFF0F4F8, 0xFFD8DEE9, 0xFFC3CBD8),
      'midnight_dusk': (0xFFF0E7ED, 0xFFF9F1F5, 0xFFE5D5DE, 0xFFCDBAC5),
      'strawberry': (0xFFF8E5E9, 0xFFFFF3F5, 0xFFF0D4DB, 0xFFD9B4BF),
      'tako': (0xFFEEE7F3, 0xFFF8F3FA, 0xFFE1D6E9, 0xFFC9B8D3),
      'yotsuba': (0xFFF8E9DB, 0xFFFFF4E9, 0xFFF0DCC9, 0xFFD9BDA3),
      'green_apple': (0xFFEBF2D9, 0xFFF6F9E9, 0xFFDDE9C0, 0xFFBDD099),
      'teal': (0xFFDDF1EC, 0xFFEDF9F5, 0xFFCCE8E1, 0xFFA7CDC3),
      'tidal_wave': (0xFFE0F0F6, 0xFFF0F8FB, 0xFFCCE5EF, 0xFFA9CBDC),
      'lavender': (0xFFECE6F6, 0xFFF7F2FC, 0xFFDED2EF, 0xFFBEABD8),
    };
    for (final entry in expected.entries) {
      final palette = ThemePresets.byId(entry.key)!.light!;
      final (background, surface, raised, border) = entry.value;
      expect(palette.background.toARGB32(), background, reason: entry.key);
      expect(palette.surface.toARGB32(), surface, reason: entry.key);
      expect(palette.surfaceRaised.toARGB32(), raised, reason: entry.key);
      expect(palette.border.toARGB32(), border, reason: entry.key);
      expect(
        MbPalette.contrastRatio(palette.text, palette.background),
        greaterThanOrEqualTo(4.5),
        reason: entry.key,
      );
      expect(
        MbPalette.contrastRatio(palette.text, palette.surface),
        greaterThanOrEqualTo(4.5),
        reason: entry.key,
      );
      expect(
        MbPalette.contrastRatio(palette.textMuted, palette.background),
        greaterThanOrEqualTo(4.5),
        reason: entry.key,
      );
      expect(
        MbPalette.contrastRatio(palette.accentForeground, palette.surface),
        greaterThanOrEqualTo(4.5),
        reason: entry.key,
      );
    }
    expect(ThemePresets.byId('amoled')!.light, isNull);
    expect(
      ThemePresets.byId('monochrome')!.light!.surface,
      const Color(0xFFFFFFFF),
    );
    expect(
      ThemePresets.byId('amoled')!.dark!.background,
      const Color(0xFF000000),
    );
  });

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
    'logo uses the active preset and preserves the exact saved accent',
    () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.darkThemeId: 'nord',
        SettingsKeys.lightThemeId: 'catppuccin',
        SettingsKeys.accentOverride: 0x80FFFFFF,
      });
      await SettingsManager().init();
      final controller = ThemeController()..init();
      addTearDown(controller.dispose);
      final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);

      final darkAccent = ThemePresets.byId('nord')!.dark!.accent;
      final lightAccent = ThemePresets.byId('catppuccin')!.light!.accent;
      expect(controller.currentLogoColor, darkAccent);
      await controller.setMode(AppThemeMode.light);
      expect(controller.currentLogoColor, lightAccent);
      await controller.setMode(AppThemeMode.system);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      expect(controller.currentLogoColor, darkAccent);
      dispatcher.platformBrightnessTestValue = Brightness.light;
      expect(controller.currentLogoColor, lightAccent);

      const custom = Color(0xFFFAFCFE);
      await controller.setAccentOverride(custom);
      expect(controller.lightPalette.accent, isNot(custom));
      expect(controller.currentLogoColor.toARGB32(), custom.toARGB32());
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      expect(controller.currentLogoColor.toARGB32(), custom.toARGB32());
      await controller.setAccentOverride(null);
      expect(controller.currentLogoColor, darkAccent);
    },
  );

  test(
    'a manual logo change notifies without changing the theme palette',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsManager();
      await settings.init();
      final controller = ThemeController()..init();
      addTearDown(controller.dispose);
      final original = controller.darkPalette;
      var notifications = 0;
      controller.addListener(() => notifications++);

      await settings.setManualLogoColor(0xFF22D3EE);
      expect(notifications, 0);
      await settings.setMatchLogoToAccent(false);
      expect(notifications, 1);
      expect(controller.currentLogoColor, const Color(0xFF22D3EE));
      await settings.setManualLogoColor(0xFF5BBD74);
      expect(notifications, 2);
      expect(controller.currentLogoColor, const Color(0xFF5BBD74));
      expect(controller.darkPalette, original);
    },
  );

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

  test('canonical yellow stays exact across supported preset variants', () {
    const yellow = Color(0xFFFBD24B);
    const other = Color(0xFF1B203A);
    for (final preset in ThemePresets.all) {
      for (final base in [?preset.dark, ?preset.light]) {
        final palette = base.withAccent(yellow);
        expect(palette.accent, yellow);
        expect(palette.onAccent, Colors.black);
        expect(palette.progressIndicator, yellow);
        expect(palette.accentOn(yellow), Colors.black);
        expect(
          palette.accentForeground,
          MbPalette.contrastRatio(yellow, base.surface) >= 4.5
              ? yellow
              : base.text,
        );
        expect(
          base.withAccent(other).accent,
          MbPalette.ensureContrast(other, base.surface, minimum: 3.0),
        );
        expect(
          base.withAccent(other).onAccent,
          MbPalette.readableOn(base.withAccent(other).accent),
        );
      }
    }
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

  test(
    'Crimson Moon stays exact for fills and gets legible foreground ink',
    () {
      final palette = EirenYuPalette.dark;
      expect(palette.accent, const Color(0xFFA82F4F));
      expect(
        MbPalette.contrastRatio(palette.onAccent, palette.accent),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        MbPalette.contrastRatio(palette.accentForeground, palette.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(palette.accentForeground, isNot(palette.accent));
      for (final variant in [
        EirenYuPalette.light,
        ThemePresets.originalGreen,
      ]) {
        expect(
          MbPalette.contrastRatio(variant.accentForeground, variant.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );

  test(
    'shared accent roles meet contrast floors on their actual backgrounds',
    () {
      final representativePalettes = [
        EirenYuPalette.dark,
        EirenYuPalette.light,
        ThemePresets.byId('nord')!.dark!,
        ThemePresets.byId('nord')!.light!,
      ];

      for (final palette in representativePalettes) {
        expect(
          MbPalette.contrastRatio(
            palette.progressIndicator,
            palette.surfaceRaised,
          ),
          greaterThanOrEqualTo(3.0),
          reason: '${palette.brightness} progress indicator',
        );
        expect(
          MbPalette.contrastRatio(
            palette.accentOn(palette.surfaceRaised),
            palette.surfaceRaised,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.brightness} snackbar action',
        );

        final snackBar = AppTheme.build(
          showTooltips: true,
          palette: palette,
        ).snackBarTheme;
        expect(snackBar.backgroundColor, palette.surfaceRaised);
        expect(
          MbPalette.contrastRatio(
            snackBar.actionTextColor!,
            snackBar.backgroundColor!,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.brightness} rendered snackbar action',
        );
      }
    },
  );

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
