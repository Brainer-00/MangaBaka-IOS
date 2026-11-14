import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/appearance_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SettingsManager.resetForTesting();
    LocalizationService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    await SettingsManager().init();
    await LocalizationService().init();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: EirenYuPalette.dark),
        home: const Scaffold(
          body: SingleChildScrollView(child: AppearanceSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mode filters real preset variants and keeps separate choices', (
    tester,
  ) async {
    await pump(tester);
    expect(SettingsManager().themeMode, AppThemeMode.dark);
    expect(
      find.byKey(const Key('appearance_preset_dark_amoled')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('appearance_preset_light_nord')), findsNothing);
    await tester.tap(find.byKey(const Key('appearance_preset_dark_nord')));
    await tester.pumpAndSettle();
    expect(SettingsManager().darkThemeId, 'nord');

    await tester.tap(find.byKey(const Key('appearance_mode_system')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('appearance_preset_light_nord')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance_preset_light_amoled')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance_preset_dark_amoled')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('appearance_preset_light_catppuccin')),
    );
    await tester.tap(
      find.byKey(const Key('appearance_preset_light_catppuccin')),
    );
    await tester.pumpAndSettle();
    expect(SettingsManager().darkThemeId, 'nord');
    expect(SettingsManager().lightThemeId, 'catppuccin');
    expect(ThemePresets.all.length, 15);
    expect(find.textContaining('My Themes'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('appearance_mode_light')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance_mode_light')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appearance_preset_dark_nord')), findsNothing);
    expect(SettingsManager().themeMode, AppThemeMode.light);
  });

  testWidgets('curated and custom accents persist, then theme default clears', (
    tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(find.byKey(const Key('appearance_accent_10')));
    await tester.tap(find.byKey(const Key('appearance_accent_10')));
    await tester.pumpAndSettle();
    expect(SettingsManager().accentOverride, 0xFFA82F4F);

    await tester.tap(find.byKey(const Key('appearance_custom_accent')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('appearance_picker_hue')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance_picker_apply')));
    await tester.pumpAndSettle();
    final custom = SettingsManager().accentOverride;
    expect(custom, isNotNull);
    expect(custom! & 0xFF000000, 0xFF000000);
    expect(custom, isNot(0xFFA82F4F));

    await tester.tap(find.byKey(const Key('appearance_custom_accent')));
    await tester.pumpAndSettle();
    expect(
      find.text('#${custom.toRadixString(16).substring(2).toUpperCase()}'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('appearance_picker_cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance_accent_default')));
    await tester.pumpAndSettle();
    expect(SettingsManager().accentOverride, isNull);
  });

  testWidgets('every built-in preset can be selected in its supported slot', (
    tester,
  ) async {
    await pump(tester);
    for (final preset in ThemePresets.all) {
      if (preset.dark == null) continue;
      final card = find.byKey(Key('appearance_preset_dark_${preset.id}'));
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(SettingsManager().darkThemeId, preset.id);
    }
    await tester.ensureVisible(find.byKey(const Key('appearance_mode_light')));
    await tester.tap(find.byKey(const Key('appearance_mode_light')));
    await tester.pumpAndSettle();
    for (final preset in ThemePresets.all) {
      final card = find.byKey(Key('appearance_preset_light_${preset.id}'));
      if (preset.light == null) {
        expect(card, findsNothing);
        continue;
      }
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(SettingsManager().lightThemeId, preset.id);
    }
  });

  testWidgets('swatches have named semantics and 48 pixel touch targets', (
    tester,
  ) async {
    await pump(tester);
    final semantics = tester.ensureSemantics();

    final emerald = find.byKey(const Key('appearance_accent_0'));
    final crimsonMoon = find.byKey(const Key('appearance_accent_10'));
    expect(tester.getSize(emerald), const Size(48, 48));
    expect(tester.getSize(crimsonMoon), const Size(48, 48));
    expect(tester.getSemantics(emerald).label, 'Emerald, #5BBD74');
    expect(tester.getSemantics(crimsonMoon).label, 'Crimson Moon, #A82F4F');
    semantics.dispose();
  });

  testWidgets('custom picker fits short landscape and persists exact ARGB', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    await _openPicker(tester);

    expect(find.byKey(const Key('appearance_picker_cancel')), findsOneWidget);
    expect(find.byKey(const Key('appearance_picker_apply')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _selectAndApplyCustomColor(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom picker fits narrow portrait and keeps actions reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester);
      await _openPicker(tester);

      expect(find.byKey(const Key('appearance_picker_cancel')), findsOneWidget);
      expect(find.byKey(const Key('appearance_picker_apply')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('appearance_picker_apply'))).bottom,
        lessThanOrEqualTo(640),
      );
      await _selectAndApplyCustomColor(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Appearance controls update a MaterialApp owned by ThemeController',
    (tester) async {
      final themes = ThemeController()..init();
      addTearDown(themes.dispose);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: themes,
          builder: (_, _) => MaterialApp(
            theme: AppTheme.build(
              showTooltips: true,
              palette: themes.lightPalette,
            ),
            darkTheme: AppTheme.build(
              showTooltips: true,
              palette: themes.darkPalette,
            ),
            themeMode: themes.materialThemeMode,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    Builder(
                      builder: (context) => Container(
                        key: const Key('effective_theme'),
                        color: context.colors.background,
                        child: Text(Theme.of(context).brightness.name),
                      ),
                    ),
                    const AppearanceSettings(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Color background() => tester
          .widget<Container>(find.byKey(const Key('effective_theme')))
          .color!;
      expect(find.text('dark'), findsOneWidget);
      await tester.tap(find.byKey(const Key('appearance_preset_dark_nord')));
      await tester.pumpAndSettle();
      expect(background(), ThemePresets.byId('nord')!.dark!.background);

      await tester.tap(find.byKey(const Key('appearance_mode_light')));
      await tester.pumpAndSettle();
      expect(find.text('light'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('appearance_preset_light_nord')),
      );
      await tester.tap(find.byKey(const Key('appearance_preset_light_nord')));
      await tester.pumpAndSettle();
      expect(background(), ThemePresets.byId('nord')!.light!.background);
    },
  );
}

Future<void> _openPicker(WidgetTester tester) async {
  final button = find.byKey(const Key('appearance_custom_accent'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _selectAndApplyCustomColor(WidgetTester tester) async {
  final hue = find.byKey(const Key('appearance_picker_hue'));
  await tester.ensureVisible(hue);
  await tester.drag(hue, const Offset(40, 0));
  await tester.pumpAndSettle();
  final colorText = tester
      .widget<Text>(
        find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.startsWith('#') ?? false),
        ),
      )
      .data!;
  await tester.tap(find.byKey(const Key('appearance_picker_apply')));
  await tester.pumpAndSettle();
  expect(
    SettingsManager().accentOverride,
    0xFF000000 | int.parse(colorText.substring(1), radix: 16),
  );
  expect(SettingsManager().accentOverride! & 0xFF000000, 0xFF000000);
}
