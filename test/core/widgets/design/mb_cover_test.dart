import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/widgets/design/mb_cover.dart';

void main() {
  testWidgets('bounds an unspecified cover decode at physical width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MbCover(url: 'https://example.com/cover.jpg', width: 40),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 120);
  });

  testWidgets('preserves an explicit cover decode bound', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MbCover(
            url: 'https://example.com/cover.jpg',
            width: 40,
            memCacheWidth: 80,
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 80);
  });
}
