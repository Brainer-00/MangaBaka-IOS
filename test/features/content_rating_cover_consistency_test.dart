import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/widgets/design/mb_cover.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_suggestions_panel.dart';
import 'package:mangabaka_app/features/home/widgets/home_rail.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cover = 'assets/series_222_cover.jpg';

Series _series(String contentRating) => Series.fromJson({
  'id': '1',
  'title': 'Visible title',
  'content_rating': contentRating,
  'cover': {'x350': _cover},
});

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
  });

  Future<void> pumpCover(
    WidgetTester tester, {
    required String contentRating,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MbCover(
          url: _cover,
          width: 100,
          contentRating: contentRating,
        ),
      ),
    ),
  );

  testWidgets('shared cover follows blur preferences without hiding content', (
    tester,
  ) async {
    await SettingsManager().setBlurredContentRatings(['erotica']);
    await pumpCover(tester, contentRating: 'erotica');

    expect(find.byType(MbCover), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);

    await SettingsManager().setBlurredContentRatings([]);
    await tester.pump();
    expect(find.byType(MbCover), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('shared cover leaves a non-blurred rating clear', (tester) async {
    await SettingsManager().setBlurredContentRatings(['erotica']);
    await pumpCover(tester, contentRating: 'safe');

    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('Home rail blurs a visible affected cover', (tester) async {
    await SettingsManager().setBlurredContentRatings(['erotica']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeRail(title: 'Home', series: [_series('erotica')]),
        ),
      ),
    );

    expect(find.text('Visible title'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('live Search blurs a visible affected result', (tester) async {
    await SettingsManager().setBlurredContentRatings(['erotica']);
    const result = AutocompleteSeriesResult(
      id: 1,
      title: 'Visible result',
      thumbnailUrl: _cover,
      contentRating: 'erotica',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchSuggestionsPanel(
            results: const [result],
            onResultTapped: (_) {},
            showSuggestions: true,
          ),
        ),
      ),
    );

    expect(find.text('Visible result'), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });
}
