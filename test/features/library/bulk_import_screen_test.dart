import '../../support/library_identity.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/features/library/import/bulk_import_screen.dart';
import 'package:mangabaka_app/features/library/import/import_parser.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoggedInAuth extends Fake with WidgetLibraryIdentity {
  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}

  bool loggedIn = true;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<String> getValidAccessToken() async => 'token';
}

void main() {
  setUpAll(prepareWidgetLibraryIdentity);
  TestWidgetsFlutterBinding.ensureInitialized();

  AppDatabase? database;
  late _LoggedInAuth auth;

  setUp(() async {
    await resetServiceLocator();
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    LocalizationService.resetForTesting();
    await SettingsManager().init();
    await LocalizationService().init();
    DesktopLayout.debugOverride = false;

    database = AppDatabase.forTesting(NativeDatabase.memory());
    auth = _LoggedInAuth();
    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<AppDatabase>(database!);
    getIt.registerSingleton<ProfileAuthService>(auth);
    getIt.registerSingleton<LibraryService>(
      LibraryService(auth: auth, database: database),
    );
  });

  tearDown(() async {
    DesktopLayout.debugOverride = null;
    await database?.close();
    await resetServiceLocator();
  });

  testWidgets('phone import input keeps all actions visible without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: BulkImportScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Paste from clipboard'), findsOneWidget);
    expect(find.text('Open file'), findsOneWidget);
    expect(find.text('From AniList'), findsOneWidget);

    final editor = tester.widget<TextField>(find.byType(TextField).first);
    expect(editor.textAlign, TextAlign.left);
    expect(editor.textAlignVertical, TextAlignVertical.top);
    final border = editor.decoration!.border! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(AppConstants.cardRadius));
  });

  final palettes = <MbPalette>[
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    ThemePresets.byId('catppuccin')!.light!,
    EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  ];

  testWidgets('input surfaces and controls follow the active palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: const BulkImportScreen(),
        ),
      ),
    );

    for (final colors in palettes) {
      palette.value = colors;
      await tester.pump();
      final page = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(BulkImportScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(page.backgroundColor, colors.background);
      final editor = tester.widget<TextField>(find.byType(TextField).first);
      expect(editor.style!.color, colors.text);
      expect(editor.decoration!.fillColor, colors.surfaceRaised);
      expect(
        MbPalette.contrastRatio(
          editor.decoration!.hintStyle!.color!,
          colors.surfaceRaised,
        ),
        greaterThanOrEqualTo(4.5),
      );
      await tester.scrollUntilVisible(
        find.byType(DropdownButton<ImportFormat>),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final format = tester.widget<DropdownButton<ImportFormat>>(
        find.byType(DropdownButton<ImportFormat>),
      );
      await tester.scrollUntilVisible(
        find.byType(DropdownButton<String>),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      final state = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(format.dropdownColor, colors.surface);
      expect(state.dropdownColor, colors.surface);
      expect(format.style!.color, colors.text);
      expect(state.style!.color, colors.text);
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(700, 320);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme switch retains input, format, target state and toggle', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: const BulkImportScreen(),
        ),
      ),
    );
    const input = 'title,status\nExample,Reading';
    await tester.enterText(find.byType(TextField).first, input);
    await tester.scrollUntilVisible(
      find.byType(DropdownButton<ImportFormat>),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byType(DropdownButton<String>),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<DropdownButton<ImportFormat>>(
          find.byType(DropdownButton<ImportFormat>),
        )
        .onChanged!(ImportFormat.csv);
    tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .onChanged!('reading');
    await tester.pump();
    await tester.ensureVisible(find.byType(SwitchListTile));
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    palette.value = EirenYuPalette.light;
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      input,
    );
    expect(
      tester
          .widget<DropdownButton<ImportFormat>>(
            find.byType(DropdownButton<ImportFormat>),
          )
          .value,
      ImportFormat.csv,
    );
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      'reading',
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AniList dialog recolors live and Cancel avoids fetching', (
    tester,
  ) async {
    final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          themeAnimationDuration: Duration.zero,
          home: const BulkImportScreen(),
        ),
      ),
    );
    await tester.ensureVisible(find.text('From AniList'));
    await tester.tap(find.text('From AniList'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
      EirenYuPalette.dark.surface,
    );
    palette.value = EirenYuPalette.light;
    await tester.pumpAndSettle();
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
      EirenYuPalette.light.surface,
    );
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.style!.color, EirenYuPalette.light.text);
    expect(
      MbPalette.contrastRatio(
        field.decoration!.labelStyle!.color!,
        EirenYuPalette.light.surfaceRaised,
      ),
      greaterThanOrEqualTo(4.5),
    );
    await tester.tap(find.text(LocalizationService().translate('cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logged-out message remains readable in both modes', (
    tester,
  ) async {
    auth.loggedIn = false;
    for (final colors in [EirenYuPalette.dark, EirenYuPalette.light]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: const BulkImportScreen(),
        ),
      );
      final message = tester.widget<Text>(
        find.text(LocalizationService().translate('import_login_required')),
      );
      expect(
        MbPalette.contrastRatio(message.style!.color!, colors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    DesktopLayout.debugOverride = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: const BulkImportScreen(),
      ),
    );
    final desktopPage = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(BulkImportScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(desktopPage.backgroundColor, EirenYuPalette.light.background);
    expect(tester.takeException(), isNull);
  });
}
