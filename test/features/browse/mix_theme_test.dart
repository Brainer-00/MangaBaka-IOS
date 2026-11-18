import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/browse/controllers/mix_controller.dart';
import 'package:mangabaka_app/features/browse/models/mix_result.dart';
import 'package:mangabaka_app/features/browse/screens/mix_screen.dart';
import 'package:mangabaka_app/features/browse/services/mix_service.dart';
import 'package:mangabaka_app/features/browse/widgets/mix/mix_dna_section.dart';
import 'package:mangabaka_app/features/browse/widgets/mix/mix_options_section.dart';
import 'package:mangabaka_app/features/browse/widgets/mix/mix_seed_section.dart';
import 'package:mangabaka_app/features/browse/widgets/mix/mix_state_views.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MixService extends Fake implements MixService {
  int requests = 0;

  @override
  Future<MixResult> fetchMix({
    required List<int> seriesIds,
    int limit = 24,
    List<String>? contentRating,
    List<String>? notContentRating,
    bool strict = false,
    String? blendUserId,
    String? excludeUserLibrary,
  }) async {
    requests++;
    return const MixResult(series: [], dna: [], seedCount: 1);
  }

  @override
  Future<List<AutocompleteSeriesResult>> fetchSeedSuggestions(
    List<int> seriesIds,
  ) async => const [
    AutocompleteSeriesResult(id: 3, title: 'Suggested', thumbnailUrl: ''),
  ];
}

class _LoggedOutAuth extends Fake implements ProfileAuthService {
  @override
  bool get isLoggedIn => false;
}

Series _series(int id) => Series.fromJson({
  'id': '$id',
  'title': 'Seed $id',
  'content_rating': 'safe',
});

Widget _app(MbPalette colors, Widget child) => MaterialApp(
  theme: AppTheme.build(showTooltips: true, palette: colors),
  themeAnimationDuration: Duration.zero,
  home: Scaffold(body: child),
);

