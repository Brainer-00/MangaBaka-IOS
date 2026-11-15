import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_surfaces.dart';
import 'package:mangabaka_app/features/navigation/screens/onboarding_screen.dart';
import 'package:mangabaka_app/features/navigation/widgets/onboarding/camera_permission_page.dart';
import 'package:mangabaka_app/features/navigation/widgets/onboarding/content_preferences_page.dart';
import 'package:mangabaka_app/features/navigation/widgets/onboarding/language_page.dart';
import 'package:mangabaka_app/features/navigation/widgets/onboarding/login_page.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends Fake implements ProfileAuthService {
  int loginCalls = 0;
  @override
  bool get isLoggedIn => false;
  @override
  Future<void> login() async => loginCalls++;
}

Widget _app(MbPalette colors, Widget child) => MaterialApp(
  theme: AppTheme.build(showTooltips: true, palette: colors),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(body: child),
);

Container _card(WidgetTester tester, String label) => tester.widget<Container>(
  find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
);

Color _fill(Container card) => (card.decoration! as BoxDecoration).color!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  setUp(() async {
    await resetServiceLocator();
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    LocalizationService.resetForTesting();
    await SettingsManager().init();
    await LocalizationService().init();
    getIt.registerSingleton<LoggingService>(LoggingService());
    auth = _Auth();
    getIt.registerSingleton<ProfileAuthService>(auth);
    DesktopLayout.debugOverride = false;
  });
  tearDown(() async {
    DesktopLayout.debugOverride = null;
    await resetServiceLocator();
  });

  final palettes = <MbPalette>[
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    ThemePresets.byId('catppuccin')!.light!,
    EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  ];

  testWidgets('language cards keep selected and unselected contrast', (
    tester,
  ) async {
    for (final colors in palettes) {
      await tester.pumpWidget(_app(colors, const LanguagePage()));
      final selected = _card(tester, 'English');
      final unselected = _card(tester, 'Deutsch');
      final tinted = Color.alphaBlend(
        colors.accent.withValues(alpha: 0.1),
        colors.background,
      );
      expect(_fill(selected), tinted);
      expect(_fill(unselected), colors.surface);
      final english = tester.widget<Text>(find.text('English'));
      expect(
        MbPalette.contrastRatio(english.style!.color!, tinted),
        greaterThanOrEqualTo(4.5),
      );
      final check = tester.widget<Icon>(
        find.byIcon(Icons.check_circle_rounded),
      );
      expect(
        MbPalette.contrastRatio(check.color!, tinted),
        greaterThanOrEqualTo(3),
      );
      expect(
        MbPalette.contrastRatio(
          (selected.decoration! as BoxDecoration).border!.top.color,
          tinted,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(LocalizationService().currentLanguage, 'de');
  });

  testWidgets('content cards and checkboxes retain minimum selection', (
    tester,
  ) async {
    final safe = LocalizationService().translate('safe');
    final erotica = LocalizationService().translate('erotica');
    for (final colors in palettes) {
      await tester.pumpWidget(_app(colors, const ContentPreferencesPage()));
      final selected = _card(tester, safe);
      final unselected = _card(tester, erotica);
      final tinted = Color.alphaBlend(
        colors.accent.withValues(alpha: 0.1),
        colors.background,
      );
      expect(_fill(selected), tinted);
      expect(_fill(unselected), colors.surface);
      final selectedText = tester.widget<Text>(find.text(safe));
      expect(
        MbPalette.contrastRatio(selectedText.style!.color!, tinted),
        greaterThanOrEqualTo(4.5),
      );
      final selectedBox = tester.widget<Checkbox>(find.byType(Checkbox).first);
      expect(selectedBox.value, isTrue);
      expect(
        MbPalette.contrastRatio(selectedBox.activeColor!, tinted),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text(safe));
    await tester.pump();
    expect(SettingsManager().contentPreferences, ['suggestive']);
    await tester.tap(find.text(LocalizationService().translate('suggestive')));
    await tester.pump();
    expect(SettingsManager().contentPreferences, ['suggestive']);
  });

  testWidgets('camera and login actions and connected badge stay readable', (
    tester,
  ) async {
    var cameraCalls = 0;
    var loginCalls = 0;
    for (final colors in palettes) {
      await tester.pumpWidget(
        _app(
          colors,
          CameraPermissionPage(onRequestPermission: () => cameraCalls++),
        ),
      );
      await tester.pumpAndSettle();
      final camera = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        MbPalette.contrastRatio(
          camera.style!.foregroundColor!.resolve({})!,
          camera.style!.backgroundColor!.resolve({})!,
        ),
        greaterThanOrEqualTo(4.5),
      );

      await tester.pumpWidget(
        _app(
          colors,
          LoginPage(
            isLoggingIn: false,
            isLoggedIn: false,
            onLogin: () => loginCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final login = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(login.onPressed, isNotNull);
      expect(
        MbPalette.contrastRatio(
          login.style!.foregroundColor!.resolve({})!,
          login.style!.backgroundColor!.resolve({})!,
        ),
        greaterThanOrEqualTo(4.5),
      );

      await tester.pumpWidget(
        _app(
          colors,
          LoginPage(
            isLoggingIn: true,
            isLoggedIn: false,
            onLogin: () => loginCalls++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final pending = tester.widget<FilledButton>(find.byType(FilledButton));
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      final disabledFill = pending.style!.backgroundColor!.resolve({
        WidgetState.disabled,
      })!;
      expect(pending.onPressed, isNull);
      expect(
        MbPalette.contrastRatio(spinner.valueColor!.value!, disabledFill),
        greaterThanOrEqualTo(3),
      );

      await tester.pumpWidget(
        _app(
          colors,
          LoginPage(
            isLoggingIn: false,
            isLoggedIn: true,
            onLogin: () => loginCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final badge = _card(
        tester,
        LocalizationService().translate('onboarding_connected'),
      );
      final badgeColor = _fill(badge);
      final label = tester.widget<Text>(
        find.text(LocalizationService().translate('onboarding_connected')),
      );
      expect(
        MbPalette.contrastRatio(label.style!.color!, badgeColor),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        MbPalette.contrastRatio(
          tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded)).color!,
          badgeColor,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    }
    expect(cameraCalls, 0);
    expect(loginCalls, 0);
    expect(auth.loginCalls, 0);
  });

  testWidgets('phone page and preferences survive a live palette change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: const OnboardingScreen(),
        ),
      ),
    );
    final l10n = LocalizationService();
    final next = l10n.translate('onboarding_next').toUpperCase();
    await tester.tap(find.text(next));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePage), findsOneWidget);
    await tester.tap(find.text(next));
    await tester.pumpAndSettle();
    expect(find.byType(ContentPreferencesPage), findsOneWidget);
    await tester.tap(find.text(l10n.translate('safe')));
    await tester.pump();
    expect(SettingsManager().contentPreferences, ['suggestive']);

    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(find.byType(ContentPreferencesPage), findsOneWidget);
    expect(SettingsManager().contentPreferences, ['suggestive']);
    final page = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(OnboardingScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(page.backgroundColor, EirenYuPalette.light.background);
    await tester.tap(find.text(l10n.translate('onboarding_back')));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePage), findsOneWidget);
    await tester.tap(find.text(next));
    await tester.pumpAndSettle();
    expect(find.byType(ContentPreferencesPage), findsOneWidget);
    expect(SettingsManager().hasCompletedOnboarding, isFalse);
    expect(auth.loginCalls, 0);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(700, 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop step colors update with camera step omitted', (
    tester,
  ) async {
    DesktopLayout.debugOverride = true;
    tester.view.physicalSize = const Size(1040, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CameraPermissionPage), findsNothing);
    expect(find.byType(DesktopSidePanel), findsOneWidget);
    final indicators = find.descendant(
      of: find.byType(DesktopSidePanel),
      matching: find.byType(AnimatedContainer),
    );
    expect(indicators, findsNWidgets(4));
    expect(
      (tester.widget<AnimatedContainer>(indicators.first).decoration!
              as BoxDecoration)
          .color,
      EirenYuPalette.dark.accentOn(EirenYuPalette.dark.background, minimum: 3),
    );
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(
      (tester.widget<AnimatedContainer>(indicators.first).decoration!
              as BoxDecoration)
          .color,
      EirenYuPalette.light.accentOn(
        EirenYuPalette.light.background,
        minimum: 3,
      ),
    );
    expect(find.byType(CameraPermissionPage), findsNothing);
    expect(auth.loginCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
