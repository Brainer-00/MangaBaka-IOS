import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/constants/mock_series_data.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';

void main() {
  testWidgets('precached sample cover paints on the very first frame',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    );
    await tester.runAsync(
      () => precacheImage(AssetImage(mockSeries222.coverUrl), ctx),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WidgetUtils.networkImage(
          url: mockSeries222.coverUrl,
          width: 100,
          height: 150,
        ),
      ),
    );

    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, isNotNull);
  });

  testWidgets('without precache the first frame has no image', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WidgetUtils.networkImage(
          url: 'assets/mangabaka512.png',
          width: 100,
          height: 150,
        ),
      ),
    );
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, isNull);
  });
}
