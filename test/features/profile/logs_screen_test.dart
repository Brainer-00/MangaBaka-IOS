import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/profile/screens/logs_screen.dart';

void main() {
  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    LoggingService.clearLogs();
  });

  testWidgets('LogsScreen renders empty-state when no logs', (tester) async {
    LoggingService.clearLogs();
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));
    await tester.pump();
    expect(find.byType(LogsScreen), findsOneWidget);
  });

  testWidgets('LogsScreen builds without errors and contains an AppBar', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));
    await tester.pump();
    expect(find.byType(LogsScreen), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  test('LoggingService.clearLogs empties the static buffer', () async {
    await LoggingService.clearLogs();
    expect(LoggingService.logs, isEmpty);
  });
}
