import 'dart:io';

import 'package:mangabaka_app/core/theme/ios_icon_variants.dart';

void main() {
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  final source = project.readAsStringSync();
  final names = iosIconVariants
      .map((entry) => entry.$2)
      .whereType<String>()
      .join(' ');
  const primary = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;';
  const generated = 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = AppIcon;';
  final expected = 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "$names";';
  if (primary.allMatches(source).length != 3) {
    throw StateError('Expected three Runner app icon build settings');
  }
  final restored = source.replaceAll(generated, expected);
  if (expected.allMatches(restored).length != 3) {
    throw StateError('Expected three Runner alternate icon build settings');
  }
  if (restored != source) project.writeAsStringSync(restored);
}
