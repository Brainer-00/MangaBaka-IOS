import 'dart:async';

import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';

typedef RateLimitClock = DateTime Function();
typedef RateLimitDelay = Future<void> Function(Duration duration);

/// Coordinates HTTP 429 handling for requests to the MangaBaka API origin.
///
/// The shared instance prevents separate GET clients from immediately sending
/// more traffic while a server-provided cooldown is active. A custom clock and
/// delay keep parsing and retry behavior deterministic in unit tests.
class RateLimitCoordinator {
  RateLimitCoordinator({
    RateLimitClock? clock,
    RateLimitDelay? delay,
    this.fallbackDelay = const Duration(
      seconds: AppConstants.rateLimitRetryDelaySeconds,
    ),
  }) : _clock = clock ?? _utcNow,
       _delay = delay ?? Future<void>.delayed;

  static final RateLimitCoordinator shared = RateLimitCoordinator();

  final RateLimitClock _clock;
  final RateLimitDelay _delay;
  final Duration fallbackDelay;

  DateTime? _cooldownUntil;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Whether [uri] belongs to the API origin governed by this policy.
  static bool appliesTo(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'api.mangabaka.org' &&
      uri.port == 443;

  /// Returns Retry-After regardless of the response header's name casing.
  static String? retryAfterHeader(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') return entry.value;
    }
    return null;
  }

  /// Parses either Retry-After delta-seconds or an HTTP date.
  ///
  /// Missing and invalid values use [fallback]. Past HTTP dates safely produce
  /// a zero delay. Negative delta-seconds are invalid and therefore fall back.
  static Duration retryAfterDelay(
    String? value, {
    required DateTime now,
    required Duration fallback,
  }) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;

    final seconds = int.tryParse(trimmed);
    if (seconds != null) {
      return seconds < 0 ? fallback : Duration(seconds: seconds);
    }

    final date = HttpDate.tryParse(trimmed)?.toUtc();
    if (date == null) return fallback;
    final remaining = date.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration get remainingCooldown {
    final until = _cooldownUntil;
    if (until == null) return Duration.zero;
    final remaining = until.difference(_clock().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get isCoolingDown => remainingCooldown > Duration.zero;

  /// Records a cooldown and never shortens a longer cooldown already known.
  Duration updateFromRetryAfter(String? retryAfter) {
    final now = _clock().toUtc();
    final delay = retryAfterDelay(
      retryAfter,
      now: now,
      fallback: fallbackDelay,
    );
    final candidate = now.add(delay);
    if (_cooldownUntil == null || candidate.isAfter(_cooldownUntil!)) {
      _cooldownUntil = candidate;
    }
    return delay;
  }

  /// Waits until the shared cooldown has elapsed, including extensions that
  /// may be recorded by another request while this one is waiting.
  Future<void> waitForCooldown() async {
    while (true) {
      final remaining = remainingCooldown;
      if (remaining <= Duration.zero) return;
      await _delay(remaining);
    }
  }

  /// Translates a mutation's 429 without ever replaying the mutation.
  void throwIfRateLimited({
    required int statusCode,
    required Map<String, String> headers,
  }) {
    if (statusCode != 429) return;
    updateFromRetryAfter(retryAfterHeader(headers));
    throw ApiException(
      message: 'Too many requests. Please try again later.',
      statusCode: 429,
      code: 'RATE_LIMITED',
    );
  }

  /// Test-only/state-owner utility for resetting an injected coordinator.
  void clear() => _cooldownUntil = null;
}

/// Minimal HTTP-date parser for the IMF-fixdate form used by Retry-After.
class HttpDate {
  HttpDate._();

  static final RegExp _pattern = RegExp(
    r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) '
    r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) '
    r'(\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  );

  static const _months = <String, int>{
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  static DateTime? tryParse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    try {
      final parsed = DateTime.utc(
        int.parse(match.group(3)!),
        _months[match.group(2)]!,
        int.parse(match.group(1)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
      if (parsed.year != int.parse(match.group(3)!) ||
          parsed.month != _months[match.group(2)]! ||
          parsed.day != int.parse(match.group(1)!) ||
          parsed.hour != int.parse(match.group(4)!) ||
          parsed.minute != int.parse(match.group(5)!) ||
          parsed.second != int.parse(match.group(6)!)) {
        return null;
      }
      return parsed;
    } on FormatException {
      return null;
    }
  }
}
