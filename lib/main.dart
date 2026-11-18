import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangabaka_app/core/app_bootstrap.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/theme_controller.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_window_frame.dart';
import 'package:mangabaka_app/features/navigation/screens/main_screen.dart';
import 'package:mangabaka_app/features/navigation/screens/onboarding_screen.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/features/profile/widgets/login/browser_sign_in_prompt.dart';
import 'package:mangabaka_app/features/updates/services/update_service.dart';
import 'package:mangabaka_app/features/updates/widgets/update_dialog.dart';
import 'package:mangabaka_app/shared/widgets/app_shortcuts.dart';

Future<void> main() async {
  await AppBootstrap.run();
  runApp(const MangaBakaApp());
}

/// The app root: chooses between onboarding and the main shell, schedules the
/// launch update check, and owns the theme.
class MangaBakaApp extends StatefulWidget {
  const MangaBakaApp({super.key});

  @override
  State<MangaBakaApp> createState() => _MangaBakaAppState();
}

class _MangaBakaAppState extends State<MangaBakaApp> {
  final ThemeController _themes = ThemeController()..init();

  /// The theme is rebuilt only when [SettingsManager.showTooltips] changes —
  /// it is baked into the tooltip theme — rather than on every notification
  /// from the merged listenable, which fires for every setting there is.
  final Map<Brightness, (MbPalette, bool, ThemeData)> _themeCache = {};

  bool _updateCheckScheduled = false;
  bool _metadataRefreshScheduled = false;

  @override
  void initState() {
    super.initState();

    final settings = SettingsManager();
    final isPastOnboarding =
        settings.hasCompletedOnboarding ||
        getIt<ProfileAuthService>().isLoggedIn;
    if (isPastOnboarding) {
      _scheduleUpdateCheckAfterFirstFrame();
    }
    _scheduleMetadataRefreshAfterFirstFrame();
  }

  ThemeData _themeFor(MbPalette palette, bool showTooltips) {
    final cached = _themeCache[palette.brightness];
    if (cached != null && cached.$1 == palette && cached.$2 == showTooltips) {
      return cached.$3;
    }
    final theme = AppTheme.build(showTooltips: showTooltips, palette: palette);
    _themeCache[palette.brightness] = (palette, showTooltips, theme);
    return theme;
  }

  @override
  void dispose() {
    _themes.dispose();
    super.dispose();
  }

  /// Checks GitHub for a newer release and, if found, shows the update dialog.
  /// Runs at most once per app launch.
  Future<void> _checkForAppUpdate() async {
    final service = getIt<UpdateService>();
    if (!service.shouldPrompt()) return;
    final release = await service.checkForUpdate();
    if (release == null) return;
    final context = AppConstants.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await UpdateDialog.show(context, release);
  }

  void _scheduleUpdateCheckAfterFirstFrame() {
    if (_updateCheckScheduled) return;
    _updateCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkForAppUpdate();
    });
  }

  void _scheduleMetadataRefreshAfterFirstFrame() {
    if (_metadataRefreshScheduled) return;
    _metadataRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) getIt<MetadataService>().refreshInBackground();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SettingsManager(),
        _themes,
        getIt<ProfileAuthService>(),
      ]),
      builder: (context, _) {
        final settings = SettingsManager();
        // Signing in implies onboarding is done, so a returning user who
        // cleared their settings does not get sent back through it.
        final isPastOnboarding =
            settings.hasCompletedOnboarding ||
            getIt<ProfileAuthService>().isLoggedIn;

        return ExcludeSemantics(
          // The Windows web-view component emits a platform accessibility
          // warning that has no fix at the widget level.
          excluding: Platform.isWindows,
          child: MaterialApp(
            navigatorKey: AppConstants.navigatorKey,
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: _themeFor(_themes.lightPalette, settings.showTooltips),
            darkTheme: _themeFor(_themes.darkPalette, settings.showTooltips),
            themeMode: _themes.materialThemeMode,
            builder: (context, child) => LogoColorScope(
              color: _themes.currentLogoColor,
              child: DesktopWindowFrame(
                child: BrowserSignInPrompt(child: AppShortcuts(child: child!)),
              ),
            ),
            home: AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppTheme.overlayFor(_themes.current),
              child: isPastOnboarding ? MainScreen() : const OnboardingScreen(),
            ),
          ),
        );
      },
    );
  }
}
