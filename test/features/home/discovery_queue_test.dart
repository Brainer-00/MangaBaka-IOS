import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/features/home/controllers/discovery_queue_controller.dart';
import 'package:mangabaka_app/features/home/screens/discovery_queue_screen.dart';
import 'package:mangabaka_app/features/home/services/home_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

Series _makeSeries(String id, String title) => Series(
  id: id,
  state: 'published',
  title: title,
  nativeTitle: '',
  romanizedTitle: '',
  secondaryTitles: const [],
  coverUrl: 'https://example.com/$id.jpg',
  rawCoverUrl: 'https://example.com/$id.jpg',
  authors: const ['Author A'],
  artists: const ['Artist A'],
  description: 'A great description for $title',
  year: '2024',
  status: 'releasing',
  isLicensed: 'no',
  hasAnime: 'no',
  contentRating: 'safe',
  type: 'manga',
  rating: '8.5',
  finalVolume: '',
  totalChapters: '50',
  links: const [],
  publishers: const [],
  genres: const ['Action', 'Fantasy'],
  tags: const ['Magic'],
  lastUpdated: '',
);

class FakeAuthService extends Fake implements ProfileAuthService {
  @override
  int get sessionGeneration => 0;
  bool loggedIn = true;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  MbProfile? get cachedProfile => null;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class FakeHomeService extends Fake implements HomeService {
  bool failForYou = false;
  Completer<List<Series>>? pendingForYou;
  ForYouReadiness? readiness = const ForYouReadiness(
    coldStart: false,
    profileStale: false,
    libraryCount: 15,
  );
  List<Series> forYouSeries = [
    _makeSeries('s1', 'Series One'),
    _makeSeries('s2', 'Series Two'),
  ];

  @override
  Future<ForYouReadiness?> fetchForYouReadiness() async => readiness;

  @override
  Future<List<Series>> fetchForYou({int limit = 20}) async {
    if (pendingForYou != null) return pendingForYou!.future;
    if (failForYou) throw StateError('Fixture failure');
    return forYouSeries;
  }

  @override
  void dispose() {}
}

class FakeLibraryService extends Fake implements LibraryService {
  final List<String> added = [];
  Completer<void>? pendingCreate;

