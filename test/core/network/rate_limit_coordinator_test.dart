import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/network/rate_limit_coordinator.dart';

void main() {
  group('Retry-After parsing', () {
    final now = DateTime.utc(2026, 9, 24, 11, 59, 50);
    const fallback = Duration(seconds: 5);

    test('parses integer delta-seconds', () {
      expect(
        RateLimitCoordinator.retryAfterDelay(
          '10',
          now: now,
          fallback: fallback,
        ),
        const Duration(seconds: 10),
      );
    });

    test('parses an HTTP date relative to UTC now', () {
      expect(
        RateLimitCoordinator.retryAfterDelay(
          'Thu, 24 Sep 2026 12:00:00 GMT',
          now: now,
          fallback: fallback,
        ),
        const Duration(seconds: 10),
      );
    });

    test('uses fallback for invalid and missing values', () {
      expect(
        RateLimitCoordinator.retryAfterDelay(
          'later',
          now: now,
          fallback: fallback,
        ),
        fallback,
      );
      expect(
        RateLimitCoordinator.retryAfterDelay(
          null,
          now: now,
          fallback: fallback,
        ),
        fallback,
      );
    });

    test('past HTTP dates produce zero delay', () {
      expect(
        RateLimitCoordinator.retryAfterDelay(
          'Thu, 24 Sep 2026 11:00:00 GMT',
          now: now,
          fallback: fallback,
        ),
        Duration.zero,
      );
    });

    test('finds Retry-After with mixed header-name casing', () {
      expect(
        RateLimitCoordinator.retryAfterHeader(const {
          'Content-Type': 'application/json',
          'ReTrY-AfTeR': '11',
        }),
        '11',
      );
    });
  });

  group('shared cooldown', () {
    late DateTime now;
    late List<Duration> delays;
    late RateLimitCoordinator coordinator;

    setUp(() {
      now = DateTime.utc(2026, 9, 24, 12);
      delays = [];
      coordinator = RateLimitCoordinator(
        clock: () => now,
        delay: (duration) async {
          delays.add(duration);
          now = now.add(duration);
        },
      );
    });

    test(
      'active cooldown reports remaining delay and waits without sleeping',
      () async {
        coordinator.updateFromRetryAfter('10');
        now = now.add(const Duration(seconds: 3));

        expect(coordinator.remainingCooldown, const Duration(seconds: 7));
        await coordinator.waitForCooldown();
        expect(delays, [const Duration(seconds: 7)]);
        expect(coordinator.isCoolingDown, isFalse);
      },
    );

    test('expired cooldown permits a request immediately', () async {
      coordinator.updateFromRetryAfter('2');
      now = now.add(const Duration(seconds: 2));

      await coordinator.waitForCooldown();
      expect(delays, isEmpty);
    });

    test('updating cooldown never shortens a longer known cooldown', () {
      coordinator.updateFromRetryAfter('10');
      coordinator.updateFromRetryAfter('2');

      expect(coordinator.remainingCooldown, const Duration(seconds: 10));
    });

    test('policy allows only the exact production MangaBaka API origin', () {
      for (final allowed in [
        'https://api.mangabaka.org/v1/series',
        'https://API.MANGABAKA.ORG/v1/series',
        'https://api.mangabaka.org:443/v1/series',
      ]) {
        expect(
          RateLimitCoordinator.appliesTo(Uri.parse(allowed)),
          isTrue,
          reason: allowed,
        );
      }

      for (final rejected in [
        'http://api.mangabaka.org/v1/series',
        'https://api.mangabaka.org:8443/v1/series',
        'https://mangabaka.org/',
        'https://api.github.com/',
      ]) {
        expect(
          RateLimitCoordinator.appliesTo(Uri.parse(rejected)),
          isFalse,
          reason: rejected,
        );
      }
    });

    test('mutation 429 is translated and never replayed by the helper', () {
      expect(
        () => coordinator.throwIfRateLimited(
          statusCode: 429,
          headers: const {'Retry-After': '8'},
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 429)
              .having((error) => error.code, 'code', 'RATE_LIMITED'),
        ),
      );
      expect(coordinator.remainingCooldown, const Duration(seconds: 8));
    });
  });
}
