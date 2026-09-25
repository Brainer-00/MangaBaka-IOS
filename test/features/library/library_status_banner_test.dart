import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_banner.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_banners.dart';

void main() {
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
            status: const LibrarySyncStatus(error: 'Session expired'),
            isIncomplete: true,
            onRetrySync: () {},
            onDismissError: () {},
            onImportFullLibrary: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Session expired'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
