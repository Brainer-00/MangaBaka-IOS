import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';

class _PrivateLogException implements Exception {
  const _PrivateLogException(this.message);

  final String message;

  @override
  String toString() => '_PrivateLogException: $message';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    LoggingService.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('logging_test');
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory' || 
            methodCall.method == 'getApplicationSupportDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LoggingService', () {
    test('setup initializes log file', () async {
      await LoggingService.setup();
      LoggingService.logger.info('Initial log');
      await Future.delayed(const Duration(milliseconds: 100));
      
      final logFilePath = await LoggingService.getLogFilePath();
      expect(logFilePath, isNotNull);
      
      final logFile = File(logFilePath!);
      expect(await logFile.exists(), true);
    });

    test('logging messages adds to buffer and file', () async {
      await LoggingService.setup();
      
      LoggingService.logger.info('Test log message');
      
      // Wait for the async listener to process the log
      await Future.delayed(const Duration(milliseconds: 100));
      
      expect(LoggingService.logs.any((l) => l.contains('Test log message')), true);
      
      final logFilePath = await LoggingService.getLogFilePath();
      final content = await File(logFilePath!).readAsString();
      expect(content.contains('Test log message'), true);
    });

    test('clearLogs clears both buffer and file', () async {
      await LoggingService.setup();
      LoggingService.logger.info('Message to clear');
      await Future.delayed(const Duration(milliseconds: 100));
      
      await LoggingService.clearLogs();
      
      expect(LoggingService.logs, isEmpty);
      
      final logFilePath = await LoggingService.getLogFilePath();
      final content = await File(logFilePath!).readAsString();
      expect(content, isEmpty);
    });

    test('redacts sensitive message values from buffer and file', () async {
      await LoggingService.setup();

      const secrets = <String>[
        'bearer-secret-123',
        'access-secret-456',
        'refresh-secret-789',
        'id-secret-abc',
        'client-secret-def',
        'oauth-code-ghi',
        'oauth-state-jkl',
        'query-secret-mno',
        'private@example.com',
        'private-windows-user',
        'private-unix-user',
        'private-macos-user',
        'custom-callback-secret',
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcml2YXRlIn0.signature',
      ];
      LoggingService.logger.info(
        'Profile refresh completed with HTTP 200; '
        'Authorization: Bearer ${secrets[0]}; '
        'access_token=${secrets[1]}; refresh_token: ${secrets[2]}; '
        '"id_token":"${secrets[3]}"; client_secret=${secrets[4]}; '
        'code=${secrets[5]}; state=${secrets[6]}; '
        'https://example.test/callback?secret=${secrets[7]}&code=hidden; '
        'email=${secrets[8]}; '
        r'C:\Users\private-windows-user\Downloads\app.apk; '
        '/home/${secrets[10]}/app/data; '
        '/Users/${secrets[11]}/Library/app; '
        'mangabaka://oauth/callback?code=${secrets[12]}; '
        'jwt=${secrets[13]}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final buffered = LoggingService.logs.join('\n');
      final logFilePath = await LoggingService.getLogFilePath();
      final persisted = await File(logFilePath!).readAsString();

      for (final secret in secrets) {
        expect(buffered, isNot(contains(secret)));
        expect(persisted, isNot(contains(secret)));
      }
      expect(buffered, contains('Profile refresh completed'));
      expect(buffered, contains('HTTP 200'));
      expect(persisted, contains('Profile refresh completed'));
      expect(persisted, contains('HTTP 200'));
    });

    test('stores only error runtimeType and omits stack traces', () async {
      await LoggingService.setup();

      const rawErrorSecret = 'raw-error-secret-value';
      const stackSecret = 'stack-trace-secret-marker';
      LoggingService.logger.log(
        Level.SEVERE,
        'Library sync failed at HTTP 503',
        const _PrivateLogException(rawErrorSecret),
        StackTrace.fromString('frame containing $stackSecret'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final buffered = LoggingService.logs.join('\n');
      final logFilePath = await LoggingService.getLogFilePath();
      final persisted = await File(logFilePath!).readAsString();

      for (final output in <String>[buffered, persisted]) {
        expect(output, contains('Library sync failed'));
        expect(output, contains('HTTP 503'));
        expect(output, contains('Error type: _PrivateLogException'));
        expect(output, isNot(contains(rawErrorSecret)));
        expect(output, isNot(contains(stackSecret)));
        expect(output, isNot(contains('StackTrace:')));
      }
    });
  });
}
