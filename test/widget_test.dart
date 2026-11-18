import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/widgets/design/mb_nav.dart';
import 'package:mangabaka_app/core/widgets/design/eirenyu_mark.dart';
import 'package:mangabaka_app/core/widgets/design/mb_icons.dart';
import 'package:mangabaka_app/core/widgets/eirenyu_startup.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/navigation/screens/main_screen.dart';
import 'package:mangabaka_app/features/navigation/screens/onboarding_screen.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/features/updates/models/app_release.dart';
import 'package:mangabaka_app/features/updates/services/update_service.dart';
import 'package:mangabaka_app/features/updates/widgets/update_dialog.dart';
import 'package:mangabaka_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockProfileAuthService extends Fake implements ProfileAuthService {
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

void main() {
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

  testWidgets(
    'authenticated iOS launch keeps the saved tab and defers only the dialog',
    (tester) async {
      const custom = Color(0xFFFAFCFE);
      final settings = SettingsManager();
      await settings.setThemeMode(AppThemeMode.light);
      await settings.setAccentOverride(custom.toARGB32());
      await settings.setDefaultStartPage(AppStartPage.browse);
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
        2,
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

  testWidgets('desktop app root skips the startup cover', (tester) async {
    await tester.pumpWidget(const MangaBakaApp());
    expect(find.byType(EirenYuStartup), findsNothing);
    expect(metadata.refreshCalls, 1);
  }, variant: TargetPlatformVariant.desktop());
}

Future<void> _pumpIOSRoot(WidgetTester tester) async {
  DesktopLayout.debugOverride = false;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    DesktopLayout.debugOverride = null;
    tester.view.reset();
  });

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
