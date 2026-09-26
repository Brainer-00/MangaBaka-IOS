import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_keys.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/widgets/design/mb_nav.dart';
import 'package:mangabaka_app/features/browse/screens/browse_screen.dart';
import 'package:mangabaka_app/features/home/screens/home_screen.dart';
import 'package:mangabaka_app/features/navigation/screens/main_screen.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockProfileAuthService extends Fake implements ProfileAuthService {
  @override
  bool get isLoggedIn => false;
  @override
  MbProfile? get cachedProfile => null;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

void main() {
  setUp(() async {
    await resetServiceLocator();
    setupServiceLocator();

    // Replace auth with mock to avoid real login logic in tests
    getIt.unregister<ProfileAuthService>();
    getIt.registerSingleton<ProfileAuthService>(MockProfileAuthService());
  });

  Future<void> loadSettings([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    SettingsManager.resetForTesting();
    await SettingsManager().init();
  }

  Future<void> pumpMainScreen(WidgetTester tester) async {
    // Set mobile size to ensure the bottom bar is used instead of the rail
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(MaterialApp(home: MainScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('MainScreen starts on Home tab by default', (
    WidgetTester tester,
  ) async {
    await loadSettings();
    await pumpMainScreen(tester);

    expect(find.byType(HomeScreen), findsOneWidget);

    final navBar = tester.widget<MbBottomNav>(find.byType(MbBottomNav));
    expect(navBar.selectedIndex, 0);
  });

  testWidgets('MainScreen respects an explicitly saved start page', (
    WidgetTester tester,
  ) async {
    await loadSettings({
      SettingsKeys.defaultStartPage: AppStartPage.browse.index,
    });
    await pumpMainScreen(tester);

    expect(find.byType(BrowseScreen), findsOneWidget);

    final navBar = tester.widget<MbBottomNav>(find.byType(MbBottomNav));
    expect(navBar.selectedIndex, 2);
  });
}
