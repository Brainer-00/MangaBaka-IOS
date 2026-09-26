import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/features/navigation/screens/onboarding_screen.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/updates/models/app_release.dart';
import 'package:mangabaka_app/features/updates/services/update_service.dart';
import 'package:mangabaka_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockProfileAuthService extends Fake implements ProfileAuthService {
  final List<VoidCallback> _listeners = [];

  @override
  bool get isLoggedIn => false;
  @override
  final ValueNotifier<bool> awaitingBrowser = ValueNotifier(false);
  @override
  MbProfile? get cachedProfile => null;
  @override
  Future<void> init() async {}
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

  @override
  bool shouldPrompt() {
    shouldPromptCalls++;
    return true;
  }

  @override
  Future<AppRelease?> checkForUpdate() async {
    checkForUpdateCalls++;
    return null;
  }
}

void main() {
  late MockProfileAuthService auth;
  late MockUpdateService updates;

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
  });

  testWidgets('App smoke test shows onboarding without an update check', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MangaBakaApp());
    await tester.pump();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(updates.shouldPromptCalls, 0);
    expect(updates.checkForUpdateCalls, 0);

    // Completing onboarding during this launch must not retroactively schedule
    // the launch-only update check.
    await SettingsManager().setHasCompletedOnboarding(true);
    await tester.pump();
    expect(updates.shouldPromptCalls, 0);
    expect(updates.checkForUpdateCalls, 0);
  });

  testWidgets('checks for updates once after the first real app frame', (
    WidgetTester tester,
  ) async {
    await SettingsManager().setHasCompletedOnboarding(true);

    await tester.pumpWidget(const MangaBakaApp());
    await tester.pump();

    expect(updates.shouldPromptCalls, 1);
    expect(updates.checkForUpdateCalls, 1);

    await SettingsManager().setShowTooltips(false);
    auth.notifyForTesting();
    await tester.pump();

    expect(updates.shouldPromptCalls, 1);
    expect(updates.checkForUpdateCalls, 1);
  });
}
