import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/widgets/design/mb_badge.dart';
import 'package:mangabaka_app/core/widgets/design/mb_button.dart';
import 'package:mangabaka_app/core/widgets/design/mb_pill.dart';
import 'package:mangabaka_app/core/widgets/design/mb_progress_bar.dart';

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
    'shared controls follow the active palette without losing state',
    (tester) async {
      final active = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(active.dispose);

      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: active,
          builder: (_, palette, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: palette),
            home: Scaffold(
              body: Column(
                children: [
                  const _Counter(),
                  MbPrimaryButton(label: 'Primary', onPressed: () {}),
                  MbSecondaryButton(label: 'Secondary', onPressed: () {}),
                  const MbPill(
                    label: 'Pill',
                    selected: true,
                    trailingText: '3',
                  ),
                  const MbBadge.accent(label: 'Accent'),
                  const MbProgressBar(value: 0.5),
                ],
              ),
            ),
          ),
        ),
      );

      Color buttonColor() => tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: find.byType(MbPrimaryButton),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .decoration!
          .letColor();
      expect(buttonColor(), EirenYuPalette.crimsonMoon);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .valueColor!
            .value,
        EirenYuPalette.dark.progressIndicator,
      );
      final trailingText = tester.widget<Text>(find.text('3'));
      expect(
        MbPalette.contrastRatio(
          trailingText.style!.color!,
          EirenYuPalette.dark.accent,
        ),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.text('Count 0'));
      await tester.pump();

      active.value = EirenYuPalette.light;
      await tester.pumpAndSettle();
      expect(find.text('Count 1'), findsOne);
      expect(buttonColor(), EirenYuPalette.light.accent);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .valueColor!
            .value,
        EirenYuPalette.light.progressIndicator,
      );
      expect(
        MbPalette.contrastRatio(
          tester.widget<Text>(find.text('3')).style!.color!,
          EirenYuPalette.light.accent,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        tester
            .widget<Container>(
              find.descendant(
                of: find.byType(MbBadge),
                matching: find.byType(Container),
              ),
            )
            .decoration,
        isA<BoxDecoration>().having(
          (d) => d.color,
          'fill',
          EirenYuPalette.light.accent,
        ),
      );
    },
  );
}

extension on Decoration {
  Color letColor() => (this as BoxDecoration).color!;
}
