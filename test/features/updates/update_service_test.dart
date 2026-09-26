import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/features/updates/services/update_service.dart';
import 'package:mangabaka_app/features/updates/models/app_release.dart';

Map<String, dynamic> _releaseJson({
  String tag = 'v99.0.0',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, dynamic>>? assets,
}) => {
  'tag_name': tag,
  'name': 'Release $tag',
  'body': 'Changelog',
  'html_url': 'https://github.com/example/repo/releases/tag/$tag',
  'draft': draft,
  'prerelease': prerelease,
  'published_at': '2026-01-01T00:00:00Z',
  'assets': assets ?? [],
};

http.Client _clientWith(int status, Object body) => MockClient(
  (request) async => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  ),
);

void main() {
  group('UpdateService.fetchLatestRelease', () {
    test('returns release on 200', () async {
      final client = _clientWith(200, [_releaseJson()]);
      final svc = UpdateService(client: client);
      final release = await svc.fetchLatestRelease();
      expect(release, isNotNull);
      expect(release!.tagName, 'v99.0.0');
      svc.dispose();
    });

    test('skips draft releases', () async {
      final client = _clientWith(200, [
        _releaseJson(tag: 'v99.0.0', draft: true),
        _releaseJson(tag: 'v98.0.0'),
      ]);
      final svc = UpdateService(client: client);
      final release = await svc.fetchLatestRelease();
      expect(release?.tagName, 'v98.0.0');
      svc.dispose();
    });

    test(
      'requests a release window large enough to see past prereleases',
      () async {
        late Uri requestedUri;
        final client = MockClient((request) async {
          requestedUri = request.url;
          return http.Response(jsonEncode(<dynamic>[]), 200);
        });
        final svc = UpdateService(client: client, currentVersion: '1.0.0');

        await svc.fetchLatestRelease();

        expect(requestedUri.queryParameters['per_page'], '20');
        svc.dispose();
      },
    );

    test('returns null on non-200', () async {
      final client = _clientWith(500, {'error': 'server error'});
      final svc = UpdateService(client: client);
      final release = await svc.fetchLatestRelease();
      expect(release, isNull);
      svc.dispose();
    });

    test('returns null on network error', () async {
      final client = MockClient(
        (_) async => throw const SocketException('no network'),
      );
      final svc = UpdateService(client: client);
      final release = await svc.fetchLatestRelease();
      expect(release, isNull);
      svc.dispose();
    });

    test('returns null when list is empty', () async {
      final client = _clientWith(200, <dynamic>[]);
      final svc = UpdateService(client: client);
      final release = await svc.fetchLatestRelease();
      expect(release, isNull);
      svc.dispose();
    });
  });

  group('UpdateService.checkForUpdate', () {
    test('returns release when newer than installed', () async {
      final client = _clientWith(200, [_releaseJson(tag: 'v99.0.0')]);
      final svc = UpdateService(client: client);
      final result = await svc.checkForUpdate();
      expect(result, isNotNull);
      svc.dispose();
    });

    test('returns null when same as installed', () async {
      // The release is older than the generated current application version.
      final client = _clientWith(200, [_releaseJson(tag: 'v0.1.0')]);
      final svc = UpdateService(client: client);
      final result = await svc.checkForUpdate();
      expect(result, isNull);
      svc.dispose();
    });

    test('stable installation ignores newer GitHub prerelease', () async {
      final client = _clientWith(200, [
        _releaseJson(tag: 'v1.1.0-pre-release-3', prerelease: true),
        _releaseJson(tag: 'v1.0.1'),
      ]);
      final svc = UpdateService(client: client, currentVersion: '1.0.0');

      final result = await svc.checkForUpdate();

      expect(result?.tagName, 'v1.0.1');
      svc.dispose();
    });

    test(
      'stable installation ignores prerelease tag when GitHub flag is false',
      () async {
        final client = _clientWith(200, [
          _releaseJson(tag: 'v1.1.0-pre-release-3'),
        ]);
        final svc = UpdateService(client: client, currentVersion: '1.0.0');

        final result = await svc.checkForUpdate();

        expect(result, isNull);
        svc.dispose();
      },
    );

    test(
      'stable installation skips misclassified prerelease before stable',
      () async {
        final client = _clientWith(200, [
          _releaseJson(tag: 'v1.2.0-pre-release-4'),
          _releaseJson(tag: 'v1.0.1'),
        ]);
        final svc = UpdateService(client: client, currentVersion: '1.0.0');

        final result = await svc.checkForUpdate();

        expect(result?.tagName, 'v1.0.1');
        svc.dispose();
      },
    );

    test(
      'stable installation returns null when only prereleases are newer',
      () async {
        final client = _clientWith(200, [
          _releaseJson(tag: 'v1.1.0-pre-release-3', prerelease: true),
        ]);
        final svc = UpdateService(client: client, currentVersion: '1.0.0');

        final result = await svc.checkForUpdate();

        expect(result, isNull);
        svc.dispose();
      },
    );

    test('prerelease installation can receive a newer prerelease', () async {
      final client = _clientWith(200, [
        _releaseJson(tag: 'v1.1.0-pre-release-3', prerelease: true),
      ]);
      final svc = UpdateService(
        client: client,
        currentVersion: '1.1.0-pre-release-2',
      );

      final result = await svc.checkForUpdate();

      expect(result?.tagName, 'v1.1.0-pre-release-3');
      svc.dispose();
    });

    test(
      'prerelease installation accepts prerelease tag when GitHub flag is false',
      () async {
        final client = _clientWith(200, [
          _releaseJson(tag: 'v1.1.0-pre-release-3'),
        ]);
        final svc = UpdateService(
          client: client,
          currentVersion: '1.1.0-pre-release-2',
        );

        final result = await svc.checkForUpdate();

        expect(result?.tagName, 'v1.1.0-pre-release-3');
        svc.dispose();
      },
    );

    test(
      'prerelease installation can receive stable release of same base',
      () async {
        final client = _clientWith(200, [_releaseJson(tag: 'v1.1.0')]);
        final svc = UpdateService(
          client: client,
          currentVersion: '1.1.0-pre-release-2',
        );

        final result = await svc.checkForUpdate();

        expect(result?.tagName, 'v1.1.0');
        svc.dispose();
      },
    );

    test(
      'chooses highest eligible version rather than first API item',
      () async {
        final client = _clientWith(200, [
          _releaseJson(tag: 'v1.0.1'),
          _releaseJson(tag: 'v1.3.0'),
          _releaseJson(tag: 'v1.2.0'),
        ]);
        final svc = UpdateService(client: client, currentVersion: '1.0.0');

        final result = await svc.checkForUpdate();

        expect(result?.tagName, 'v1.3.0');
        svc.dispose();
      },
    );

    test('same and older eligible releases do not trigger an update', () async {
      final client = _clientWith(200, [
        _releaseJson(tag: 'v1.0.0'),
        _releaseJson(tag: 'v0.9.9'),
      ]);
      final svc = UpdateService(client: client, currentVersion: '1.0.0+15');

      final result = await svc.checkForUpdate();

      expect(result, isNull);
      svc.dispose();
    });

    test(
      'malformed release entries are skipped without aborting the check',
      () async {
        final malformed = _releaseJson(tag: 'not-a-version')..['draft'] = 'no';
        final client = _clientWith(200, [
          malformed,
          _releaseJson(tag: ''),
          'not an object',
          _releaseJson(tag: 'v1.0.2'),
        ]);
        final svc = UpdateService(client: client, currentVersion: '1.0.0');

        final result = await svc.checkForUpdate();

        expect(result?.tagName, 'v1.0.2');
        svc.dispose();
      },
    );
  });

  group('UpdateService.shouldPrompt', () {
    test('returns true only once per instance', () {
      final client = MockClient((_) async => throw UnimplementedError());
      final svc = UpdateService(client: client);
      expect(svc.shouldPrompt(), isTrue);
      expect(svc.shouldPrompt(), isFalse);
      expect(svc.shouldPrompt(), isFalse);
      svc.dispose();
    });
  });

  group('UpdateService.selectAssetForPlatform', () {
    AppRelease releaseWithAssets(List<Map<String, dynamic>> assets) =>
        AppRelease.fromJson(_releaseJson(tag: 'v1.0.0', assets: assets));

    test('returns null for empty asset list', () async {
      final client = MockClient((_) async => throw UnimplementedError());
      final svc = UpdateService(client: client);
      final release = releaseWithAssets([]);
      final asset = await svc.selectAssetForPlatform(release);
      expect(asset, isNull);
      svc.dispose();
    });
  });
}
