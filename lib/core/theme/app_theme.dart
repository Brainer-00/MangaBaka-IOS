import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

/// Material themes built from the resolved semantic palette.
class AppTheme {
  AppTheme._();

  /// Overlay style for the status and navigation bars.
  ///
  /// Applied both at startup (before any widget exists) and by an
  /// `AnnotatedRegion` around the app, which is what keeps it after a route
  /// or platform change resets it. Shared so the two cannot disagree.
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  );

  static void applySystemOverlay() =>
      SystemChrome.setSystemUIOverlayStyle(systemOverlay);

  static SystemUiOverlayStyle overlayFor(MbPalette palette) =>
      systemOverlay.copyWith(
        systemNavigationBarIconBrightness: palette.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarIconBrightness: palette.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      );

  /// Builds the theme.
  ///
  /// [showTooltips] is baked in rather than read at each call site: Flutter
  /// has no "off" for tooltips, so disabling them means switching every
  /// tooltip to manual triggering — a theme-level change, and the reason the
  /// caller caches the result and rebuilds it only when the setting changes.
  static ThemeData build({
    required bool showTooltips,
    required MbPalette palette,
  }) {
    final base = ThemeData(brightness: palette.brightness, useMaterial3: true);
    final textBase = palette.brightness == Brightness.dark
        ? Typography.material2021(platform: TargetPlatform.android).white
        : Typography.material2021(platform: TargetPlatform.android).black;

    return base.copyWith(
      textTheme: AppTypography.textTheme(textBase),
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: palette.brightness,
        surface: palette.surface,
        primary: palette.accent,
        onPrimary: palette.onAccent,
        error: palette.error,
      ),
      extensions: [MbColors(palette)],
      scaffoldBackgroundColor: palette.background,
      cardColor: palette.surface,
      // Dividers are drawn deliberately where they are wanted; the implicit
      // ones Material adds inside tab bars and dialogs are noise here.
      dividerColor: Colors.transparent,
      tooltipTheme: _tooltip(palette, showTooltips),
      dialogTheme: _dialog(palette),
      bottomSheetTheme: _bottomSheet(palette),
      appBarTheme: _appBar(palette),
      inputDecorationTheme: _inputDecoration(palette),
      chipTheme: _chip(palette),
      cardTheme: _card(palette),
      textButtonTheme: _textButton(palette),
      elevatedButtonTheme: _elevatedButton(palette),
      outlinedButtonTheme: _outlinedButton(palette),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: palette.text),
      ),
      switchTheme: _switch(palette),
      checkboxTheme: _checkbox(palette),
      radioTheme: _radio(palette),
      sliderTheme: _slider(palette),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.progressIndicator,
        linearTrackColor: palette.surfaceRaised,
        circularTrackColor: Colors.transparent,
      ),
      tabBarTheme: _tabBar(palette),
      snackBarTheme: _snackBar(palette),
      popupMenuTheme: _popupMenu(palette),
      listTileTheme: _listTile(palette),
      pageTransitionsTheme: _pageTransitions,
    );
  }

  /// Flutter cannot disable tooltips outright, so "off" is manual triggering
  /// plus a wait long enough never to elapse. When enabled, snappy 350ms wait duration
  /// with desktop styling.
  static TooltipThemeData _tooltip(MbPalette palette, bool showTooltips) =>
      TooltipThemeData(
        triggerMode: showTooltips ? null : TooltipTriggerMode.manual,
        waitDuration: showTooltips
            ? const Duration(milliseconds: 350)
            : const Duration(days: 365),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        textStyle: AppTypography.sans(
          color: palette.text,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      );

  static DialogThemeData _dialog(MbPalette palette) => DialogThemeData(
    backgroundColor: palette.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConstants.largeRadius),
    ),
    titleTextStyle: AppTypography.display(color: palette.text, fontSize: 18),
    contentTextStyle: AppTypography.sans(
      color: palette.textMuted,
      fontSize: 15,
      height: 1.45,
    ),
  );

  static BottomSheetThemeData _bottomSheet(MbPalette palette) =>
      BottomSheetThemeData(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.largeRadius),
          ),
        ),
      );

  static AppBarTheme _appBar(MbPalette palette) => AppBarTheme(
    backgroundColor: palette.background,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    // Material tints the bar as content scrolls under it; on a near-black
    // surface that reads as the bar changing colour at random.
    scrolledUnderElevation: 0,
    iconTheme: IconThemeData(color: palette.text),
    titleTextStyle: AppTypography.display(color: palette.text, fontSize: 20),
  );

  static InputDecorationTheme _inputDecoration(MbPalette palette) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      borderSide: BorderSide.none,
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceRaised,
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    );
  }

  static ChipThemeData _chip(MbPalette palette) => ChipThemeData(
    backgroundColor: palette.surfaceRaised,
    selectedColor: palette.accent,
    secondarySelectedColor: palette.usesCanonicalYellow ? palette.accent : null,
    checkmarkColor: palette.usesCanonicalYellow ? palette.onAccent : null,
    side: BorderSide.none,
    labelStyle: AppTypography.display(color: palette.text, fontSize: 12),
    secondaryLabelStyle: AppTypography.display(
      color: palette.onAccent,
      fontSize: 12,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConstants.pillRadius),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  );

  static CardThemeData _card(MbPalette palette) => CardThemeData(
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
    ),
    color: palette.surface,
  );

  // Buttons: amber caps for affirmative actions, muted caps for the rest.

  static TextButtonThemeData _textButton(MbPalette palette) =>
      TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accentForeground,
          textStyle: AppTypography.display(fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      );

  static ElevatedButtonThemeData _elevatedButton(MbPalette palette) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          elevation: 0,
          textStyle: AppTypography.display(fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      );

  static OutlinedButtonThemeData _outlinedButton(MbPalette palette) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border),
          textStyle: AppTypography.display(fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      );

  // Amber is the "on" state everywhere a control has one.

  static WidgetStateProperty<Color> _whenSelected(Color on, Color off) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? on : off,
      );

  static SwitchThemeData _switch(MbPalette palette) => SwitchThemeData(
    thumbColor: _whenSelected(palette.onAccent, palette.textMuted),
    trackColor: _whenSelected(palette.accent, palette.surfaceRaised),
    trackOutlineColor: WidgetStateProperty.all(palette.border),
    // The default hover/press halo around the thumb reads as a glow.
    overlayColor: WidgetStateProperty.all(Colors.transparent),
  );

  static CheckboxThemeData _checkbox(MbPalette palette) => CheckboxThemeData(
    fillColor: _whenSelected(palette.accent, Colors.transparent),
    checkColor: WidgetStateProperty.all(palette.onAccent),
    side: BorderSide(color: palette.border, width: 1.5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
  );

  static RadioThemeData _radio(MbPalette palette) => RadioThemeData(
    fillColor: _whenSelected(palette.accent, palette.textMuted),
  );

  static SliderThemeData _slider(MbPalette palette) => SliderThemeData(
    activeTrackColor: palette.accent,
    inactiveTrackColor: palette.surfaceRaised,
    thumbColor: palette.accent,
    overlayColor: Colors.transparent,
    valueIndicatorColor: palette.accent,
    valueIndicatorTextStyle: AppTypography.display(
      color: palette.onAccent,
      fontSize: 13,
    ),
    trackHeight: 4,
  );

  static TabBarThemeData _tabBar(MbPalette palette) => TabBarThemeData(
    labelColor: palette.text,
    unselectedLabelColor: palette.textMuted,
    labelStyle: AppTypography.display(fontSize: 13),
    unselectedLabelStyle: AppTypography.display(fontSize: 13),
    indicatorColor: palette.accent,
    dividerColor: Colors.transparent,
    overlayColor: WidgetStateProperty.all(Colors.transparent),
  );

  static SnackBarThemeData _snackBar(MbPalette palette) => SnackBarThemeData(
    backgroundColor: palette.surfaceRaised,
    contentTextStyle: AppTypography.sans(color: palette.text, fontSize: 14),
    actionTextColor: palette.accentOn(palette.surfaceRaised),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConstants.denseRadius),
      side: BorderSide(color: palette.border),
    ),
  );

  static PopupMenuThemeData _popupMenu(MbPalette palette) => PopupMenuThemeData(
    color: palette.surface,
    surfaceTintColor: Colors.transparent,
    textStyle: AppTypography.sans(color: palette.text, fontSize: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConstants.denseRadius),
    ),
  );

  static ListTileThemeData _listTile(MbPalette palette) => ListTileThemeData(
    iconColor: palette.textMuted,
    textColor: palette.text,
    titleTextStyle: AppTypography.sans(
      color: palette.text,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    ),
    subtitleTextStyle: AppTypography.sans(
      color: palette.textMuted,
      fontSize: 13,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConstants.denseRadius),
    ),
  );

  /// Page transitions match `AppTransitions` so system-pushed routes agree
  /// with the ones the app pushes itself.
  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
    },
  );
}
