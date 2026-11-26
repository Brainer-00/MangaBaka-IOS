import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/network/backend_health_banner.dart';
import 'package:mangabaka_app/core/network/backend_health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_banner.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_banners.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().init();
  });

  for (final healthFirst in [true, false]) {
    testWidgets('cached outage has one notice (health first: $healthFirst)', (
      tester,
    ) async {
      final health = BackendHealthService(
        client: MockClient((_) async => http.Response('', 200)),
        failureThreshold: 1,
        probeInterval: const Duration(hours: 1),
      );
      getIt.registerSingleton(health);
      final status = ValueNotifier(const LibrarySyncStatus());
      addTearDown(() async {
        status.dispose();
        health.dispose();
        await getIt.reset();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const BackendHealthBanner(),
                ValueListenableBuilder(
                  valueListenable: status,
                  builder: (_, value, _) => LibraryStatusBanners(
                    loggedIn: true,
                    status: value,
                    onRetrySync: () {},
                    onDismissError: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      void updateHealth() => health.reportServerFailure(context: 'test');
      void updateSync() =>
          status.value = const LibrarySyncStatus(isServerDown: true);
      final outage = find.textContaining("Can't reach MangaBaka");
      final summary = find.textContaining('Sync failed');
      final cap = find.textContaining('maximum number of pages');
      if (healthFirst) {
        updateHealth();
      } else {
        updateSync();
      }
      await tester.pump();
      expect(outage, healthFirst ? findsOneWidget : findsNothing);
      expect(summary, findsNothing);
      expect(cap, findsNothing);
      if (healthFirst) {
        updateSync();
      } else {
        updateHealth();
      }
      await tester.pumpAndSettle();
      expect(outage, findsOneWidget);
      expect(summary, findsNothing);
      expect(cap, findsNothing);

      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();
      expect(outage, findsNothing);
      expect(summary, findsNothing);
      status.value = const LibrarySyncStatus();
      await tester.pump();
      expect(find.byType(LibraryStatusBanner), findsNothing);
    });
  }

  testWidgets('shows distinct localized sync and import notices with Retry', (
    tester,
  ) async {
    var retries = 0;
    Future<void> show(LibrarySyncStatus status) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryStatusBanners(
            loggedIn: true,
            status: status,
            onRetrySync: () => retries++,
            onDismissError: () {},
          ),
        ),
      ),
    );

    await show(const LibrarySyncStatus(error: 'failed_to_load'));
    expect(find.text('Sync failed: Failed to load data'), findsOneWidget);
    expect(find.textContaining('failed_to_load'), findsNothing);
    await tester.tap(find.text('Retry'));
    await show(
      const LibrarySyncStatus(
        error: 'failed_to_load',
        initialImportIncomplete: true,
      ),
    );
    expect(find.text('Your Library import is incomplete.'), findsOneWidget);
    expect(find.textContaining('maximum number of pages'), findsNothing);
    await tester.tap(find.text('Retry'));

    await show(
      const LibrarySyncStatus(
        initialImportIncomplete: true,
        pageLimitReached: true,
      ),
    );
    expect(find.textContaining('maximum number of pages'), findsOneWidget);
    expect(find.text('Your Library import is incomplete.'), findsNothing);
    await tester.tap(find.text('Update'));
    expect(retries, 3);
  });

  testWidgets('LibraryStatusBanner displays message and icon', (
    WidgetTester tester,
  ) async {
    bool actionPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryStatusBanner(
            message: 'Test Banner',
            icon: Icons.info,
            color: Colors.blue,
            action: TextButton(
              onPressed: () => actionPressed = true,
              child: const Text('Action'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Test Banner'), findsOneWidget);
    expect(find.byIcon(Icons.info), findsOneWidget);

    await tester.tap(find.text('Action'));
    expect(actionPressed, isTrue);
  });

  testWidgets('LibraryStatusBanner close button works', (
    WidgetTester tester,
  ) async {
    bool closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryStatusBanner(
            message: 'Test Banner',
            icon: Icons.info,
            color: Colors.blue,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    expect(closed, isTrue);
  });

  testWidgets('hides stale sync errors after the session ends', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryStatusBanners(
            loggedIn: false,
            status: const LibrarySyncStatus(
              error: 'Session expired',
              pageLimitReached: true,
            ),
            onRetrySync: () {},
            onDismissError: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Session expired'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
