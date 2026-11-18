import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/core/widgets/app_snack_bar.dart';
import 'package:mangabaka_app/core/widgets/design/mb_nav.dart';
import 'package:mangabaka_app/core/widgets/design/mb_screen_header.dart';
import 'package:mangabaka_app/core/widgets/design/mb_starburst_button.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('Count $count'),
  );
}

void main() {
  testWidgets(
    'navigation and shared chrome follow themes without losing state',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      var selected = 0;
      var ctaCalls = 0;
      const destinations = [
        MbNavDestination(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Home',
        ),
        MbNavDestination(
          icon: Icons.book_outlined,
          selectedIcon: Icons.book,
          label: 'Library',
        ),
      ];

      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (_, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            home: Scaffold(
              appBar: mbScreenAppBar(title: 'Now'),
              body: Column(
                children: [
                  const _Counter(),
                  const MbSectionHeader(title: 'For You'),
                  MbStarburstButton(label: 'Read', onPressed: () => ctaCalls++),
                ],
              ),
              bottomNavigationBar: MbBottomNav(
                destinations: destinations,
                selectedIndex: selected,
                onDestinationSelected: (index) => selected = index,
              ),
            ),
          ),
        ),
      );

      for (final colors in [
        EirenYuPalette.dark,
        EirenYuPalette.light,
        ThemePresets.byId('nord')!.dark!,
      ]) {
        palette.value = colors;
        await tester.pumpAndSettle();
        final nav = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(MbBottomNav),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(nav.color, colors.background);
        final icons = tester
            .widgetList<Icon>(
              find.descendant(
                of: find.byType(MbBottomNav),
                matching: find.byType(Icon),
              ),
            )
            .toList();
        expect(icons[0].color, colors.onAccent);
        expect(icons[1].color, colors.textMuted);
        expect(
          MbPalette.contrastRatio(icons[0].color!, colors.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          MbPalette.contrastRatio(icons[1].color!, colors.background),
          greaterThanOrEqualTo(3),
        );
        expect(tester.widget<Text>(find.text('NOW')).style!.color, colors.text);
        expect(
          tester.widget<Text>(find.text('FOR YOU')).style!.color,
          colors.text,
        );
        expect(
          tester.widget<Text>(find.text('READ')).style!.color,
          colors.onAccent,
        );
        expect(
          tester
              .widget<CustomPaint>(
                find
                    .descendant(
                      of: find.byType(MbStarburstButton),
                      matching: find.byType(CustomPaint),
                    )
                    .first,
              )
              .painter,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Count 0'));
      await tester.pump();
      palette.value = EirenYuPalette.dark;
      await tester.pumpAndSettle();
      expect(find.text('Count 1'), findsOneWidget);
      await tester.tap(find.text('READ'));
      expect(ctaCalls, 1);
      await tester.tap(find.byIcon(Icons.book_outlined));
      expect(selected, 1);
    },
  );

  testWidgets('snackbar foregrounds contrast with its actual background', (
    tester,
  ) async {
    for (final colors in [
      EirenYuPalette.dark,
      EirenYuPalette.light,
      ThemePresets.byId('nord')!.dark!,
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AppSnackBar.show(
                  context,
                  'Saved',
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () {},
                    textColor: colors.accent,
                  ),
                ),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, colors.surfaceRaised);
      final message = tester.widget<Text>(find.text('Saved'));
      expect(
        MbPalette.contrastRatio(message.style!.color!, colors.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.check_circle_outline_rounded),
      );
      expect(
        MbPalette.contrastRatio(icon.color!, colors.surfaceRaised),
        greaterThanOrEqualTo(3),
      );
      final action = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Undo'),
      );
      final actionColor = action.style!.foregroundColor!.resolve({})!;
      expect(
        MbPalette.contrastRatio(actionColor, colors.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
      await tester.pumpAndSettle();
    }
  });
}
