import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUpAll(() {
    AppTypography.setTestMode(true);
  });
  tearDownAll(() {
    AppTypography.setTestMode(false);
  });
  await testMain();
}