  @override
  Future<void> createLibraryEntry(String seriesId, String state) async {
    added.add('$seriesId:$state');
    if (pendingCreate != null) await pendingCreate!.future;
  }
}

void main() {
  late FakeAuthService auth;
  late FakeHomeService home;
  late FakeLibraryService library;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await resetServiceLocator();
    setupServiceLocator();
  });

  setUp(() {
    DesktopLayout.debugOverride = false;
    auth = FakeAuthService();
    home = FakeHomeService();
    library = FakeLibraryService();

    if (getIt.isRegistered<ProfileAuthService>()) {
      getIt.unregister<ProfileAuthService>();
    }
    getIt.registerSingleton<ProfileAuthService>(auth);
  });

  tearDown(() => DesktopLayout.debugOverride = null);

  group('DiscoveryQueueController', () {
    test('reports not ready if user is logged out', () async {
      auth.loggedIn = false;
      final controller = DiscoveryQueueController(
        homeService: home,
        libraryService: library,
        authService: auth,
      );

      await controller.loadQueue();

      expect(controller.isReady, isFalse);
      expect(controller.errorMessage, 'import_login_required');
      expect(controller.queue, isEmpty);
    });

    test('reports not ready if readiness probe indicates coldStart', () async {
      home.readiness = const ForYouReadiness(
        coldStart: true,
        profileStale: false,
        libraryCount: 1,
      );
      final controller = DiscoveryQueueController(
        homeService: home,
        libraryService: library,
        authService: auth,
      );

      await controller.loadQueue();

      expect(controller.isReady, isFalse);
      expect(controller.queue, isEmpty);
    });

    test('loads recommendations and steps through queue', () async {
      final controller = DiscoveryQueueController(
        homeService: home,
        libraryService: library,
        authService: auth,
      );

      await controller.loadQueue();

      expect(controller.isReady, isTrue);
      expect(controller.totalCount, 2);
      expect(controller.currentIndex, 0);
      expect(controller.currentSeries?.id, 's1');
      expect(controller.remainingCount, 2);
      expect(controller.isCompleted, isFalse);

      // Skip first
      controller.skip();
      expect(controller.currentIndex, 1);
      expect(controller.reviewedCount, 1);
      expect(controller.currentSeries?.id, 's2');
      expect(controller.remainingCount, 1);
      expect(controller.isCompleted, isFalse);

      // Add second
      final added = await controller.addToLibrary('reading');
      expect(added, isTrue);
      expect(library.added, ['s2:reading']);
      expect(controller.currentIndex, 2);
      expect(controller.reviewedCount, 2);
      expect(controller.addedCount, 1);
      expect(controller.isCompleted, isTrue);
    });
  });

  group('DiscoveryQueueScreen', () {
    final palettes = <String, MbPalette>{
      'EirenYu Dark': EirenYuPalette.dark,
      'EirenYu Light': EirenYuPalette.light,
      'Nord Dark': ThemePresets.byId('nord')!.dark!,
      'Catppuccin Light': ThemePresets.byId('catppuccin')!.light!,
      'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
    };

    for (final entry in palettes.entries) {
      testWidgets('${entry.key}: queue surfaces and labels are readable', (
        tester,
      ) async {
        final controller = DiscoveryQueueController(
          homeService: home,
          libraryService: library,
          authService: auth,
        );
        await controller.loadQueue();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: entry.value),
            home: DiscoveryQueueScreen(controller: controller),
          ),
        );
        await tester.pump();
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, entry.value.background);
        final title = tester.widget<Text>(find.text('Series One'));
        expect(
          MbPalette.contrastRatio(title.style!.color!, entry.value.background),
          greaterThanOrEqualTo(4.5),
        );
        final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(
          MbPalette.contrastRatio(progress.color!, progress.backgroundColor!),
          greaterThanOrEqualTo(3),
        );
        final chip = tester.widget<Text>(find.text('MANGA'));
        final chipBackground = Color.alphaBlend(
          entry.value.accent.withValues(alpha: 0.14),
          entry.value.background,
        );
        expect(
          MbPalette.contrastRatio(chip.style!.color!, chipBackground),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('theme changes retain queue position and actions', (
      tester,
    ) async {
      final controller = DiscoveryQueueController(
        homeService: home,
        libraryService: library,
        authService: auth,
      );
      await controller.loadQueue();
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (context, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            themeAnimationDuration: Duration.zero,
            home: DiscoveryQueueScreen(controller: controller),
          ),
        ),
      );
      await tester.tap(find.text('DISCOVERY_QUEUE_SKIP'));
      await tester.pump();
      expect(controller.currentIndex, 1);
      palette.value = EirenYuPalette.light;
      await tester.pump();
      expect(controller.currentSeries?.id, 's2');
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        EirenYuPalette.light.background,
      );
      await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('reading').last);
      await tester.pumpAndSettle();
      expect(library.added, ['s2:reading']);
      expect(controller.isCompleted, isTrue);
      expect(tester.takeException(), isNull);
    });

    for (final entry in <String, MbPalette>{
      'EirenYu Light': EirenYuPalette.light,
      'EirenYu Dark': EirenYuPalette.dark,
    }.entries) {
      testWidgets('${entry.key}: pending add keeps a readable spinner', (
        tester,
      ) async {
        final controller = DiscoveryQueueController(
          homeService: home,
          libraryService: library,
          authService: auth,
        );
        await controller.loadQueue();
        library.pendingCreate = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: entry.value),
            home: DiscoveryQueueScreen(controller: controller),
          ),
        );

        await tester.tap(find.byType(FilledButton).last);
        await tester.pump();

        final button = tester.widget<FilledButton>(
          find.byType(FilledButton).last,
        );
        expect(button.onPressed, isNull);
        final fill = button.style!.backgroundColor!.resolve({
          WidgetState.disabled,
        });
        expect(fill, entry.value.accent);
        final spinner = tester.widget<CircularProgressIndicator>(
          find.descendant(
            of: find.byType(FilledButton).last,
            matching: find.byType(CircularProgressIndicator),
          ),
        );
        expect(
          MbPalette.contrastRatio(spinner.color!, fill!),
          greaterThanOrEqualTo(3),
        );

        library.pendingCreate!.complete();
        await tester.pumpAndSettle();
        expect(library.added, ['s1:plan_to_read']);
        expect(controller.currentIndex, 1);
      });
    }

    testWidgets(
      'loading, not-ready, empty, error and completed states use palette colors',
      (tester) async {
        final colors = EirenYuPalette.light;
        Future<void> show(DiscoveryQueueController controller) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.build(showTooltips: true, palette: colors),
              home: DiscoveryQueueScreen(
                key: ValueKey(controller),
                controller: controller,
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            colors.background,
          );
          expect(tester.takeException(), isNull);
        }

        home.pendingForYou = Completer<List<Series>>();
        var controller = DiscoveryQueueController(
          homeService: home,
          libraryService: library,
          authService: auth,
        );
        final loading = controller.loadQueue();
        await show(controller);
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator),
              )
              .color,
          colors.accentOn(colors.background, minimum: 3),
        );
        home.pendingForYou!.complete(home.forYouSeries);
        await loading;
        home.pendingForYou = null;
        home.readiness = const ForYouReadiness(
          coldStart: true,
          profileStale: false,
          libraryCount: 1,
        );
        controller = DiscoveryQueueController(
          homeService: home,
          libraryService: library,
          authService: auth,
        );
        await controller.loadQueue();
        await show(controller);
        expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
        home.readiness = const ForYouReadiness(
          coldStart: false,
          profileStale: false,
          libraryCount: 15,
        );
        home.forYouSeries = [];
        controller = DiscoveryQueueController(
          homeService: home,
          libraryService: library,
          authService: auth,
        );
        await controller.loadQueue();
        await show(controller);
        expect(find.byIcon(Icons.explore_off_outlined), findsOneWidget);
        home.failForYou = true;
        controller = DiscoveryQueueController(
          homeService: home,
          libraryService: library,
          authService: auth,
        );
        await controller.loadQueue();
        await show(controller);
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
        home.failForYou = false;
        home.forYouSeries = [_makeSeries('s1', 'Series One')];
        controller = DiscoveryQueueController(
          homeService: home,
          libraryService: library,
          authService: auth,
        );
        await controller.loadQueue();
        controller.skip();
        await show(controller);
        expect(find.text('DISCOVERY_QUEUE_COMPLETE_TITLE'), findsOneWidget);
      },
    );
    testWidgets('renders series card and handles skip', (
      WidgetTester tester,
    ) async {
      final controller = DiscoveryQueueController(
        homeService: home,
        libraryService: library,
        authService: auth,
      );
      await controller.loadQueue();

      await tester.pumpWidget(
        MaterialApp(home: DiscoveryQueueScreen(controller: controller)),
      );
      await tester.pump();

      expect(find.text('Series One'), findsOneWidget);
      expect(find.text('DISCOVERY_QUEUE_SKIP'), findsOneWidget);

      // Tap skip
      await tester.tap(find.text('DISCOVERY_QUEUE_SKIP'));
      await tester.pump();

      expect(find.text('Series Two'), findsOneWidget);
    });

    testWidgets('shows completed screen when queue finishes', (
      WidgetTester tester,
    ) async {
      final controller = DiscoveryQueueController(
        homeService: home,
        libraryService: library,
        authService: auth,
      );
      await controller.loadQueue();

      await tester.pumpWidget(
        MaterialApp(home: DiscoveryQueueScreen(controller: controller)),
      );
      await tester.pump();

      // Skip both items
      controller.skip();
      controller.skip();
      await tester.pump();

      expect(find.text('DISCOVERY_QUEUE_COMPLETE_TITLE'), findsOneWidget);
    });

    testWidgets('queue fits narrow portrait and short landscape', (
      tester,
    ) async {
      final controller = DiscoveryQueueController(
        homeService: home,
        libraryService: library,
        authService: auth,
      );
      await controller.loadQueue();
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      for (final size in [const Size(320, 640), const Size(740, 360)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(
              showTooltips: true,
              palette: EirenYuPalette.light,
            ),
            home: DiscoveryQueueScreen(controller: controller),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'viewport $size');
      }
    });
  });
}
