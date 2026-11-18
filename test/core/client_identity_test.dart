import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/generated/app_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('display name changes while the User-Agent and release URLs stay', () {
    expect(AppConstants.appName, 'EirenYu');
    expect(
      AppConstants.userAgent,
      'MangaBaka iOS/${GeneratedAppVersion.version} '
      '(https://github.com/Brainer-00/MangaBaka-IOS)',
    );
    expect(AppConstants.githubOwner, 'Brainer-00');
    expect(AppConstants.githubRepo, 'MangaBaka-IOS');
    expect(
      AppConstants.githubRepoUrl,
      'https://github.com/Brainer-00/MangaBaka-IOS',
    );
    expect(
      AppConstants.githubReleasesApi,
      'https://api.github.com/repos/Brainer-00/MangaBaka-IOS/releases',
    );
  });

  for (final locale in ['en', 'as', 'de', 'es', 'fr', 'ja']) {
    test('$locale defines EirenYu as the app name', () async {
      final json = await rootBundle.loadString('assets/lang/$locale.json');
      expect(jsonDecode(json)['strings']['app_name'], 'EirenYu');
    });
  }

  test('iOS app name changes while the install and OAuth IDs stay', () {
    const bundleId = 'io.github.brainer00.mangabaka-ios';
    expect(AppConstants.oauthRedirectUri, '$bundleId://oauthredirect');

    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      matches(r'<key>CFBundleDisplayName</key>\s*<string>EirenYu</string>'),
    );
    expect(
      plist,
      matches(r'<key>CFBundleName</key>\s*<string>EirenYu</string>'),
    );
    expect(
      plist,
      matches(
        '<key>CFBundleURLSchemes</key>\\s*<array>\\s*'
        '<string>${RegExp.escape(bundleId)}</string>',
      ),
    );

    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final runnerIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = "([^"]+)";')
        .allMatches(project)
        .map((match) => match.group(1)!)
        .where((id) => !id.endsWith('.RunnerTests'));
    expect(runnerIds, [bundleId, bundleId, bundleId]);
  });
}
