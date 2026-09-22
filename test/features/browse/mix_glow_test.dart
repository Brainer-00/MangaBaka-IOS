import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/features/browse/models/mix_result.dart';
import 'package:mangabaka_app/features/browse/widgets/mix/mix_dna_section.dart';

void main() {
  testWidgets('the DNA bars are flat, with no glow behind them', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MixDnaSection(
              l10n: LocalizationService(),
              dna: const [
                MixDnaTag(tagId: 1, name: 'Fantasy', weight: 1.0),
                MixDnaTag(tagId: 2, name: 'Mystery', weight: 0.6),
                MixDnaTag(tagId: 3, name: 'Drama', weight: 0.3),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Fantasy'), findsOneWidget);

    final shadows = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.boxShadow != null && d.boxShadow!.isNotEmpty);
    expect(shadows, isEmpty);
  });
}
