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
    final override = _settings.accentOverride;
    MbPalette accent(MbPalette p) =>
        override == null ? p : p.withAccent(Color(override));
    final dark = accent(_for(_settings.darkThemeId, Brightness.dark));
    final light = accent(_for(_settings.lightThemeId, Brightness.light));
    final mode = _settings.themeMode;
    if (dark == _dark && light == _light && mode == _mode) return;
    _dark = dark;
    _light = light;
    _mode = mode;
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    if (_mode == AppThemeMode.system) notifyListeners();
  }
}
