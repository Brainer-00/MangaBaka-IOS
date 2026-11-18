import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/widgets/design/eirenyu_mark.dart';
import 'package:mangabaka_app/core/widgets/eirenyu_startup.dart';

void main() {
  testWidgets('one wave reveals the symbol and the untinted dot', (
    tester,
  ) async {
    const accent = Color(0xFF1296E3);
    const filled = [18, 150, 227, 255];
    const white = [247, 248, 252, 255];
    const neutral = [57, 56, 64, 255];
    const obsidian = [11, 11, 16, 255];
    const boundaryKey = Key('launch-capture');

    Future<void> show(Widget art) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox.square(
              dimension: 320,
              child: ColoredBox(
                color: EirenYuPalette.obsidian,
                child: Center(child: art),
              ),
            ),
          ),
        ),
      ),
    );

    Future<ByteData> capture() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      return (await tester.runAsync(() async {
        final frame = await boundary.toImage();
        try {
          return await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          frame.dispose();
        }
      }))!;
    }

    List<int> rgba(ByteData image, int x, int y) =>
        image.buffer.asUint8List((y * 320 + x) * 4, 4);

    const zero = EirenYuLaunchArtwork(progress: 0, color: accent);
    await show(zero);
    final context = tester.element(find.byKey(boundaryKey));
    await tester.runAsync(
      () => Future.wait([
        precacheImage(EirenYuLaunchArtwork.neutralImage, context),
        precacheImage(EirenYuMark.symbolImage, context),
        precacheImage(EirenYuMark.dotImage, context),
      ]),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byType(EirenYuLaunchArtwork)),
      const Size.square(313.5),
    );
    final empty = await capture();
    expect(rgba(empty, 160, 160), neutral);
    expect(rgba(empty, 205, 151), obsidian);
    expect(rgba(empty, 205, 140), obsidian);

    await show(const EirenYuLaunchArtwork(progress: 0.49, color: accent));
    final belowDot = await capture();
    expect(rgba(belowDot, 160, 233), filled);
    expect(rgba(belowDot, 205, 151), obsidian);
    expect(rgba(belowDot, 205, 140), obsidian);

    await show(const EirenYuLaunchArtwork(progress: 0.58, color: accent));
    final crossingDot = await capture();
    expect(rgba(crossingDot, 109, 150), filled);
    expect(rgba(crossingDot, 205, 151), white);
    expect(rgba(crossingDot, 205, 140), obsidian);
    expect(rgba(crossingDot, 183, 150), obsidian);
    expect(rgba(crossingDot, 72, 224), obsidian);

    await show(const EirenYuLaunchArtwork(progress: 0.72, color: accent));
    final aboveDot = await capture();
    expect(rgba(aboveDot, 205, 151), white);
    expect(rgba(aboveDot, 205, 140), white);

    await show(const EirenYuLaunchArtwork(progress: 1, color: accent));
    final finished = await capture();
    await show(const EirenYuMark(size: 223.75, color: accent));
    expect(
      finished.buffer.asUint8List(),
      (await capture()).buffer.asUint8List(),
    );
    expect(rgba(finished, 160, 160), filled);
    expect(rgba(finished, 205, 140), white);
  });

  for (final stall in [false, true]) {
    testWidgets(
      stall
          ? 'a stalled asset releases startup by its deadline'
          : 'a failed asset releases startup without blocking the destination',
      (tester) async {
        final bundle = _LaunchBundle(stall: stall);
        var dismissed = 0;
        var taps = 0;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _startupHost(
              bundle: bundle,
              onDismissed: () => dismissed++,
              child: TextButton(
                focusNode: focus,
                onPressed: () => taps++,
                child: const Text('Destination'),
              ),
            ),
          );
          // Give the failing bundle's asynchronous error time to report at the
          // current virtual instant. A stalled request has no result to report.
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump();
          }
          if (stall) {
            expect(dismissed, 0);
            expect(focus.canRequestFocus, isFalse);
            expect(find.bySemanticsLabel('Destination'), findsNothing);
            await tester.tap(find.text('Destination'), warnIfMissed: false);
            expect(taps, 0);
            await tester.pump(const Duration(milliseconds: 251));
          }
          await tester.pump();
          expect(dismissed, 1);
          expect(tester.binding.sendFramesToEngine, isTrue);
          expect(find.byType(EirenYuLaunchArtwork), findsNothing);
          expect(focus.canRequestFocus, isTrue);
          expect(find.bySemanticsLabel('Destination'), findsOneWidget);
          await tester.tap(find.text('Destination'));
          expect(taps, 1);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('Reduce Motion shows the destination without decoding the logo', (
    tester,
  ) async {
    final bundle = _LaunchBundle(stall: true);
    var dismissed = 0;
    await tester.pumpWidget(
      _startupHost(
        bundle: bundle,
        onDismissed: () => dismissed++,
        reduceMotion: true,
        child: const Text('Destination'),
      ),
    );
    expect(dismissed, 1);
    expect(bundle.launchReads, 0);
    expect(tester.binding.sendFramesToEngine, isTrue);
    expect(find.byType(EirenYuLaunchArtwork), findsNothing);
  });
}

Widget _startupHost({
  required AssetBundle bundle,
  required VoidCallback onDismissed,
  required Widget child,
  bool reduceMotion = false,
}) => MaterialApp(
  home: Scaffold(
    body: DefaultAssetBundle(
      bundle: bundle,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: EirenYuStartup(
          resolveColor: () => EirenYuPalette.crimsonMoon,
          onDismissed: onDismissed,
          child: Center(child: child),
        ),
      ),
    ),
  ),
);

class _LaunchBundle extends CachingAssetBundle {
  _LaunchBundle({required this.stall});

  final bool stall;
  int launchReads = 0;

  @override
  Future<ByteData> load(String key) {
    if (key != EirenYuLaunchArtwork.neutralImage.assetName) {
      return rootBundle.load(key);
    }
    launchReads++;
    return stall
        ? Completer<ByteData>().future
        : Future.error(StateError('Missing test launch artwork'));
  }
}
