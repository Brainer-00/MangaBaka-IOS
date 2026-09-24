import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/utils/external_url_launcher.dart';

void main() {
  group('ExternalUrlLauncher.parseHttpsUrl', () {
    test('accepts absolute HTTPS URLs', () {
      expect(
        ExternalUrlLauncher.parseHttpsUrl('https://example.com/path'),
        Uri.parse('https://example.com/path'),
      );
      expect(
        ExternalUrlLauncher.parseHttpsUrl(
          'https://example.com/path?chapter=1#details',
        ),
        Uri.parse('https://example.com/path?chapter=1#details'),
      );
    });

    test('rejects malformed, relative, and scheme-relative values', () {
      for (final value in [
        '',
        'https://exa mple.com',
        '/relative/path',
        '//example.com/path',
      ]) {
        expect(ExternalUrlLauncher.parseHttpsUrl(value), isNull, reason: value);
      }
    });

    test('rejects non-HTTPS schemes', () {
      for (final value in [
        'http://example.com',
        'javascript:alert(1)',
        'data:text/html,<h1>unsafe</h1>',
        'file:///tmp/example',
        'mailto:user@example.com',
        'customscheme://example.com/path',
      ]) {
        expect(ExternalUrlLauncher.parseHttpsUrl(value), isNull, reason: value);
      }
    });

    test('rejects user info and missing hosts', () {
      expect(
        ExternalUrlLauncher.parseHttpsUrl('https://user@example.com/'),
        isNull,
      );
      expect(ExternalUrlLauncher.parseHttpsUrl('https:///path'), isNull);
    });
  });

  group('ExternalUrlLauncher host allowlist', () {
    const githubHosts = {'github.com'};

    test('accepts exact hosts case-insensitively', () {
      expect(
        ExternalUrlLauncher.parseHttpsUrl(
          'https://GITHUB.com/openai',
          allowedHosts: githubHosts,
        ),
        isNotNull,
      );
    });

    test('accepts legitimate subdomains only when enabled', () {
      expect(
        ExternalUrlLauncher.parseHttpsUrl(
          'https://www.github.com/openai',
          allowedHosts: githubHosts,
          allowSubdomains: true,
        ),
        isNotNull,
      );
      expect(
        ExternalUrlLauncher.parseHttpsUrl(
          'https://www.github.com/openai',
          allowedHosts: githubHosts,
        ),
        isNull,
      );
    });

    test('rejects lookalike and suffix-confusion hosts', () {
      for (final value in [
        'https://github.com.evil.test/',
        'https://fakegithub.com/',
        'https://evil-github.com/',
      ]) {
        expect(
          ExternalUrlLauncher.parseHttpsUrl(
            value,
            allowedHosts: githubHosts,
            allowSubdomains: true,
          ),
          isNull,
          reason: value,
        );
      }
    });
  });
}
