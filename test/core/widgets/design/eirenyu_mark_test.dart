import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/widgets/design/eirenyu_mark.dart';
import 'package:mangabaka_app/core/widgets/design/mb_icons.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_sign_in_prompt.dart';
import 'package:mangabaka_app/features/navigation/models/nav_destinations.dart';
import 'package:mangabaka_app/features/navigation/widgets/main_nav_rail.dart';
import 'package:mangabaka_app/features/navigation/widgets/main_top_nav_bar.dart';

void main() {
  testWidgets('mark renders the requested accent and keeps the dot white', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const boundaryKey = Key('mark-boundary');

    Future<void> verifyMark(EirenYuMark mark, List<int> accent) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Center(
            child: RepaintBoundary(key: boundaryKey, child: mark),
          ),
        ),
      );
      final markFinder = find.byType(EirenYuMark);
      final context = tester.element(markFinder);
      final layers = tester.widgetList<Image>(
        find.descendant(of: markFinder, matching: find.byType(Image)),
      );
      expect(layers, hasLength(2));
      await tester.runAsync(() async {
        for (final layer in layers) {
          await precacheImage(layer.image, context);
        }
      });
      await tester.pump();

      expect(find.bySemanticsLabel('EirenYu'), findsOneWidget);
      expect(tester.getSize(markFinder), const Size.square(128));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final frame = await boundary.toImage();
        try {
          final pixels = (await frame.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          List<int> rgba(int x, int y) {
            final offset = (y * frame.width + x) * 4;
            return pixels.sublist(offset, offset + 4);
          }

          expect(rgba(64, 64), accent);
          expect(rgba(89, 56), [247, 248, 252, 255]);
          expect(rgba(8, 64), [11, 11, 16, 255]);
        } finally {
          frame.dispose();
        }
      });
    }

    try {
      await verifyMark(const EirenYuMark(size: 128), [168, 47, 79, 255]);
      await verifyMark(const EirenYuMark(size: 128, color: Color(0xFF12AB34)), [
        18,
        171,
        52,
        255,
      ]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('branded tablet rail still selects the Browse destination', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainNavRail(
            selectedIndex: NavTabs.home,
            onDestinationSelected: (index) => selected = index,
            l10n: LocalizationService(),
            side: NavRailSide.left,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(EirenYuMark)), const Size.square(36));
    await tester.tap(find.byIcon(MbIcons.compass));
    expect(selected, NavTabs.browse);
  });

  testWidgets('branded top bar still selects the Browse destination', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: MainTopNavBar(
            selectedIndex: NavTabs.home,
            onDestinationSelected: (index) => selected = index,
            l10n: LocalizationService(),
            showSearchField: false,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(EirenYuMark)), const Size.square(28));
    await tester.tap(find.byIcon(MbIcons.compass));
    expect(selected, NavTabs.browse);
  });

  testWidgets('desktop sign-in prompt displays the mark and forwards login', (
    tester,
  ) async {
    var loggedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopSignInPrompt(
            title: 'Profile',
            message: 'Sign in with MangaBaka',
            onLogin: () => loggedIn = true,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(EirenYuMark)), const Size.square(56));
    await tester.tap(find.byIcon(Icons.login_rounded));
    expect(loggedIn, isTrue);
  });
}
