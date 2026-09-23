import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/screens/privacy_legal_screen.dart';
import 'package:mangabaka_app/features/profile/screens/settings_screen.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedOutAuth extends Fake implements ProfileAuthService {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<ProfileAuthService>(_SignedOutAuth());
    LocalizationService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
    await LocalizationService().init();
    DesktopLayout.debugOverride = false;
  });

  tearDown(() async {
    DesktopLayout.debugOverride = null;
    await resetServiceLocator();
  });

  testWidgets('PrivacyLegalScreen renders its title and privacy summary', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyLegalScreen()));

    expect(find.text('PRIVACY & LEGAL'), findsOneWidget);
    expect(find.text('PRIVACY AT A GLANCE'), findsOneWidget);
    expect(find.textContaining('MangaBaka OAuth'), findsOneWidget);
  });

  testWidgets('signed-out settings opens Privacy & Legal', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('PRIVACY & LEGAL'), findsOneWidget);
    await tester.tap(find.text('PRIVACY & LEGAL'));
    await tester.pumpAndSettle();

    expect(find.text('PRIVACY AT A GLANCE'), findsOneWidget);
  });

  testWidgets('landscape settings keeps Privacy & Legal in the dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SettingsScreen.show(context),
              child: const Text('Open Settings'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PRIVACY & LEGAL'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('PRIVACY AT A GLANCE'), findsOneWidget);
  });

  testWidgets('open-source licenses action opens Flutter license UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PrivacyLegalScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('OPEN-SOURCE LICENSES'));
    await tester.tap(find.text('OPEN-SOURCE LICENSES'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
