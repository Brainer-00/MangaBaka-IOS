import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LoggingService {
  static final Logger _logger = Logger('MangaBakaApp');
  static final List<String> _logBuffer = [];
  static const int _maxLogs = 1000;
  static const int _maxLogFileBytes = 10 * 1024 * 1024;
  static const Duration _flushInterval = Duration(seconds: 2);

  static File? _logFile;
  static StreamSubscription<LogRecord>? _subscription;
  static Timer? _flushTimer;

  // Lines waiting to be written to disk. They are flushed in batches rather
  // than once per record (the previous behaviour forced a synchronous disk
  // flush on every single log call, which was a real performance drain).
  static final Queue<String> _pendingWrites = Queue<String>();

  // Single-writer chain so concurrent flushes never overlap or interleave on
  // the same file handle.
  static Future<void> _writeChain = Future<void>.value();

  @visibleForTesting
  static void resetForTesting() {
    _logBuffer.clear();
    _pendingWrites.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _writeChain = Future<void>.value();
    _logFile = null;
  }

  static Future<void> setup() async {
    Logger.root.level = Level.ALL;

    try {
      final directory = await getApplicationDocumentsDirectory();
      _logFile = File(p.join(directory.path, 'app_logs.txt'));

      // Clear old logs if they get too large (e.g. > 10MB)
      if (await _logFile!.exists() &&
          await _logFile!.length() > _maxLogFileBytes) {
        await _logFile!.writeAsString('');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Failed to initialize log file (${e.runtimeType})');
      }
    }

    // Guard against re-subscribing: calling setup() more than once previously
    // attached an additional listener each time, duplicating every log line.
    _subscription ??= Logger.root.onRecord.listen(_onRecord);
    _flushTimer ??= Timer.periodic(_flushInterval, (_) => _flush());
  }

  static void _onRecord(LogRecord record) {
    final buffer = StringBuffer()
      ..write(
        '[${record.level.name}] ${record.time}: '
        '${_sanitize(record.message)}',
      );
    final error = record.error;
    if (error != null) {
      buffer.write('\nError type: ${error.runtimeType}');
    }
    // Stack traces can contain request data, filesystem paths, and values from
    // exception messages. Keep them out of logs that users can view or share.
    final logMessage = _sanitize(buffer.toString());

    // Console output is noise (and an avoidable cost) in release builds, but
    // profile builds are only ever run from `flutter run` — surfacing logs
    // there makes field diagnosis (network failures, rate limits) possible
    // without the in-app viewer.
    if (kDebugMode || kProfileMode) {
      // ignore: avoid_print
      print(logMessage);
    }

    _logBuffer.add(logMessage);
    if (_logBuffer.length > _maxLogs) {
      _logBuffer.removeAt(0);
    }

    if (_logFile != null) {
      _pendingWrites.add(logMessage);
    }
  }

  // Writes all currently-buffered lines to disk in a single append.
  static Future<void> _flush() {
    if (_logFile == null || _pendingWrites.isEmpty) return Future<void>.value();

    final payload = '${_pendingWrites.join('\n')}\n';
    _pendingWrites.clear();

    _writeChain = _writeChain.then((_) async {
      try {
        await _logFile!.writeAsString(payload, mode: FileMode.append);
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('Failed to write to log file (${e.runtimeType})');
        }
      }
    });
    return _writeChain;
  }

  static Logger get logger => _logger;
  static List<String> get logs => List.unmodifiable(_logBuffer);

  /// Forces any buffered log lines to be written to disk. Useful before the
  /// app terminates or when the persisted log file must be read immediately.
  static Future<void> flush() => _flush();

  static Future<void> clearLogs() async {
    _logBuffer.clear();
    _pendingWrites.clear();
    // Drop any in-flight writes and start a fresh chain — clearing means the
    // file should end up empty regardless of what was queued.
    _writeChain = Future<void>.value();
    try {
      // Truncate (creating the file if necessary) so the persisted log is
      // left in a known-empty state.
      await _logFile?.writeAsString('');
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Failed to clear log file (${e.runtimeType})');
      }
    }
  }

  static Future<String?> getLogFilePath() async {
    // Make sure any buffered lines are on disk before the caller reads the file.
    await flush();
    return _logFile?.path;
  }

  static String _sanitize(String value) {
    var sanitized = value;

    // Remove URL query and fragment contents before field-level replacements
    // so callback URLs and ordinary request URLs cannot retain secret values.
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'\b[a-z][a-z0-9+.-]*://[^\s<>]+', caseSensitive: false),
      (match) => _sanitizeUrl(match.group(0)!),
    );

    sanitized = sanitized.replaceAll(
      RegExp(r'\bAuthorization\s*:\s*Bearer\s+[^\s,;]+', caseSensitive: false),
      'Authorization: Bearer [REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );

    // Covers key=value, key: value, quoted JSON-like keys/values, and values
    // copied from query parameters outside a complete URL.
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'''(["']?\b(?:access_token|refresh_token|id_token|token|client_secret|code|state)\b["']?\s*[:=]\s*)(["']?)([^"'\s,;&}\]]+)(["']?)''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}${match.group(2)}[REDACTED]${match.group(4)}',
    );

    sanitized = sanitized.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
      '[REDACTED_JWT]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        caseSensitive: false,
      ),
      '[REDACTED_EMAIL]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\b[A-Z]:[\\/]Users[\\/][^\\/]+', caseSensitive: false),
      '[USER_HOME]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'/(?:Users|home)/[^/]+', caseSensitive: false),
      '[USER_HOME]',
    );

    return sanitized;
  }

  static String _sanitizeUrl(String rawUrl) {
    var url = rawUrl;
    var trailingPunctuation = '';
    while (
        url.isNotEmpty &&
        RegExp(r'''[.,;:!?\)\]}'"]''').hasMatch(url[url.length - 1])) {
      trailingPunctuation = '${url[url.length - 1]}$trailingPunctuation';
      url = url.substring(0, url.length - 1);
    }

    final queryIndex = url.indexOf('?');
    final fragmentIndex = url.indexOf('#');
    final firstSensitiveIndex = <int>[queryIndex, fragmentIndex]
        .where((index) => index >= 0)
        .fold<int>(
          url.length,
          (minimum, index) => index < minimum ? index : minimum,
        );
    if (firstSensitiveIndex < url.length) {
      url = '${url.substring(0, firstSensitiveIndex)}?[REDACTED]';
    }
    return '$url$trailingPunctuation';
  }
}
