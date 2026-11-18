import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_surfaces.dart';
import 'package:mangabaka_app/features/profile/screens/logs_screen.dart';
import 'package:mangabaka_app/features/profile/screens/privacy_legal_screen.dart';
import 'package:mangabaka_app/features/profile/screens/translation_credits_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalizationService.resetForTesting();
    await LocalizationService().init();
    LoggingService.resetForTesting();
    DesktopLayout.debugOverride = false;
  });

  tearDown(() {
    LoggingService.resetForTesting();
    DesktopLayout.debugOverride = null;
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    ValueNotifier<MbPalette> palette,
    Widget screen,
  ) => tester.pumpWidget(
    ValueListenableBuilder<MbPalette>(
      valueListenable: palette,
      builder: (_, colors, _) => MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: colors),
        themeAnimationDuration: Duration.zero,
        home: screen,
      ),
    ),
  );

  final palettes = [
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  ];

  testWidgets(
    'Legal summary and action colors change without resetting scroll',
    (tester) async {
      final palette = ValueNotifier<MbPalette>(palettes.first);
      addTearDown(palette.dispose);
      await pumpScreen(tester, palette, const PrivacyLegalScreen());
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(100);
      await tester.pump();
      final before = scroll.position.pixels;
      for (final colors in palettes) {
        palette.value = colors;
        await tester.pump();
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          colors.background,
        );
        expect(scroll.position.pixels, before);
        final summary = tester.widget<Text>(find.text('PRIVACY AT A GLANCE'));
        expect(
          MbPalette.contrastRatio(summary.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        final shield = tester.widget<Icon>(find.byIcon(Icons.shield_outlined));
        expect(
          MbPalette.contrastRatio(shield.color!, colors.surface),
          greaterThanOrEqualTo(3),
        );
        final actionIcon = tester.widget<Icon>(
          find.byIcon(Icons.open_in_new).first,
        );
        expect(
          MbPalette.contrastRatio(actionIcon.color!, colors.surface),
          greaterThanOrEqualTo(3),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'desktop Legal actions retain focus outline and keyboard action',
    (tester) async {
      DesktopLayout.debugOverride = true;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final palette = ValueNotifier<MbPalette>(palettes.first);
      addTearDown(palette.dispose);
      await pumpScreen(tester, palette, const PrivacyLegalScreen());
      await tester.pump();
      final license = find.text('OPEN-SOURCE LICENSES');
      await tester.ensureVisible(license);
      final row = find.ancestor(
        of: license,
        matching: find.byType(DesktopSettingRow),
      );
      final action = find.descendant(
        of: row,
        matching: find.byType(DesktopPillButton),
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final focusNode = Focus.of(tester.element(action));
      focusNode.requestFocus();
      await tester.pump();
      final focused = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: action, matching: find.byType(AnimatedContainer))
            .first,
      );
      expect((focused.decoration! as BoxDecoration).border, isNotNull);
      palette.value = EirenYuPalette.light;
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      final recolored = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: action, matching: find.byType(AnimatedContainer))
            .first,
      );
      final focusBorder =
          (recolored.decoration! as BoxDecoration).border! as Border;
      expect(
        MbPalette.contrastRatio(
          focusBorder.top.color,
          EirenYuPalette.light.surface,
        ),
        greaterThanOrEqualTo(3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    },
  );

  testWidgets(
    'Credits keep contributors and scroll state through theme changes',
    (tester) async {
      final languages = LocalizationService().getLanguages();
      expect(languages, isNotEmpty);
      final palette = ValueNotifier<MbPalette>(palettes.first);
      addTearDown(palette.dispose);
      await pumpScreen(tester, palette, const TranslationCreditsScreen());
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(50);
      await tester.pump();
      final before = scroll.position.pixels;
      for (final colors in palettes) {
        palette.value = colors;
        await tester.pump();
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          colors.background,
        );
        expect(scroll.position.pixels, before);
        final language = tester.widget<Text>(
          find.text(languages.first['name']),
        );
        expect(
          MbPalette.contrastRatio(language.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        final contributor = tester.widget<Text>(
          find.text((languages.first['translators'] as List<String>).first),
        );
        expect(
          MbPalette.contrastRatio(contributor.style!.color!, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Logs empty state, notice and disabled actions follow palettes', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    await pumpScreen(tester, palette, const LogsScreen());
    for (final colors in palettes) {
      palette.value = colors;
      await tester.pump();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        colors.background,
      );
      final buttons = tester
          .widgetList<ElevatedButton>(find.byType(ElevatedButton))
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons.every((button) => button.onPressed == null), isTrue);
      final notice = tester.widget<Text>(
        find.text(LocalizationService().translate('log_share_warning')),
      );
      final noticeBackground = Color.alphaBlend(
        colors.info.withValues(alpha: 0.10),
        colors.background,
      );
      expect(
        MbPalette.contrastRatio(notice.style!.color!, noticeBackground),
        greaterThanOrEqualTo(4.5),
      );
      final infoIcon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
      expect(
        MbPalette.contrastRatio(infoIcon.color!, noticeBackground),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Logs copy and clear preserve content through theme changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(620, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => throw PlatformException(code: 'disabled_in_test'),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          ),
    );
    await LoggingService.setup();
    LoggingService.logger.info('Fixture diagnostic line');
    for (var index = 0; index < 18; index++) {
      LoggingService.logger.info('Fixture detail $index');
    }
    await tester.pump();
    expect(LoggingService.logs, isNotEmpty);
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    await pumpScreen(tester, palette, const LogsScreen());
    final state = tester.state(find.byType(LogsScreen));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(30);
    await tester.pump();
    final scrollBefore = scroll.position.pixels;
    expect(scrollBefore, greaterThan(0));
    expect(find.textContaining('Fixture diagnostic line'), findsOneWidget);
    for (final colors in palettes) {
      palette.value = colors;
      await tester.pump();
      expect(tester.state(find.byType(LogsScreen)), same(state));
      expect(scroll.position.pixels, scrollBefore);
      expect(find.textContaining('Fixture diagnostic line'), findsOneWidget);
      final buttons = tester
          .widgetList<ElevatedButton>(find.byType(ElevatedButton))
          .toList();
      expect(buttons.every((button) => button.onPressed != null), isTrue);
      final shareFg = buttons.last.style!.foregroundColor!.resolve({})!;
      final shareBg = buttons.last.style!.backgroundColor!.resolve({})!;
      expect(
        MbPalette.contrastRatio(shareFg, shareBg),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    expect(copiedText, contains('Fixture diagnostic line'));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(LoggingService.logs, isEmpty);
    expect(find.text('No logs recorded yet'), findsOneWidget);
    LoggingService.resetForTesting();
  });

  testWidgets('three screens fit narrow portrait and short landscape', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    for (final size in [const Size(280, 640), const Size(620, 300)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final screen in [
        const PrivacyLegalScreen(),
        const TranslationCreditsScreen(),
        const LogsScreen(),
      ]) {
        await pumpScreen(tester, palette, screen);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.reset();
  });
}
