import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/ios_home_icon.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/widgets/design/eirenyu_mark.dart';
import 'package:mangabaka_app/core/widgets/design/mb_nav.dart';
import 'package:mangabaka_app/features/series/widgets/series_detail_fab.dart';
import 'package:mangabaka_app/features/series/widgets/series_segmented_control.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/appearance_settings.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/theme_miniature_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SettingsManager.resetForTesting();
    LocalizationService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    await SettingsManager().init();
    await LocalizationService().init();
  });

  Future<void> pump(WidgetTester tester, {TargetPlatform? platform}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.dark,
        ).copyWith(platform: platform),
        home: const Scaffold(
          body: SingleChildScrollView(child: AppearanceSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iPhone Appearance shows the concise Home Screen icon note', (
    tester,
  ) async {
    await pump(tester, platform: TargetPlatform.iOS);
    expect(find.text('Home Screen Icon'), findsOneWidget);
    expect(
      find.text(
        'Custom colors work inside EirenYu, but the iPhone icon supports preset colors only.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'explicit mode changes request the resolved icon while system brightness stays read-only',
    (tester) async {
      final settings = SettingsManager();
      await settings.setDarkThemeId('default');
      final theme = ThemeController()..init();
      const channel = MethodChannel('eirenyu/home_icon');
      String? nativeIcon;
      final requests = <String?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'supported':
                return true;
              case 'current':
                return nativeIcon;
              case 'set':
                nativeIcon = call.arguments as String?;
                requests.add(nativeIcon);
                return null;
            }
            throw StateError(call.method);
          });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      final icon = IosHomeIcon(theme, channel: channel)..start();
      addTearDown(() {
        icon.dispose();
        theme.dispose();
        dispatcher.clearPlatformBrightnessTestValue();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: IosHomeIconScope(
            icon: icon,
            child: const Scaffold(
              body: SingleChildScrollView(child: AppearanceSettings()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, isEmpty);

      Future<void> choose(String mode) async {
        await tester.tap(find.byKey(Key('appearance_mode_$mode')));
        await tester.pumpAndSettle();
      }

      await choose('light');
      expect(requests, isEmpty);
      await choose('dark');
      expect(requests, ['IconEmerald']);
      await choose('system');
      expect(requests, ['IconEmerald']);
      dispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(requests, ['IconEmerald']);
      await choose('light');
      expect(requests, ['IconEmerald', null]);

      await settings.setManualLogoColor(0xFF4CC9FF);
      await settings.setMatchLogoToAccent(false);
      icon.request();
      await tester.pumpAndSettle();
      expect(requests, ['IconEmerald', null, 'IconHorizonBlue']);
      await choose('dark');
      await choose('system');
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(requests, ['IconEmerald', null, 'IconHorizonBlue']);
      expect(settings.manualLogoColor, 0xFF4CC9FF);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

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
    await _showPreset(tester, Brightness.dark, 'nord');
    await tester.tap(find.byKey(const Key('appearance_preset_dark_nord')));
    await tester.pumpAndSettle();
    expect(SettingsManager().darkThemeId, 'nord');

    await tester.ensureVisible(find.byKey(const Key('appearance_mode_system')));
    await tester.pumpAndSettle();
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
    await _showPreset(tester, Brightness.light, 'catppuccin');
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

  testWidgets(
    'horizontal galleries reveal later presets and keep their scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester);

      final darkRail = find.byKey(
        const PageStorageKey<String>('appearance_gallery_dark'),
      );
      expect(darkRail, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(darkRail).scrollDirection,
        Axis.horizontal,
      );
      final first = find.byKey(const Key('appearance_preset_dark_eirenyu'));
      final second = find.byKey(const Key('appearance_preset_dark_default'));
      expect(tester.getSize(first).width, inInclusiveRange(150, 220));
      expect(tester.getRect(second).left, lessThan(320));

      await tester.drag(darkRail, const Offset(-500, 0));
      await tester.pumpAndSettle();
      final nord = find.byKey(const Key('appearance_preset_dark_nord'));
      await _showPreset(tester, Brightness.dark, 'nord');
      await tester.pumpAndSettle();
      final leftBefore = tester.getRect(nord).left;
      await tester.tap(nord);
      await tester.pumpAndSettle();
      expect(SettingsManager().darkThemeId, 'nord');
      expect(tester.getRect(nord).left, closeTo(leftBefore, 1));
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(nord).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        find.descendant(of: nord, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      semantics.dispose();

      await tester.ensureVisible(
        find.byKey(const Key('appearance_mode_system')),
      );
      await tester.tap(find.byKey(const Key('appearance_mode_system')));
      await tester.pumpAndSettle();
      final lightRail = find.byKey(
        const PageStorageKey<String>('appearance_gallery_light'),
      );
      expect(lightRail, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(lightRail).scrollDirection,
        Axis.horizontal,
      );
      expect(
        find.byKey(const Key('appearance_preset_light_amoled')),
        findsNothing,
      );
      expect(tester.getRect(nord).left, closeTo(leftBefore, 1));
      await tester.ensureVisible(lightRail);
      await tester.pumpAndSettle();
      await tester.drag(lightRail, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.byKey(const Key('appearance_preset_light_eirenyu')))
            .left,
        lessThan(0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('miniature surfaces match actual dark and light palette roles', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('appearance_mode_system')));
    await tester.pumpAndSettle();
    for (final (brightness, preset) in [
      (Brightness.dark, ThemePresets.byId('nord')!),
      (Brightness.light, ThemePresets.byId('catppuccin')!),
    ]) {
      final palette = brightness == Brightness.dark
          ? preset.dark!
          : preset.light!;
      final preview = find.byKey(
        Key('appearance_preview_${brightness.name}_${preset.id}'),
      );
      expect(tester.widget<ThemeMiniaturePreview>(preview).palette, palette);
      Color painted(String key) {
        final container = tester.widget<Container>(
          find.descendant(of: preview, matching: find.byKey(Key(key))),
        );
        final decoration = container.decoration;
        return decoration is BoxDecoration
            ? decoration.color!
            : container.color!;
      }

      expect(painted('appearance_preview_background'), palette.background);
      expect(painted('appearance_preview_cover'), palette.surfaceRaised);
      expect(painted('appearance_preview_active_nav'), palette.accent);
      expect(painted('appearance_preview_navigation'), palette.background);
      final size = tester.getSize(preview);
      expect(size.width / size.height, closeTo(160 / 328, 0.01));
      final cover = tester.getSize(
        find.descendant(
          of: preview,
          matching: find.byKey(const Key('appearance_preview_cover')),
        ),
      );
      expect(cover.width / cover.height, closeTo(2 / 3, 0.01));
      expect(
        find.descendant(of: preview, matching: find.text('HOME')),
        findsOneWidget,
      );
      final header = tester.getRect(
        find.descendant(
          of: preview,
          matching: find.byKey(const Key('appearance_preview_header')),
        ),
      );
      final home = tester.getRect(
        find.descendant(of: preview, matching: find.text('HOME')),
      );
      final settings = tester.getRect(
        find.descendant(
          of: preview,
          matching: find.byIcon(Icons.settings_outlined),
        ),
      );
      expect(home.center.dx, closeTo(header.center.dx, 1));
      expect(home.right, lessThan(settings.left));
      expect(
        find.descendant(of: preview, matching: find.text('FOR YOU')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.text('TOP IN CULT')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(Icon)),
        findsNWidgets(10),
      );
    }
  });

  testWidgets('saved yellow drives navigation, Appearance and series fills', (
    tester,
  ) async {
    final settings = SettingsManager();
    final controller = ThemeController()..init();
    addTearDown(controller.dispose);
    await settings.setThemeMode(AppThemeMode.system);
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    const yellow = Color(0xFFFBD24B);
    expect(ThemePresets.accentSwatches[1], yellow);

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: controller,
        builder: (_, _) => MaterialApp(
          theme: AppTheme.build(
            showTooltips: true,
            palette: controller.lightPalette,
          ),
          darkTheme: AppTheme.build(
            showTooltips: true,
            palette: controller.darkPalette,
          ),
          themeMode: ThemeMode.system,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SeriesAddToLibraryButton(editorOpen: false, onAdd: () {}),
                  SeriesSegmentedControl(
                    selectedTab: 'Info',
                    onTabChanged: (_) {},
                  ),
                  const AppearanceSettings(),
                ],
              ),
            ),
            bottomNavigationBar: MbBottomNav(
              destinations: const [
                MbNavDestination(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: 'Home',
                ),
              ],
              selectedIndex: 0,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final swatch = find.byKey(const Key('appearance_accent_1'));
    await tester.ensureVisible(swatch);
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    expect(settings.accentOverride, yellow.toARGB32());

    for (final brightness in Brightness.values) {
      dispatcher.platformBrightnessTestValue = brightness;
      await tester.pumpAndSettle();
      final mode = find.byKey(const Key('appearance_mode_system'));
      await tester.ensureVisible(mode);
      await tester.pumpAndSettle();
      final rawChip = tester.widget<RawChip>(
        find.descendant(of: mode, matching: find.byType(RawChip)),
      );
      expect(rawChip.selected, isTrue);
      expect(rawChip.selectedColor, yellow);
      expect(rawChip.labelStyle!.color, Colors.black);

      final nav = find.byType(MbBottomNav);
      final activeNav = tester.widget<AnimatedContainer>(
        find.descendant(of: nav, matching: find.byType(AnimatedContainer)),
      );
      expect((activeNav.decoration as BoxDecoration).color, yellow);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.home_rounded)).color,
        Colors.black,
      );

      final preview = find.byKey(
        Key('appearance_preview_${brightness.name}_eirenyu'),
      );
      final previewNav = find.descendant(
        of: preview,
        matching: find.byKey(const Key('appearance_preview_active_nav')),
      );
      expect(
        (tester.widget<Container>(previewNav).decoration as BoxDecoration)
            .color,
        yellow,
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: previewNav, matching: find.byType(Icon)),
            )
            .color,
        Colors.black,
      );
      final preset = find.byKey(
        Key('appearance_preset_${brightness.name}_eirenyu'),
      );
      final check = find.descendant(
        of: preset,
        matching: find.byIcon(Icons.check_circle),
      );
      expect(tester.widget<Icon>(check).color, yellow);

      final add = find.byKey(const Key('add_to_library_button'));
      final material = tester.widget<Material>(
        find.descendant(of: add, matching: find.byType(Material)),
      );
      expect(material.color, yellow);
      expect(material.textStyle!.color, Colors.black);
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect((tabs.indicator as BoxDecoration).color, yellow);
      expect(tabs.labelColor, Colors.black);

      final theme = Theme.of(tester.element(add));
      expect(theme.colorScheme.primary, yellow);
      expect(theme.colorScheme.onPrimary, Colors.black);
      expect(theme.progressIndicatorTheme.color, yellow);
      expect(theme.sliderTheme.activeTrackColor, yellow);
      expect(
        theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
        yellow,
      );
      expect(
        theme.switchTheme.thumbColor!.resolve({WidgetState.selected}),
        Colors.black,
      );
    }
  });

  testWidgets(
    'accent override changes miniature palettes and reset restores them',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('appearance_mode_system')));
      await tester.pumpAndSettle();
      final dark = find.byKey(const Key('appearance_preview_dark_nord'));
      final light = find.byKey(
        const Key('appearance_preview_light_catppuccin'),
      );
      MbPalette palette(Finder preview) =>
          tester.widget<ThemeMiniaturePreview>(preview).palette;
      expect(palette(dark).accent, ThemePresets.byId('nord')!.dark!.accent);
      expect(
        palette(light).accent,
        ThemePresets.byId('catppuccin')!.light!.accent,
      );

      final swatch = find.byKey(const Key('appearance_accent_10'));
      await tester.ensureVisible(swatch);
      await tester.tap(swatch);
      await tester.pumpAndSettle();
      const override = Color(0xFFA82F4F);
      expect(
        palette(dark),
        ThemePresets.byId('nord')!.dark!.withAccent(override),
      );
      expect(
        palette(light),
        ThemePresets.byId('catppuccin')!.light!.withAccent(override),
      );
      final native = tester.widget<Container>(
        find.byKey(const Key('appearance_native_accent_dark_nord')),
      );
      expect(
        (native.decoration! as BoxDecoration).color,
        ThemePresets.byId('nord')!.dark!.accent,
      );

      final themeDefault = find.byKey(const Key('appearance_accent_default'));
      await tester.tap(themeDefault);
      await tester.pumpAndSettle();
      expect(palette(dark), ThemePresets.byId('nord')!.dark);
      expect(palette(light), ThemePresets.byId('catppuccin')!.light);
    },
  );

  testWidgets('gallery coexists with vertical scrolling on short landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    final darkRail = find.byKey(
      const PageStorageKey<String>('appearance_gallery_dark'),
    );
    await tester.ensureVisible(darkRail);
    await tester.pumpAndSettle();
    await tester.drag(darkRail, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.byKey(const Key('appearance_preset_dark_eirenyu')))
          .left,
      lessThan(0),
    );
    final outer = find.byType(SingleChildScrollView).first;
    await tester.drag(outer, const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('appearance_accent_default')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow Logo gallery shows all named marks and retains selection',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        await pump(tester);
        final match = find.byKey(const Key('appearance_logo_match'));
        final gallery = find.byKey(
          const PageStorageKey('appearance_logo_gallery'),
        );
        expect(tester.widget<SwitchListTile>(match).value, isTrue);
        expect(
          find.byKey(const Key('appearance_logo_preview')),
          findsOneWidget,
        );
        expect(gallery, findsNothing);
        await tester.ensureVisible(match);
        await tester.pumpAndSettle();
        await tester.tap(match);
        await tester.pumpAndSettle();
        await tester.ensureVisible(gallery);
        await tester.pumpAndSettle();

        const names = [
          'Emerald',
          'Amber',
          'Orange',
          'Rose',
          'Pink',
          'Violet',
          'Blue',
          'Cyan',
          'Teal',
          'Lime',
          'Crimson Moon',
          'Twilight Lavender',
          'Horizon Blue',
        ];
        Finder option(int index) =>
            find.byKey(Key('appearance_logo_swatch_$index'));
        final previews = find.descendant(
          of: gallery,
          matching: find.byType(EirenYuMark),
        );
        expect(previews, findsNWidgets(names.length));
        for (final (index, name) in names.indexed) {
          expect(
            find.descendant(of: option(index), matching: find.text(name)),
            findsOneWidget,
          );
          final mark = tester.widget<EirenYuMark>(previews.at(index));
          expect(mark.color, ThemePresets.accentSwatches[index]);
          expect(mark.size, 56);
        }

        final firstX = tester.getTopLeft(option(0)).dx;
        await tester.drag(gallery, const Offset(-260, 0));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(option(0)).dx, lessThan(firstX));
        await tester.ensureVisible(option(10));
        await tester.pumpAndSettle();
        expect(tester.getSemantics(option(10)).label, 'Crimson Moon');
        expect(
          tester.getSemantics(option(10)).flagsCollection.isSelected,
          Tristate.isTrue,
        );

        await tester.ensureVisible(option(12));
        await tester.pumpAndSettle();
        await tester.tap(option(12));
        await tester.pumpAndSettle();
        expect(tester.getSemantics(option(12)).label, 'Horizon Blue');
        expect(
          tester.getSemantics(option(12)).flagsCollection.isSelected,
          Tristate.isTrue,
        );
        expect(
          find.descendant(
            of: option(12),
            matching: find.byIcon(Icons.check_circle),
          ),
          findsOneWidget,
        );

        await tester.ensureVisible(match);
        await tester.pumpAndSettle();
        await tester.tap(match);
        await tester.pumpAndSettle();
        expect(gallery, findsNothing);
        expect(
          SettingsManager().manualLogoColor,
          EirenYuPalette.horizonBlue.toARGB32(),
        );
        await tester.tap(match);
        await tester.pumpAndSettle();
        await tester.ensureVisible(option(12));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(option(12)).flagsCollection.isSelected,
          Tristate.isTrue,
        );

        await tester.ensureVisible(option(0));
        Focus.of(tester.element(find.text('Emerald'))).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          SettingsManager().manualLogoColor,
          ThemePresets.accentSwatches[1].toARGB32(),
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

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
      await _showPreset(tester, Brightness.dark, preset.id);
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
      await _showPreset(tester, Brightness.light, preset.id);
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
      await _showPreset(tester, Brightness.dark, 'nord');
      await tester.tap(find.byKey(const Key('appearance_preset_dark_nord')));
      await tester.pumpAndSettle();
      expect(background(), ThemePresets.byId('nord')!.dark!.background);

      await tester.ensureVisible(
        find.byKey(const Key('appearance_mode_light')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance_mode_light')));
      await tester.pumpAndSettle();
      expect(find.text('light'), findsOneWidget);
      await _showPreset(tester, Brightness.light, 'nord');
      await tester.tap(find.byKey(const Key('appearance_preset_light_nord')));
      await tester.pumpAndSettle();
      expect(background(), ThemePresets.byId('nord')!.light!.background);
    },
  );
}

Future<void> _showPreset(
  WidgetTester tester,
  Brightness brightness,
  String id,
) async {
  final rail = find.byKey(
    PageStorageKey<String>('appearance_gallery_${brightness.name}'),
  );
  await tester.ensureVisible(rail);
  await tester.scrollUntilVisible(
    find.byKey(Key('appearance_preset_${brightness.name}_$id')),
    220,
    scrollable: find.descendant(of: rail, matching: find.byType(Scrollable)),
  );
  await tester.pumpAndSettle();
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
