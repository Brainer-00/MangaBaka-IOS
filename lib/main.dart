import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangabaka_app/core/app_bootstrap.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_window_frame.dart';
import 'package:mangabaka_app/features/navigation/screens/main_screen.dart';
import 'package:mangabaka_app/features/navigation/screens/onboarding_screen.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
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
  /// The theme is rebuilt only when [SettingsManager.showTooltips] changes —
  /// it is baked into the tooltip theme — rather than on every notification
  /// from the merged listenable, which fires for every setting there is.
  ThemeData? _cachedTheme;
  bool? _lastShowTooltips;

  bool _updateCheckScheduled = false;

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
  }

  ThemeData _themeFor(bool showTooltips) {
    if (_cachedTheme != null && _lastShowTooltips == showTooltips) {
      return _cachedTheme!;
    }
    _lastShowTooltips = showTooltips;
    return _cachedTheme = AppTheme.build(showTooltips: showTooltips);
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        SettingsManager(),
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
            theme: _themeFor(settings.showTooltips),
            builder: (context, child) => DesktopWindowFrame(
              child: BrowserSignInPrompt(child: AppShortcuts(child: child!)),
            ),
            home: AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppTheme.systemOverlay,
              child: isPastOnboarding ? MainScreen() : const OnboardingScreen(),
            ),
          ),
        );
      },
    );
  }
}
