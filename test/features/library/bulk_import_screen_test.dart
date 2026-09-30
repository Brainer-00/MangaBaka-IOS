import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/features/library/import/bulk_import_screen.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoggedInAuth extends Fake implements ProfileAuthService {
  @override
  bool get isLoggedIn => true;

  @override
  Future<String> getValidAccessToken() async => 'token';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppDatabase? database;

  setUp(() async {
    await resetServiceLocator();
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    LocalizationService.resetForTesting();
    await SettingsManager().init();
    await LocalizationService().init();
    DesktopLayout.debugOverride = false;

    database = AppDatabase.forTesting(NativeDatabase.memory());
    final auth = _LoggedInAuth();
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
}