BoxDecoration _box(Container container) =>
    container.decoration! as BoxDecoration;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MixService service;

  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
    service = _MixService();
    getIt.registerSingleton<MixService>(service);
    getIt.registerSingleton<ProfileAuthService>(_LoggedOutAuth());
  });

  final palettes = <MbPalette>[
    EirenYuPalette.dark,
    EirenYuPalette.light,
    ThemePresets.byId('nord')!.dark!,
    ThemePresets.byId('catppuccin')!.light!,
    EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  ];

  testWidgets('Mix screen follows palette and retains search and options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final palette = ValueNotifier<MbPalette>(palettes.first);
    addTearDown(palette.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<MbPalette>(
        valueListenable: palette,
        builder: (_, colors, _) => _app(colors, const MixScreen()),
      ),
    );

    final field = find.byType(TextField);
    await tester.enterText(field, 'a');
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);

    for (final colors in palettes) {
      palette.value = colors;
      await tester.pump();
      final mixScaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(MixScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(mixScaffold.backgroundColor, colors.background);
      expect(tester.widget<TextField>(field).controller!.text, 'a');
      expect(tester.widget<TextField>(field).style!.color, colors.text);
      expect(tester.widget<Text>(find.text('MIX')).style!.color, colors.text);
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
      expect(find.byType(MixEmptyState), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(service.requests, 0);
    tester.view.physicalSize = const Size(700, 320);
    await tester.pump();
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      palette.value.background,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('DNA card, bars and chips follow all palettes with contrast', (
    tester,
  ) async {
    const dna = [
      MixDnaTag(tagId: 1, name: 'Fantasy', weight: 1),
      MixDnaTag(tagId: 2, name: 'Drama', weight: .8),
      MixDnaTag(tagId: 3, name: 'Mystery', weight: .6),
      MixDnaTag(tagId: 4, name: 'Action', weight: .4),
      MixDnaTag(tagId: 5, name: 'Comedy', weight: .2),
      MixDnaTag(tagId: 6, name: 'Adventure', weight: .1),
    ];
    for (final colors in palettes) {
      await tester.pumpWidget(
        _app(
          colors,
          SingleChildScrollView(
            child: MixDnaSection(dna: dna, l10n: LocalizationService()),
          ),
        ),
      );
      final boxes = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(MixDnaSection),
              matching: find.byType(Container),
            ),
          )
          .map(_box)
          .toList();
      expect(boxes.any((box) => box.color == colors.surface), isTrue);
      expect(boxes.any((box) => box.color == colors.surfaceRaised), isTrue);
      expect(boxes.any((box) => box.color == colors.progressIndicator), isTrue);
      expect(
        MbPalette.contrastRatio(colors.progressIndicator, colors.surfaceRaised),
        greaterThanOrEqualTo(3),
      );
      final percent = tester.widget<Text>(find.text('100%'));
      expect(
        MbPalette.contrastRatio(percent.style!.color!, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(find.text('Adventure'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('options keep readable login state and functional switch', (
    tester,
  ) async {
    final controller = MixController();
    addTearDown(controller.dispose);
    for (final colors in palettes) {
      await tester.pumpWidget(
        _app(
          colors,
          SingleChildScrollView(
            child: MixOptionsSection(
              controller: controller,
              l10n: LocalizationService(),
            ),
          ),
        ),
      );
      final disabled = tester.widget<Text>(find.text('Requires login').first);
      final card = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(MixOptionsSection),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(_box(card).color, colors.surface);
      expect(
        MbPalette.contrastRatio(disabled.style!.color!, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches[1].onChanged, isNull);
      expect(switches[2].onChanged, isNull);
      expect(
        switches.first.activeTrackColor,
        colors.accentOn(colors.surface, minimum: 3),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(controller.strictMode, isTrue);
  });

  testWidgets('seed search, suggestions, removal and states stay themed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MixController();
    addTearDown(controller.dispose);
    final search = TextEditingController();
    final focus = FocusNode();
    addTearDown(search.dispose);
    addTearDown(focus.dispose);
    controller.addSeed(_series(1));
    controller.addSeed(_series(2));
    await tester.runAsync(
      () async => await Future<void>.delayed(Duration.zero),
    );
    var removed = 0;
    var added = 0;
    for (final colors in [EirenYuPalette.dark, EirenYuPalette.light]) {
      await tester.pumpWidget(
        _app(
          colors,
          SingleChildScrollView(
            child: MixSeedSection(
              controller: controller,
              l10n: LocalizationService(),
              searchController: search,
              searchFocus: focus,
              suggestions: const [],
              showSuggestions: false,
              onSeedTap: (_) {},
              onSeedRemove: (seed) {
                removed++;
                controller.removeSeed(seed);
              },
              onSuggestionSelected: (_) {},
              onSuggestedSeedAdded: (_) => added++,
              onClearSearch: search.clear,
            ),
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.fillColor, colors.surfaceRaised);
      expect(
        MbPalette.contrastRatio(
          field.decoration!.hintStyle!.color!,
          colors.surfaceRaised,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(find.text('Seed 1'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Suggested')).style!.color,
        colors.text,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Suggested'));
    expect(added, 1);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    expect(removed, 1);

    for (final colors in palettes) {
      await tester.pumpWidget(
        _app(
          colors,
          Column(
            children: [
              Expanded(child: MixEmptyState(l10n: LocalizationService())),
              Expanded(child: MixLoadingState(l10n: LocalizationService())),
              Expanded(child: MixNoResultsState(l10n: LocalizationService())),
            ],
          ),
        ),
      );
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator).first,
      );
      expect(
        MbPalette.contrastRatio(spinner.color!, colors.background),
        greaterThanOrEqualTo(3),
      );
      expect(tester.takeException(), isNull);
    }
    var retries = 0;
    for (final colors in palettes) {
      await tester.pumpWidget(
        _app(
          colors,
          MixErrorState(l10n: LocalizationService(), onRetry: () => retries++),
        ),
      );
      final retry = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(
        MbPalette.contrastRatio(
          retry.style!.foregroundColor!.resolve({})!,
          retry.style!.backgroundColor!.resolve({})!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.byType(ElevatedButton));
      expect(tester.takeException(), isNull);
    }
    expect(retries, palettes.length);
  });
}
