import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';

class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController({SettingsManager? settings})
    : _settings = settings ?? SettingsManager();

  final SettingsManager _settings;
  bool _initialized = false;
  AppThemeMode _mode = AppThemeMode.dark;
  MbPalette _dark = EirenYuPalette.dark;
  MbPalette _light = EirenYuPalette.light;
  Color _darkLogoColor = EirenYuPalette.dark.accent;
  Color _lightLogoColor = EirenYuPalette.light.accent;

  void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_resolve);
    _resolve();
  }

  @override
  void dispose() {
    if (_initialized) {
      WidgetsBinding.instance.removeObserver(this);
      _settings.removeListener(_resolve);
    }
    super.dispose();
  }

  AppThemeMode get mode => _mode;
  ThemeMode get materialThemeMode => switch (_mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
  MbPalette get darkPalette => _dark;
  MbPalette get lightPalette => _light;
  MbPalette get current => switch (_mode) {
    AppThemeMode.light => _light,
    AppThemeMode.dark => _dark,
    AppThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
          ? _dark
          : _light,
  };
  Color get currentLogoColor =>
      current.brightness == Brightness.dark ? _darkLogoColor : _lightLogoColor;

  Future<void> setMode(AppThemeMode mode) => _settings.setThemeMode(mode);
  Future<void> select(String id, Brightness brightness) {
    final validId = _validId(id, brightness);
    return brightness == Brightness.dark
        ? _settings.setDarkThemeId(validId)
        : _settings.setLightThemeId(validId);
  }

  Future<void> setAccentOverride(Color? color) =>
      _settings.setAccentOverride(color?.toARGB32());

  MbPalette _for(String id, Brightness brightness) {
    final preset = ThemePresets.byId(_validId(id, brightness));
    return (brightness == Brightness.dark ? preset?.dark : preset?.light) ??
        (brightness == Brightness.dark
            ? EirenYuPalette.dark
            : EirenYuPalette.light);
  }

  String _validId(String id, Brightness brightness) {
    final preset = ThemePresets.byId(id);
    final supported = brightness == Brightness.dark
        ? preset?.dark != null
        : preset?.light != null;
    return supported ? id : ThemePresets.defaultId;
  }

  void _resolve() {
    final overrideArgb = _settings.accentOverride;
    final override = overrideArgb == null ? null : Color(overrideArgb);
    final darkPreset = _for(_settings.darkThemeId, Brightness.dark);
    final lightPreset = _for(_settings.lightThemeId, Brightness.light);
    final dark = override == null
        ? darkPreset
        : darkPreset.withAccent(override);
    final light = override == null
        ? lightPreset
        : lightPreset.withAccent(override);
    // The logo follows the original preset or exact saved ARGB. UI contrast
    // adjustments belong to the palettes above.
    final logoColor = _settings.matchLogoToAccent
        ? override
        : Color(_settings.manualLogoColor);
    final darkLogoColor = logoColor ?? darkPreset.accent;
    final lightLogoColor = logoColor ?? lightPreset.accent;
    final mode = _settings.themeMode;
    if (dark == _dark &&
        light == _light &&
        darkLogoColor == _darkLogoColor &&
        lightLogoColor == _lightLogoColor &&
        mode == _mode) {
      return;
    }
    _dark = dark;
    _light = light;
    _darkLogoColor = darkLogoColor;
    _lightLogoColor = lightLogoColor;
    _mode = mode;
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppThemeMode.system) notifyListeners();
  }
}
