import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/navigation/screens/animated_splash_screen.dart';

void main() {
  testWidgets('uses the native-sized padded splash without resizing', (
    WidgetTester tester,
  ) async {
    bool completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              AnimatedSplashOverlay(
                onComplete: () {
                  completed = true;
                },
              ),
            ],
          ),
        ),
      ),
    );

    final splashImage = tester.widget<Image>(find.byType(Image));
    expect(
      (splashImage.image as AssetImage).assetName,
      'assets/mangabaka_splash.png',
    );
    expect(splashImage.width, 313);
    expect(splashImage.height, 313);
    expect(tester.getSize(find.byType(Image)), const Size.square(313));
    expect(completed, isFalse);

    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(completed, isTrue);
  });
}
