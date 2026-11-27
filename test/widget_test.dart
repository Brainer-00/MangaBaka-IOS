import 'support/library_identity.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_keys.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/widgets/design/mb_nav.dart';
import 'package:mangabaka_app/core/widgets/design/eirenyu_mark.dart';
import 'package:mangabaka_app/core/widgets/design/mb_icons.dart';
import 'package:mangabaka_app/core/widgets/eirenyu_startup.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_window_frame.dart';
import 'package:mangabaka_app/features/home/screens/home_screen.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/screens/library_screen.dart';
import 'package:mangabaka_app/features/navigation/models/nav_destinations.dart';
import 'package:mangabaka_app/features/navigation/screens/main_screen.dart';
import 'package:mangabaka_app/features/navigation/screens/onboarding_screen.dart';
import 'package:mangabaka_app/features/navigation/widgets/main_top_nav_bar.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/screens/settings/settings_dialog.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/features/updates/models/app_release.dart';
import 'package:mangabaka_app/features/updates/services/update_service.dart';
import 'package:mangabaka_app/features/updates/widgets/update_dialog.dart';
import 'package:mangabaka_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Control write completion at the installed plugin's storage boundary.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class MockProfileAuthService extends Fake with WidgetLibraryIdentity {
  final List<VoidCallback> _listeners = [];

  @override
  bool isLoggedIn = false;
  @override
  final ValueNotifier<bool> awaitingBrowser = ValueNotifier(false);
  @override
  MbProfile? get cachedProfile => null;
  @override
  Future<void> init() async {}
  @override
  Future<String> getValidAccessToken() async => throw StateError('Offline');
  @override
  Future<MbProfile> fetchProfile({bool forceRefresh = false}) async =>
      throw StateError('Offline');
  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void notifyForTesting() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

class MockUpdateService extends Fake implements UpdateService {
  int shouldPromptCalls = 0;
  int checkForUpdateCalls = 0;
  AppRelease? availableRelease;

  @override
  bool get supportsInAppUpdate => false;

  @override
  bool shouldPrompt() {
    shouldPromptCalls++;
    return true;
  }

  @override
  Future<AppRelease?> checkForUpdate() async {
    checkForUpdateCalls++;
    return availableRelease;
  }
}

class _PendingLibrarySync extends Fake implements LibraryService {
  final sync = Completer<void>();
  int syncCalls = 0;

  @override
  final syncStatus = ValueNotifier(const LibrarySyncStatus());

  @override
  Stream<List<LibraryEntry>> watchEntriesFromDb() => const Stream.empty();

  @override
  Future<void> performInitialSyncIfNeeded() {
    syncCalls++;
    return sync.future;
  }

  @override
  Future<bool> isLibraryIncomplete() async => false;
}

class MockMetadataService extends Fake implements MetadataService {
  int refreshCalls = 0;

  @override
  Future<void> refreshInBackground() async {
    refreshCalls++;
  }
}

class _HeldLogoPreferenceStore extends InMemorySharedPreferencesStore {
  _HeldLogoPreferenceStore(super.data) : super.withData();

  static const matchKey = 'flutter.${SettingsKeys.matchLogoToAccent}';
  static const manualKey = 'flutter.${SettingsKeys.manualLogoColor}';
  final writes = <({String key, Object value, Completer<bool> release})>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == matchKey || key == manualKey) {
      final release = Completer<bool>();
      writes.add((key: key, value: value, release: release));
      if (!await release.future) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  setUpAll(prepareWidgetLibraryIdentity);
  late MockProfileAuthService auth;
  late MockUpdateService updates;
  late MockMetadataService metadata;

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
    await SettingsManager().init();

    await resetServiceLocator();
    setupServiceLocator();

    auth = MockProfileAuthService();
    getIt.unregister<ProfileAuthService>();
    getIt.registerSingleton<ProfileAuthService>(auth);

    updates = MockUpdateService();
    getIt.unregister<UpdateService>();
    getIt.registerSingleton<UpdateService>(updates);

    metadata = MockMetadataService();
    getIt.unregister<MetadataService>();
    getIt.registerSingleton<MetadataService>(metadata);
  });

  testWidgets('bottom tab changes release search focus and retain the query', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await SettingsManager().setHasCompletedOnboarding(true);
    await tester.pumpWidget(const MangaBakaApp());
    await tester.pump();
    MainScreen.setTabIndex(NavTabs.library);
    await tester.pump();
    final library = LibraryScreen.libraryScreenKey.currentState!;
    library.enterSearchMode();
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Retained');
    expect(library.searchFocusNode.hasFocus, isTrue);
    MainScreen.setTabIndex(NavTabs.home);
    await tester.pump();
    expect(library.searchFocusNode.hasFocus, isFalse);
    MainScreen.setTabIndex(NavTabs.library);
    await tester.pump();
    expect(library.searchFocusNode.hasFocus, isFalse);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'Retained',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('App smoke test shows onboarding without an update check', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MangaBakaApp());
    await tester.pump();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(EirenYuStartup), findsNothing);
    expect(updates.shouldPromptCalls, 0);
    expect(updates.checkForUpdateCalls, 0);
    expect(metadata.refreshCalls, 1);

    // Completing onboarding during this launch must not retroactively schedule
    // the launch-only update check.
    await SettingsManager().setHasCompletedOnboarding(true);
    await tester.pump();
    expect(updates.shouldPromptCalls, 0);
    expect(updates.checkForUpdateCalls, 0);
  });

  testWidgets(
    'landscape navigation branding follows Appearance live through navigation and reload',
    (tester) async {
      final settings = SettingsManager();
      await settings.setHasCompletedOnboarding(true);
      await settings.setLandscapeAppBarPosition(LandscapeAppBarPosition.top);
      final landscape =
          settings.landscapeAppBarPosition == LandscapeAppBarPosition.top;
      DesktopLayout.debugOverride = false;
      DesktopWindowFrame.debugOverride = false;
      tester.view.physicalSize = landscape
          ? const Size(844, 390)
          : const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      dispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(() {
        DesktopLayout.debugOverride = null;
        DesktopWindowFrame.debugOverride = null;
        tester.view.reset();
        dispatcher.clearAccessibilityFeaturesTestValue();
        dispatcher.clearPlatformBrightnessTestValue();
      });

      const warmupKey = Key('home-logo-warmup');
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox(key: warmupKey)),
      );
      final context = tester.element(find.byKey(warmupKey));
      await tester.runAsync(
        () => Future.wait([
          precacheImage(EirenYuMark.symbolImage, context),
          precacheImage(EirenYuMark.dotImage, context),
        ]),
      );
      const captureKey = Key('home-logo-capture');
      await tester.pumpWidget(
        const RepaintBoundary(key: captureKey, child: MangaBakaApp()),
      );
      await tester.pumpAndSettle();
      final home = find.byType(HomeScreen, skipOffstage: false);
      expect(home, findsOneWidget);
      final brandHost = landscape ? find.byType(MainTopNavBar) : home;
      final mark = find.descendant(
        of: brandHost,
        matching: find.byType(EirenYuMark, skipOffstage: false),
        skipOffstage: false,
      );
      if (landscape) {
        expect(
          find.descendant(of: home, matching: find.byType(EirenYuMark)),
          findsNothing,
        );
      }
      final mountedMark = tester.element(mark);
      final preview = find.byKey(const Key('appearance_logo_preview'));
      RenderImage layer(Finder mark, int index) =>
          tester.renderObject<RenderImage>(
            find
                .descendant(
                  of: mark,
                  matching: find.byType(RawImage, skipOffstage: false),
                  skipOffstage: false,
                )
                .at(index),
          );
      final symbol = layer(mark, 0);

      void expectBrand(Color tint, {bool dialogOpen = true}) {
        expect(tester.element(mark), same(mountedMark));
        expect(mountedMark.logoColor, tint);
        expect(layer(mark, 0), same(symbol));
        expect(symbol.color, tint);
        expect(layer(mark, 1).color, isNull);
        if (dialogOpen) expect(layer(preview, 0).color, tint);
        if (landscape) {
          final frame = mountedMark.findAncestorWidgetOfExactType<Container>()!;
          expect(
            (frame.decoration! as BoxDecoration).color,
            tint.withValues(alpha: 0.1),
          );
        }
      }

      Future<void> expectPaintedMark(Color tint) async {
        final frame = find.byKey(captureKey);
        final origin = tester.getTopLeft(mark) - tester.getTopLeft(frame);
        final boundary = tester.renderObject<RenderRepaintBoundary>(frame);
        await tester.runAsync(() async {
          const scale = 2;
          final image = await boundary.toImage(pixelRatio: scale.toDouble());
          try {
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final left = (origin.dx * scale).floor();
            final top = (origin.dy * scale).floor();
            final markPixels = <int>{
              for (var y = 0; y < 28 * scale; y++)
                for (var x = 0; x < 28 * scale; x++)
                  pixels.getUint32(((top + y) * image.width + left + x) * 4),
            };
            // Sample opaque interiors without depending on edge antialiasing.
            expect(
              markPixels,
              contains(((tint.toARGB32() & 0xFFFFFF) << 8) | 255),
            );
            expect(markPixels, contains(0xF7F8FCFF));
          } finally {
            image.dispose();
          }
        });
      }

      Future<void> tapControl(String key, {bool settle = true}) async {
        final control = find.byKey(Key(key));
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        await tester.tap(control);
        if (settle) await tester.pumpAndSettle();
      }

      Future<void> openAppearance() async {
        await tester.tap(
          find.descendant(
            of: brandHost,
            matching: find.byIcon(Icons.settings_outlined),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('APPEARANCE'));
        await tester.pumpAndSettle();
      }

      Future<void> closeSettings() async {
        if (landscape) {
          await tester.tap(
            find.descendant(
              of: find.byType(SettingsDialog),
              matching: find.byIcon(Icons.close),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SettingsDialog), findsNothing);
        } else {
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          navigator.pop();
          await tester.pumpAndSettle();
          navigator.pop();
          await tester.pumpAndSettle();
        }
      }

      await openAppearance();
      expectBrand(EirenYuPalette.dark.accent);
      final nord = ThemePresets.byId('nord')!.dark!.accent;
      final catppuccin = ThemePresets.byId('catppuccin')!.light!.accent;
      await tapControl('appearance_preset_dark_nord');
      expectBrand(nord);

      await tapControl('appearance_logo_match');
      await tapControl('appearance_logo_swatch_12');
      expectBrand(EirenYuPalette.horizonBlue);
      await tapControl('appearance_logo_match');
      expectBrand(nord);
      await tapControl('appearance_mode_light');
      expectBrand(EirenYuPalette.light.accent);
      await tapControl('appearance_preset_light_catppuccin');
      expectBrand(catppuccin);

      await tapControl('appearance_custom_accent');
      tester
          .widget<Slider>(find.byKey(const Key('appearance_picker_saturation')))
          .onChanged!(0);
      tester
          .widget<Slider>(find.byKey(const Key('appearance_picker_value')))
          .onChanged!(1);
      await tester.pumpAndSettle();
      await tapControl('appearance_picker_apply');
      expect(settings.accentOverride, 0xFFFFFFFF);
      expectBrand(const Color(0xFFFFFFFF));

      await tapControl('appearance_accent_default');
      await tapControl('appearance_mode_system');
      expectBrand(catppuccin);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expectBrand(nord);

      await tapControl('appearance_logo_match');
      expectBrand(EirenYuPalette.horizonBlue);
      await closeSettings();
      expectBrand(EirenYuPalette.horizonBlue, dialogOpen: false);
      await expectPaintedMark(EirenYuPalette.horizonBlue);

      final nav = find.byType(landscape ? MainTopNavBar : MbBottomNav);
      Future<void> selectTab(IconData icon) async {
        final tab = find.descendant(of: nav, matching: find.byIcon(icon));
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
      }

      await selectTab(MbIcons.compass);
      expect(home.hitTestable(), findsNothing);
      await settings.setMatchLogoToAccent(true);
      await tester.pumpAndSettle();
      await selectTab(MbIcons.house);
      expect(home.hitTestable(), findsOneWidget);
      expectBrand(nord, dialogOpen: false);
      await expectPaintedMark(nord);

      final originalStore = SharedPreferencesStorePlatform.instance;
      final store = _HeldLogoPreferenceStore(await originalStore.getAll());
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = originalStore,
      );
      const matchControl = 'appearance_logo_match';
      const finalSwatch = 'appearance_logo_swatch_11';
      const finalColor = EirenYuPalette.twilightLavender;

      void expectManualSelection(String swatch) {
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key(matchControl)))
              .value,
          isFalse,
        );
        expect(
          tester.widget<ChoiceChip>(find.byKey(Key(swatch))).selected,
          isTrue,
        );
      }

      await openAppearance();
      await tapControl(matchControl, settle: false);
      await tester.pump();
      expectBrand(EirenYuPalette.horizonBlue);
      await closeSettings();
      expectBrand(EirenYuPalette.horizonBlue, dialogOpen: false);
      expect(store.writes.single.value, isFalse);
      expect((await store.getAll())[_HeldLogoPreferenceStore.matchKey], isTrue);

      await openAppearance();
      expectManualSelection('appearance_logo_swatch_12');
      await tapControl(matchControl);
      expectBrand(nord);
      await tapControl(matchControl);
      await tapControl('appearance_logo_swatch_10');
      await tapControl(finalSwatch, settle: false);
      await closeSettings();
      expectBrand(finalColor, dialogOpen: false);
      await expectPaintedMark(finalColor);
      await openAppearance();
      expectManualSelection(finalSwatch);
      await closeSettings();

      // An older platform write must finish before another write to its key
      // starts. A different preference can save independently.
      expect(store.writes.map((write) => write.key), [
        _HeldLogoPreferenceStore.matchKey,
        _HeldLogoPreferenceStore.manualKey,
      ]);
      for (var index = 0; index < store.writes.length; index++) {
        final write = store.writes[index];
        expect(
          store.writes.skip(index + 1).any((next) => next.key == write.key),
          isFalse,
        );
        // A rejected intermediate swatch must not block its replacement.
        write.release.complete(
          write.value != EirenYuPalette.crimsonMoon.toARGB32(),
        );
        await tester.pump();
        expectBrand(finalColor, dialogOpen: false);
      }

      // Re-read from the platform store instead of the plugin's eager cache.
      await tester.pumpWidget(const SizedBox.shrink());
      SettingsManager.resetForTesting();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await settings.init();
      await tester.pumpWidget(const MangaBakaApp());
      await tester.pumpAndSettle();
      expect(layer(mark, 0).color, finalColor);
      expect(layer(mark, 1).color, isNull);
      await openAppearance();
      expectManualSelection(finalSwatch);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('portrait Home keeps its original header without an emblem', (
    tester,
  ) async {
    await SettingsManager().setHasCompletedOnboarding(true);
    DesktopLayout.debugOverride = false;
    DesktopWindowFrame.debugOverride = false;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      DesktopLayout.debugOverride = null;
      DesktopWindowFrame.debugOverride = null;
      tester.view.reset();
    });
    await tester.pumpWidget(const MangaBakaApp());
    await tester.pumpAndSettle();
    final home = find.byType(HomeScreen);
    expect(home, findsOneWidget);
    expect(
      find.descendant(of: home, matching: find.byType(EirenYuMark)),
      findsNothing,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  test(
    'resetForTesting does not retain an earlier preference write queue',
    () async {
      final originalStore = SharedPreferencesStorePlatform.instance;
      final store = _HeldLogoPreferenceStore(await originalStore.getAll());
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = originalStore,
      );
      final settings = SettingsManager();
      final first = settings.setMatchLogoToAccent(false);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(1));

      SettingsManager.resetForTesting();
      final second = settings.setMatchLogoToAccent(false);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(2));

      for (final write in store.writes) {
        write.release.complete(true);
      }
      await Future.wait([first, second]);
    },
  );

  testWidgets(
    'mounted app mark follows logo settings and platform brightness',
    (tester) async {
      DesktopLayout.debugOverride = true;
      tester.view.physicalSize = const Size(1040, 720);
      tester.view.devicePixelRatio = 1;
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(() {
        DesktopLayout.debugOverride = null;
        tester.view.reset();
        dispatcher.clearPlatformBrightnessTestValue();
      });

      await tester.pumpWidget(const MangaBakaApp());
      await tester.pump();
      final mark = find.byType(EirenYuMark);
      final mountedMark = tester.element(mark);
      final layers = find.descendant(of: mark, matching: find.byType(Image));
      Color? tint() => tester.widget<Image>(layers.first).color;

      final settings = SettingsManager();
      expect(tint(), EirenYuPalette.dark.accent);
      await settings.setThemeMode(AppThemeMode.light);
      await tester.pump();
      expect(tint(), EirenYuPalette.light.accent);
      await settings.setThemeMode(AppThemeMode.system);
      await tester.pump();
      expect(tint(), EirenYuPalette.dark.accent);
      dispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      expect(tint(), EirenYuPalette.light.accent);

      const custom = Color(0xFFFAFCFE);
      await settings.setAccentOverride(custom.toARGB32());
      await tester.pump();
      expect(tint(), custom);
      await settings.setMatchLogoToAccent(false);
      await tester.pump();
      expect(tint(), EirenYuPalette.crimsonMoon);
      await settings.setManualLogoColor(EirenYuPalette.horizonBlue.toARGB32());
      await tester.pump();
      expect(tint(), EirenYuPalette.horizonBlue);
      expect(tester.element(mark), same(mountedMark));
      expect(tester.widget<Image>(layers.last).color, isNull);
      expect(metadata.refreshCalls, 1);
    },
  );

  testWidgets('checks for updates once after the first real app frame', (
    WidgetTester tester,
  ) async {
    await SettingsManager().setHasCompletedOnboarding(true);

    await tester.pumpWidget(const MangaBakaApp());
    await tester.pump();

    expect(updates.shouldPromptCalls, 1);
    expect(updates.checkForUpdateCalls, 1);
    expect(metadata.refreshCalls, 1);

    await SettingsManager().setShowTooltips(false);
    auth.notifyForTesting();
    await tester.pump();

    expect(updates.shouldPromptCalls, 1);
    expect(updates.checkForUpdateCalls, 1);
    expect(metadata.refreshCalls, 1);
  });

  testWidgets('iOS launch uses the saved manual color once on onboarding', (
    tester,
  ) async {
    final settings = SettingsManager();
    await settings.setMatchLogoToAccent(false);
    await settings.setManualLogoColor(EirenYuPalette.horizonBlue.toARGB32());
    await settings.setAccentOverride(0xFFFAFCFE);
    final prefs = await SharedPreferences.getInstance();
    SettingsManager.resetForTesting();
    await prefs.reload();
    await settings.init();
    await _pumpIOSRoot(tester);

    final artwork = find.byType(EirenYuLaunchArtwork);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(tester.widget<EirenYuLaunchArtwork>(artwork).progress, 0);
    expect(metadata.refreshCalls, 1);
    expect(updates.checkForUpdateCalls, 0);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 540));
    final middle = tester.widget<EirenYuLaunchArtwork>(artwork);
    expect(middle.progress, inExclusiveRange(0, 1));
    expect(middle.color, EirenYuPalette.horizonBlue);

    await tester.pump(const Duration(milliseconds: 800));
    expect(artwork, findsNothing);
    await settings.setHasCompletedOnboarding(true);
    await tester.pump();
    expect(find.byType(MainScreen), findsOneWidget);
    expect(
      tester.widget<MbBottomNav>(find.byType(MbBottomNav)).selectedIndex,
      0,
    );

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settings.setMatchLogoToAccent(true);
    auth.notifyForTesting();
    await tester.pump();
    final bottomNav = find.byType(MbBottomNav);
    await tester.tap(
      find.descendant(of: bottomNav, matching: find.byIcon(MbIcons.compass)),
    );
    await tester.pump();
    expect(tester.widget<MbBottomNav>(bottomNav).selectedIndex, 2);
    expect(artwork, findsNothing);
    expect(metadata.refreshCalls, 1);
    expect(updates.checkForUpdateCalls, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('cold iOS reveal uses the saved matching custom accent', (
    tester,
  ) async {
    final settings = SettingsManager();
    await settings.setHasCompletedOnboarding(true);
    await settings.setMatchLogoToAccent(true);
    await settings.setAccentOverride(0xFF123456);
    final prefs = await SharedPreferences.getInstance();
    SettingsManager.resetForTesting();
    await prefs.reload();
    await settings.init();
    await _pumpIOSRoot(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 540));
    expect(find.byType(MainScreen), findsOneWidget);
    final artwork = tester.widget<EirenYuLaunchArtwork>(
      find.byType(EirenYuLaunchArtwork),
    );
    expect(artwork.color, const Color(0xFF123456));
    expect(artwork.progress, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 800));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'cold first-install onboarding completes the reveal after slow assets',
    (tester) async {
      _configureIOSRoot(tester);
      final assets = <(ImageProvider<Object>, AssetImage)>[
        (
          const ResizeImage(
            EirenYuLaunchArtwork.neutralImage,
            width: 313,
            height: 313,
          ),
          EirenYuLaunchArtwork.neutralImage,
        ),
        (EirenYuMark.symbolImage, EirenYuMark.symbolImage),
        (EirenYuMark.dotImage, EirenYuMark.dotImage),
      ];
      final coldImages = (await tester.runAsync(() async {
        // Use official PNGs, but leave their image-cache entries pending until
        // the test clock reaches the simulated cold-decode completion times.
        final results = <(Object, ImageInfo)>[];
        for (final (provider, source) in assets) {
          final key = await provider.obtainKey(
            ImageConfiguration(bundle: rootBundle, devicePixelRatio: 1),
          );
          final bytes = await rootBundle.load(source.assetName);
          final codec = await ui.instantiateImageCodec(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            targetWidth: provider is ResizeImage ? provider.width : null,
            targetHeight: provider is ResizeImage ? provider.height : null,
          );
          try {
            results.add((
              key,
              ImageInfo(image: (await codec.getNextFrame()).image),
            ));
          } finally {
            codec.dispose();
          }
        }
        return results;
      }))!;
      final cache = tester.binding.imageCache;
      final decoded = <Completer<ImageInfo>>[];
      for (final (key, _) in coldImages) {
        cache.evict(key);
        final result = Completer<ImageInfo>();
        decoded.add(result);
        cache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(result.future),
        );
        addTearDown(() => cache.evict(key));
      }

      tester.binding.resetFirstFrameSent();
      await tester.pumpWidget(const MangaBakaApp());
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(tester.binding.sendFramesToEngine, isFalse);
      expect(metadata.refreshCalls, 1);
      expect(updates.checkForUpdateCalls, 0);

      final artwork = find.byType(EirenYuLaunchArtwork);
      decoded[0].complete(coldImages[0].$2);
      await tester.pump();
      await tester.pump();
      expect(tester.binding.sendFramesToEngine, isTrue);
      expect(tester.widget<EirenYuLaunchArtwork>(artwork).progress, 0);

      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<EirenYuLaunchArtwork>(artwork).progress, 0);
      decoded[1].complete(coldImages[1].$2);
      decoded[2].complete(coldImages[2].$2);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 540));
      expect(
        tester.widget<EirenYuLaunchArtwork>(artwork).progress,
        inExclusiveRange(0, 1),
      );
      await tester.pump(const Duration(milliseconds: 620));
      expect(tester.widget<EirenYuLaunchArtwork>(artwork).progress, 1);
      await tester.pump(const Duration(milliseconds: 180));
      expect(artwork, findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(metadata.refreshCalls, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('returning signed-out iOS launch still reveals over Home', (
    tester,
  ) async {
    await SettingsManager().setHasCompletedOnboarding(true);
    await _pumpIOSRoot(tester);
    final artwork = find.byType(EirenYuLaunchArtwork);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(tester.widget<EirenYuLaunchArtwork>(artwork).progress, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1340));
    expect(artwork, findsNothing);
    expect(
      tester.widget<MbBottomNav>(find.byType(MbBottomNav)).selectedIndex,
      0,
    );
    expect(metadata.refreshCalls, 1);
    expect(updates.checkForUpdateCalls, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final startPage in [AppStartPage.home, AppStartPage.browse]) {
    testWidgets(
      'authenticated iOS launch on ${startPage.name} defers only the dialog',
      (tester) async {
        const custom = Color(0xFFFAFCFE);
        final settings = SettingsManager();
        await settings.setThemeMode(AppThemeMode.light);
        await settings.setAccentOverride(custom.toARGB32());
        await settings.setDefaultStartPage(startPage);
        auth.isLoggedIn = true;
        final library = _PendingLibrarySync();
        await getIt.unregister<LibraryService>();
        getIt.registerSingleton<LibraryService>(library);
        updates.availableRelease = const AppRelease(
          tagName: 'v99.0.0',
          name: 'Test release',
          body: '',
          htmlUrl: 'https://github.com/Brainer-00/MangaBaka-IOS/releases',
          draft: false,
          prerelease: false,
          assets: [],
        );

        await _pumpIOSRoot(tester);
        final artwork = find.byType(EirenYuLaunchArtwork);
        expect(artwork, findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
        expect(
          tester.widget<MbBottomNav>(find.byType(MbBottomNav)).selectedIndex,
          startPage.index,
        );
        expect(library.syncCalls, 1);
        expect(metadata.refreshCalls, 1);
        expect(updates.checkForUpdateCalls, 1);
        expect(find.byType(UpdateDialog), findsNothing);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.widget<EirenYuLaunchArtwork>(artwork).color, custom);
        await settings.setAccentOverride(0xFF123456);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.widget<EirenYuLaunchArtwork>(artwork).color, custom);
        expect(find.byType(UpdateDialog), findsNothing);

        await tester.pump(const Duration(milliseconds: 640));
        await tester.pump();
        expect(artwork, findsNothing);
        expect(find.byType(UpdateDialog), findsOneWidget);
        expect(library.sync.isCompleted, isFalse);
        expect(updates.shouldPromptCalls, 1);
        expect(updates.checkForUpdateCalls, 1);
        library.sync.complete();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        library.syncStatus.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets('desktop app root skips the startup cover', (tester) async {
    await tester.pumpWidget(const MangaBakaApp());
    expect(find.byType(EirenYuStartup), findsNothing);
    expect(metadata.refreshCalls, 1);
  }, variant: TargetPlatformVariant.desktop());
}

void _configureIOSRoot(WidgetTester tester) {
  DesktopLayout.debugOverride = false;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    DesktopLayout.debugOverride = null;
    tester.view.reset();
  });
}

Future<void> _pumpIOSRoot(WidgetTester tester) async {
  _configureIOSRoot(tester);

  // Decode real assets outside Flutter's fake clock, then drive the mounted
  // app's launch and fade exclusively with deterministic frame pumps.
  const warmup = Key('startup-image-warmup');
  await tester.pumpWidget(const MaterialApp(home: SizedBox(key: warmup)));
  final context = tester.element(find.byKey(warmup));
  await tester.runAsync(
    () => Future.wait([
      precacheImage(
        const ResizeImage(
          EirenYuLaunchArtwork.neutralImage,
          width: 313,
          height: 313,
        ),
        context,
      ),
      precacheImage(EirenYuMark.symbolImage, context),
      precacheImage(EirenYuMark.dotImage, context),
    ]),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  tester.binding.resetFirstFrameSent();
  await tester.pumpWidget(const MangaBakaApp());
  await tester.pump();
}
