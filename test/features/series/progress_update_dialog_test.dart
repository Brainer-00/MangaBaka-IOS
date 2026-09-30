import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/features/series/widgets/progress_update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LocalizationService.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    await LocalizationService().init();
  });

  Future<void> openDialog(
    WidgetTester tester,
    Future<void> Function(int) onUpdate,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ProgressUpdateDialog(
                  initialValue: 2,
                  title: 'Update chapters',
                  maxValue: '12',
                  onUpdate: onUpdate,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('save awaits success and prevents duplicate submissions', (
    tester,
  ) async {
    final completion = Completer<void>();
    var calls = 0;
    await openDialog(tester, (value) {
      calls++;
      expect(value, 2);
      return completion.future;
    });

    await tester.tap(find.text('Save'));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(ProgressUpdateDialog), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completion.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ProgressUpdateDialog), findsNothing);
  });

  testWidgets('failed save keeps the sheet open and reports an error', (
    tester,
  ) async {
    await openDialog(tester, (_) async => throw StateError('failed'));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(ProgressUpdateDialog), findsOneWidget);
    expect(find.text('failed_to_update'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('manual progress input accepts digits but not a minus sign', (
    tester,
  ) async {
    int? submitted;
    await openDialog(tester, (value) async => submitted = value);

    await tester.enterText(find.byType(TextField), '-3');
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(submitted, 3);
  });

  testWidgets('empty progress disables save and cannot submit a stale value', (
    tester,
  ) async {
    var calls = 0;
    await openDialog(tester, (_) async => calls++);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
    expect(calls, 0);
  });
}
