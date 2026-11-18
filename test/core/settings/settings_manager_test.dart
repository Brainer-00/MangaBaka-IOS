import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
  });

  group('SettingsManager', () {
    test('initializes with default values', () async {
      final manager = SettingsManager();
      await manager.init();

      expect(manager.themeMode, AppThemeMode.dark);
      expect(manager.darkThemeId, 'eirenyu');
      expect(manager.lightThemeId, 'eirenyu');
      expect(manager.accentOverride, isNull);
      expect(manager.matchLogoToAccent, isTrue);
      expect(manager.manualLogoColor, 0xFFA82F4F);
      expect(manager.currentListStyle, AppListStyle.compactGrid);
      expect(manager.hideLibrarySeriesInBrowse, false);
      expect(manager.contentPreferences, ['safe', 'suggestive']);
      expect(manager.showTooltips, true);
      expect(manager.compactGridTitleRows, 1);
      expect(manager.defaultStartPage, AppStartPage.home);
    });

    test('loads values from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.themeMode: 'light',
        SettingsKeys.darkThemeId: 'nord',
        SettingsKeys.lightThemeId: 'catppuccin',
        SettingsKeys.accentOverride: 0xFF8B7CF6,
        SettingsKeys.listStylePref: AppListStyle.comfortable.index,
        SettingsKeys.hideLibrarySeriesInBrowse: true,
        SettingsKeys.contentPreferences: ['safe', 'suggestive', 'erotica'],
        SettingsKeys.showTooltips: false,
        SettingsKeys.compactGridTitleRows: 3,
        SettingsKeys.defaultStartPage: AppStartPage.news.index,
      });

      final manager = SettingsManager();
      await manager.init();

      expect(manager.themeMode, AppThemeMode.light);
      expect(manager.darkThemeId, 'nord');
      expect(manager.lightThemeId, 'catppuccin');
      expect(manager.accentOverride, 0xFF8B7CF6);
      expect(manager.matchLogoToAccent, isTrue);
      expect(manager.manualLogoColor, 0xFFA82F4F);
      expect(manager.currentListStyle, AppListStyle.comfortable);
      expect(manager.hideLibrarySeriesInBrowse, true);
      expect(manager.contentPreferences, contains('erotica'));
      expect(manager.showTooltips, false);
      expect(manager.compactGridTitleRows, 3);
      expect(manager.defaultStartPage, AppStartPage.news);
    });

    test('appearance settings update and persist', () async {
      final manager = SettingsManager();
      await manager.init();

      await manager.setThemeMode(AppThemeMode.system);
      await manager.setDarkThemeId('dracula');
      await manager.setAccentOverride(0xFFA82F4F);
      expect(manager.themeMode, AppThemeMode.system);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SettingsKeys.accentOverride), 0xFFA82F4F);
      expect(prefs.getString(SettingsKeys.themeMode), 'system');
      expect(prefs.getString(SettingsKeys.darkThemeId), 'dracula');
    });

    test('logo settings reload independently of theme and accent', () async {
      final manager = SettingsManager();
      await manager.init();
      await manager.setMatchLogoToAccent(false);
      await manager.setManualLogoColor(0xFF22D3EE);
      await manager.setThemeMode(AppThemeMode.light);
      await manager.setAccentOverride(0xFF123456);
      await manager.setMatchLogoToAccent(true);
      await manager.setMatchLogoToAccent(false);

      final prefs = await SharedPreferences.getInstance();
      SettingsManager.resetForTesting();
      expect(manager.matchLogoToAccent, isTrue);
      expect(manager.manualLogoColor, 0xFFA82F4F);
      await prefs.reload();
      await manager.init();

      expect(manager.matchLogoToAccent, isFalse);
      expect(manager.manualLogoColor, 0xFF22D3EE);
      expect(manager.accentOverride, 0xFF123456);
      expect(manager.themeMode, AppThemeMode.light);
    });

    test('invalid stored logo choices and accents fall back safely', () async {
      for (final invalid in ['bad', 0x80778899, 0x1FF223344, -1]) {
        SharedPreferences.setMockInitialValues({
          SettingsKeys.matchLogoToAccent: 'off',
          SettingsKeys.manualLogoColor: invalid,
          SettingsKeys.accentOverride: invalid,
        });
        SettingsManager.resetForTesting();
        final manager = SettingsManager();
        await manager.init();

        expect(manager.matchLogoToAccent, isTrue);
        expect(manager.manualLogoColor, 0xFFA82F4F);
        expect(manager.accentOverride, isNull);
      }

      SharedPreferences.setMockInitialValues({
        SettingsKeys.manualLogoColor: 0xFF123456,
      });
      SettingsManager.resetForTesting();
      final manager = SettingsManager();
      await manager.init();
      expect(manager.manualLogoColor, 0xFFA82F4F);
      await manager.setManualLogoColor(0xFF123456);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SettingsKeys.manualLogoColor), 0xFFA82F4F);
    });

    test('updates values and notifies listeners', () async {
      final manager = SettingsManager();
      await manager.init();

      bool notified = false;
      manager.addListener(() {
        notified = true;
      });

      await manager.setListStyle(AppListStyle.compact);
      expect(manager.currentListStyle, AppListStyle.compact);
      expect(notified, true);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(SettingsKeys.listStylePref),
        AppListStyle.compact.index,
      );
    });

    test('setContentPreferences updates and persists', () async {
      final manager = SettingsManager();
      await manager.init();

      await manager.setContentPreferences(['safe']);
      expect(manager.contentPreferences, ['safe']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(SettingsKeys.contentPreferences), ['safe']);
    });

    test('toggle separateListStyles persists', () async {
      final manager = SettingsManager();
      await manager.init();

      await manager.setSeparateListStyles(true);
      expect(manager.separateListStyles, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SettingsKeys.separateListStyles), true);
    });

    test('compactGridTitleRows updates and persists within limits', () async {
      final manager = SettingsManager();
      await manager.init();

      await manager.setCompactGridTitleRows(5);
      expect(manager.compactGridTitleRows, 5);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(SettingsKeys.compactGridTitleRows), 5);

      // Test clamping/limits
      await manager.setCompactGridTitleRows(100);
      expect(manager.compactGridTitleRows, 99); // Clamped to 99

      await manager.setCompactGridTitleRows(0);
      expect(manager.compactGridTitleRows, 1); // Clamped to 1
    });
  });
}
