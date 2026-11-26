import '../../support/library_identity.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_presets.dart';
import 'package:mangabaka_app/features/series/screens/series_detail_screen.dart';
import 'package:mangabaka_app/features/series/widgets/app_bar/glass_control.dart';
import 'package:mangabaka_app/features/series/widgets/app_bar/series_banner_background.dart';
import 'package:mangabaka_app/features/series/widgets/series_hero.dart';
import 'package:mangabaka_app/features/series/widgets/series_action_bar.dart';
import 'package:mangabaka_app/features/series/widgets/series_detail_fab.dart';
import 'package:mangabaka_app/features/series/widgets/series_my_list_card.dart';
import 'package:mangabaka_app/features/series/widgets/series_quick_action_button.dart';
import 'package:mangabaka_app/features/series/widgets/chip.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/features/library/widgets/library_entry_editor_sheet.dart';
import 'package:mangabaka_app/features/series/services/series_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:drift/native.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series_link.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/features/series/services/series_search_service.dart';
import 'package:mangabaka_app/features/series/models/series_cover.dart';
import 'package:mangabaka_app/features/news/models/news.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';
import 'package:mangabaka_app/features/series/models/series_work.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';

class MockSeriesService extends Fake implements SeriesService {
  Series? seriesResponse;
  Object? error;
  bool fetchSeriesCalled = false;
  int fetchSeriesCalls = 0;
  bool fetchCoversCalled = false;
  bool delayFetch = false;

  @override
  Future<List<SeriesLink>> fetchSeriesLinks(String id) async => [];

  @override
  Future<Series> fetchSeries(String id) async {
    fetchSeriesCalled = true;
    fetchSeriesCalls++;
    if (delayFetch) await Future.delayed(const Duration(milliseconds: 100));
    if (error != null) throw error!;
    return seriesResponse ??
        Series.fromJson({
          'id': id,
          'title': 'Fetched Title',
          'description': 'Fetched Description',
        });
  }

  @override
  get logger => LoggingService.logger;

  @override
  Future<List<SeriesCover>> fetchSeriesCovers(String id) async {
    fetchCoversCalled = true;
    return [];
  }

  @override
  Future<List<Series>> fetchSeriesRelated(String id) async => [];
  @override
  Future<List<News>> fetchSeriesNews(String id) async => [];
  @override
  Future<List<SeriesCollection>> fetchSeriesCollections(String id) async => [];
  @override
  Future<List<SeriesWork>> fetchSeriesWorks(String id) async => [];
}

class MockLibraryService extends Fake implements LibraryService {
  final _controller = StreamController<LibraryEntry?>.broadcast(sync: true);
  LibraryEntry? currentEntry;
  LibraryEntry? authoritativeEntry;
  LibraryEntryDraft? createdDraft;
  bool deleteCalled = false;
  int? lastProgressChapter;
  bool failProgress = false;

  @override
  Stream<LibraryEntry?> watchEntryFromDb(String id) {
    return Stream.multi((controller) {
      controller.add(currentEntry);
      final sub = _controller.stream.listen(controller.add);
      controller.onCancel = () => sub.cancel();
    }, isBroadcast: true);
  }

  @override
  Future<LibraryEntry?> fetchAuthoritativeLibraryEntry(
    String seriesId, {
    LibraryCacheLease? lease,
  }) async => authoritativeEntry ?? currentEntry;

  @override
  Future<List<AccountLibraryList>> fetchAccountLibraryLists(
    LibraryCacheLease lease,
  ) async => [];

  @override
  Future<LibrarySaveResult> createCompleteLibraryEntry(
    LibraryEntryDraft draft,
  ) async {
    createdDraft = draft;
    final id = draft.seriesId;
    currentEntry = LibraryEntry(
      id: id,
      state: draft.state.value!,
      series: Series.fromJson({'id': id, 'title': 'Test Manga'}),
    );
    _controller.add(currentEntry);
    return LibrarySaveResult(LibrarySaveOutcome.saved, entry: currentEntry);
  }

  @override
  Future<void> deleteEntry(String id) async {
    deleteCalled = true;
    currentEntry = null;
    _controller.add(null);
  }

  @override
  Future<void> updateLibraryEntryProgress(
    String seriesId, {
    int? progressChapter,
    int? progressVolume,
  }) async {
    lastProgressChapter = progressChapter;
    if (failProgress) throw StateError('progress failed');
  }
}

class MockProfileAuthService extends ChangeNotifier with WidgetLibraryIdentity {
  bool _isLoggedIn = false;
  LibraryCacheLease? suppliedLease;
  bool useSuppliedLease = false;
  @override
  LibraryCacheLease? get libraryLease =>
      useSuppliedLease ? suppliedLease : super.libraryLease;
  @override
  final ValueNotifier<bool> awaitingBrowser = ValueNotifier(false);
  @override
  void cancelLogin() {}
  @override
  Future<void> reopenBrowser() async {}
  @override
  bool get isLoggedIn => _isLoggedIn;
  set isLoggedIn(bool value) {
    _isLoggedIn = value;
    notifyListeners();
  }

  @override
  MbProfile? get cachedProfile => null;

  @override
  Future<void> init() async {}
  @override
  Future<void> login() async {}
  @override
  Future<void> logout() async {}
  @override
  Future<bool> hasSession() async => _isLoggedIn;
  @override
  Future<MbProfile> fetchProfile({bool forceRefresh = false}) async =>
      MbProfile(id: '1', role: 'user', scopes: []);
  @override
  Future<String> getValidAccessToken() async => 'token';
  @override
  Future<String> recoverAfterUnauthorized(String rejectedAccessToken) async =>
      'token';
}

void main() {
  setUpAll(prepareWidgetLibraryIdentity);
  late MockSeriesService mockSeriesService;
  late MockLibraryService mockLibraryService;
  late MockProfileAuthService mockAuthService;
  AppDatabase? db;

  final testSeries = Series.fromJson({
    'id': '123',
    'title': 'Test Manga',
    'native_title': 'Native',
    'description': 'Description',
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            return '.';
          },
        );
    SharedPreferences.setMockInitialValues({});
    await resetServiceLocator();
    await SettingsManager().init();

    mockSeriesService = MockSeriesService();
    mockLibraryService = MockLibraryService();
    mockAuthService = MockProfileAuthService();
    db = AppDatabase.forTesting(NativeDatabase.memory());

    getIt.registerSingleton<LoggingService>(LoggingService());
    getIt.registerSingleton<AppDatabase>(db!);
    getIt.registerSingleton<SeriesService>(mockSeriesService);
    getIt.registerSingleton<LibraryService>(mockLibraryService);
    getIt.registerSingleton<ProfileAuthService>(mockAuthService);
    getIt.registerSingleton<MetadataService>(MetadataService());
    getIt.registerSingleton<SeriesSearchService>(SeriesSearchService());
  });

  tearDown(() async {
    await db?.close();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(home: SeriesDetailScreen(series: testSeries));
  }

  testWidgets('SeriesDetailScreen renders fetched info on success', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();
    expect(find.text('Fetched Title'), findsAtLeast(1));
  });

  for (final paletteCase in <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'custom accent': EirenYuPalette.light.withAccent(const Color(0xFF808080)),
  }.entries) {
    final palette = paletteCase.value;
    testWidgets('selected genre chip stays readable in ${paletteCase.key}', (
      tester,
    ) async {
      final series = Series.fromJson({
        'id': 'genre-series',
        'title': 'Genre Fixture',
        'genres': ['Fantasy'],
      });
      mockSeriesService.seriesResponse = series;
      final screenKey = GlobalKey<SeriesDetailScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: SeriesDetailScreen(key: screenKey, series: series),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fantasy'));
      await tester.longPress(find.text('Fantasy'));
      // Filter mode starts a repeating marching-ants animation, so settle the
      // drawer transition explicitly rather than waiting for all frames.
      await tester.pump(const Duration(milliseconds: 350));

      expect(screenKey.currentState!.drawerFilters!.genre, contains('Fantasy'));
      final chip = tester.widget<ChipBase>(
        find.ancestor(
          of: find.text('Fantasy'),
          matching: find.byType(ChipBase),
        ),
      );
      expect(chip.backgroundColor, palette.accent);
      final foreground = tester
          .widget<Text>(find.text('Fantasy'))
          .style!
          .color!;
      expect(
        MbPalette.contrastRatio(foreground, palette.accent),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('progress dialog uses the freshest fetched series total', (
    tester,
  ) async {
    mockAuthService.isLoggedIn = true;
    final key = GlobalKey<SeriesDetailScreenState>();
    final initial = Series.fromJson({
      'id': '123',
      'title': 'Test Manga',
      'description': 'Initial description',
      'total_chapters': '120',
    });
    mockSeriesService.seriesResponse = Series.fromJson({
      'id': '123',
      'title': 'Test Manga',
      'description': 'Fresh description',
      'total_chapters': '121',
    });
    final entry = LibraryEntry(
      id: 'entry-123',
      state: 'reading',
      progressChapter: 2,
      series: initial,
    );
    mockLibraryService.currentEntry = entry;

    await tester.pumpWidget(
      MaterialApp(
        home: SeriesDetailScreen(key: key, series: initial),
      ),
    );
    await tester.pumpAndSettle();

    expect(key.currentState!.series.totalChapters, '121');
    key.currentState!.showUpdateProgressDialog(entry, isChapter: true);
    await tester.pumpAndSettle();

    expect(find.text('total: 121'), findsOneWidget);
  });

  testWidgets('Series Detail drops private tracking after an account switch', (
    tester,
  ) async {
    final dao = db!.ownedLibraryDao;
    final a = await tester.runAsync(() async {
      final lease = await dao.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId('A'),
      );
      await dao.finishFullImport(
        lease,
        completeSeriesIds: {'123'},
        watermark: null,
        entries: [
          LibraryEntry(
            id: 'private-a',
            state: 'completed',
            rating: 90,
            series: testSeries,
          ),
        ],
      );
      return lease;
    });
    mockAuthService
      ..useSuppliedLease = true
      ..suppliedLease = a
      ..isLoggedIn = true;
    await getIt.unregister<LibraryService>();
    final service = LibraryService(auth: mockAuthService, database: db);
    getIt.registerSingleton<LibraryService>(
      service,
      dispose: (s) => s.dispose(),
    );
    await tester.pumpWidget(
      MaterialApp(home: SeriesDetailScreen(series: testSeries)),
    );
    await tester.runAsync(
      () =>
          service.watchEntryFromDb('123').firstWhere((entry) => entry != null),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SeriesMyListCard), findsOneWidget);

    mockAuthService
      ..suppliedLease = null
      ..isLoggedIn = false;
    await tester.pump();
    expect(find.byType(SeriesMyListCard), findsNothing);
    final b = await tester.runAsync(() async {
      final lease = await dao.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId('B'),
      );
      await dao.finishFullImport(lease, completeSeriesIds: {}, watermark: null);
      return lease;
    });
    mockAuthService
      ..suppliedLease = b
      ..isLoggedIn = true;
    await tester.pumpAndSettle();
    expect(find.byType(SeriesMyListCard), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(() => db!.close());
    db = null;
  });

  testWidgets('SeriesDetailScreen shows error banner on fetch failure', (
    WidgetTester tester,
  ) async {
    mockSeriesService.error = Exception('Network error');
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();
    expect(find.text('failed_to_load'), findsOneWidget);

    mockSeriesService.error = null;
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    expect(mockSeriesService.fetchSeriesCalled, isTrue);
  });

  testWidgets(
    'SeriesDetailScreen allows adding to library when logged in (wide: sidebar button, no FAB)',
    (WidgetTester tester) async {
      mockAuthService.isLoggedIn = true;
      await SettingsManager().setAddLibraryDefaultTab('paused');

      // Set a large viewport for widget tests
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('add_to_library_button'));
      expect(find.byKey(const Key('add_to_library_fab')), findsNothing);
      expect(fabFinder, findsOneWidget);

      // Use standard tap instead of tapAt to be more robust
      await tester.tap(fabFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(LibraryEntryEditorSheet), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(mockLibraryService.createdDraft, isNull);
      await tester.tap(find.text(LocalizationService().translate('save')));
      await tester.pumpAndSettle();
      expect(mockLibraryService.createdDraft?.seriesId, testSeries.id);
      expect(mockLibraryService.createdDraft?.toJson(), {'state': 'paused'});
      expect(find.byType(SeriesMyListCard), findsOneWidget);
    },
  );

  testWidgets(
    'SeriesDetailScreen allows adding to library when logged in (phone: FAB)',
    (WidgetTester tester) async {
      mockAuthService.isLoggedIn = true;

      // Set a large viewport for widget tests
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1.0;
      await tester.pump();
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const Key('add_to_library_fab'));
      expect(fabFinder, findsOneWidget);
      expect(
        tester.widget<FloatingActionButton>(fabFinder).onPressed,
        isNotNull,
      );

      // Use standard tap instead of tapAt to be more robust
      await tester.tap(fabFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(LibraryEntryEditorSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(mockLibraryService.createdDraft, isNull);
      await tester.tap(find.text(LocalizationService().translate('cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryEntryEditorSheet), findsNothing);
      expect(mockLibraryService.createdDraft, isNull);
    },
  );

  for (final width in [500.0, 1200.0]) {
    testWidgets('tracking-card pencil opens the editor at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() => tester.view.reset());
      mockAuthService.isLoggedIn = true;
      mockLibraryService.currentEntry = LibraryEntry(
        id: '7',
        state: 'reading',
        progressChapter: 3,
        series: testSeries,
      );
      mockLibraryService.authoritativeEntry = LibraryEntry(
        id: '7',
        state: 'reading',
        progressChapter: 48,
        series: testSeries,
      );
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();
      final pencil = find.byTooltip(
        LocalizationService().translate('library_editor_edit'),
      );
      await tester.ensureVisible(pencil);
      await tester.tap(pencil);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryEntryEditorSheet), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(mockLibraryService.createdDraft, isNull);
    });
  }

  testWidgets('SeriesDetailScreen fetches tab data when switching tabs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.reset());

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    final coverTabFinder = find.text('COVERS');
    await tester.ensureVisible(coverTabFinder);
    await tester.pumpAndSettle();

    await tester.tap(coverTabFinder);
    await tester.pumpAndSettle();
    expect(mockSeriesService.fetchCoversCalled, isTrue);
  });

  final palettes = <String, MbPalette>{
    'EirenYu Dark': EirenYuPalette.dark,
    'EirenYu Light': EirenYuPalette.light,
    'Nord': ThemePresets.byId('nord')!.dark!,
    'custom accent': EirenYuPalette.dark.withAccent(const Color(0xFF808080)),
  };

  for (final entry in palettes.entries) {
    testWidgets('${entry.key} detail chrome and banner follow the palette', (
      tester,
    ) async {
      final palette = entry.value;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: palette),
          home: SeriesDetailScreen(series: testSeries),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        palette.background,
      );
      expect(
        tester.widget<SliverAppBar>(find.byType(SliverAppBar)).backgroundColor,
        palette.background,
      );

      final banner = find.byType(SeriesBannerBackground);
      final bannerStack = tester.widget<Stack>(
        find.descendant(of: banner, matching: find.byType(Stack)).first,
      );
      expect(
        (bannerStack.children.first as Container).color,
        palette.surfaceRaised,
      );
      final fallback = tester.widgetList<Container>(
        find.descendant(of: banner, matching: find.byType(Container)),
      );
      final fade = fallback
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>()
          .firstWhere((gradient) => gradient.stops?.length == 4);
      expect(fade.colors.last, palette.background);
      final bannerTitle = tester.widget<Text>(
        find.descendant(
          of: find.byType(SeriesTitleBlock),
          matching: find.text('FETCHED TITLE'),
        ),
      );
      expect(bannerTitle.style?.color, palette.text);
      expect(
        MbPalette.contrastRatio(bannerTitle.style!.color!, palette.background),
        greaterThanOrEqualTo(4.5),
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final collapsedTitle = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SliverAppBar),
              matching: find.byType(Text),
            ),
          )
          .where((text) => text.data == 'Fetched Title')
          .first;
      expect(collapsedTitle.style?.color, palette.text);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${entry.key} glass controls stay readable over cover extremes',
      (tester) async {
        final palette = entry.value;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: palette),
            home: Scaffold(
              body: GlassControl(
                onTap: () {},
                icon: Icons.arrow_back,
                label: 'Back',
              ),
            ),
          ),
        );
        final control = find.byType(GlassControl);
        final glass = tester.widget<Container>(
          find.descendant(of: control, matching: find.byType(Container)).first,
        );
        final fill = (glass.decoration! as BoxDecoration).color!;
        final icon = tester.widget<Icon>(
          find.descendant(of: control, matching: find.byType(Icon)),
        );
        final label = tester.widget<Text>(
          find.descendant(of: control, matching: find.text('Back')),
        );
        expect(fill, palette.surface.withValues(alpha: 0.94));
        expect(label.style?.color, icon.color);
        for (final artwork in [Colors.black, Colors.white]) {
          expect(
            MbPalette.contrastRatio(
              icon.color!,
              Color.alphaBlend(fill, artwork),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: palette),
            home: Scaffold(
              body: GlassControl(
                onTap: () {},
                icon: Icons.arrow_back,
                label: 'Back',
                showBg: false,
              ),
            ),
          ),
        );
        final collapsedIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(GlassControl),
            matching: find.byType(Icon),
          ),
        );
        expect(
          MbPalette.contrastRatio(collapsedIcon.color!, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'live palette switch keeps detail state, tab and scroll position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() => tester.view.reset());
      final palette = ValueNotifier<MbPalette>(EirenYuPalette.dark);
      addTearDown(palette.dispose);
      final key = GlobalKey<SeriesDetailScreenState>();
      final detail = SeriesDetailScreen(key: key, series: testSeries);
      await tester.pumpWidget(
        ValueListenableBuilder<MbPalette>(
          valueListenable: palette,
          builder: (context, colors, _) => MaterialApp(
            theme: AppTheme.build(showTooltips: true, palette: colors),
            home: detail,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState;
      final fetches = mockSeriesService.fetchSeriesCalls;
      final covers = find.text('COVERS');
      await tester.ensureVisible(covers);
      await tester.pumpAndSettle();
      await tester.tap(covers);
      await tester.pumpAndSettle();
      expect(state!.selectedTab, 'Covers');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final offset = scroll.position.pixels;
      expect(offset, greaterThan(0));

      palette.value = EirenYuPalette.light;
      await tester.pumpAndSettle();
      expect(key.currentState, same(state));
      expect(state.selectedTab, 'Covers');
      expect(scroll.position.pixels, closeTo(offset, 1));
      expect(mockSeriesService.fetchSeriesCalls, fetches);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
        EirenYuPalette.light.background,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail chrome fits short landscape without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.reset());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          showTooltips: true,
          palette: EirenYuPalette.light,
        ),
        home: SeriesDetailScreen(series: testSeries),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final entry in palettes.entries) {
    testWidgets('${entry.key} tracking actions and FAB keep readable colors', (
      tester,
    ) async {
      final colors = entry.value;
      final series = Series.fromJson({
        'id': '123',
        'title': 'Test Manga',
        'total_chapters': '12',
      });
      final libraryEntry = LibraryEntry(
        id: '123',
        state: 'reading',
        rating: 40,
        progressChapter: 2,
        series: series,
      );
      mockAuthService.isLoggedIn = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            body: Column(
              children: [
                SeriesActionBar(
                  series: series,
                  entry: libraryEntry,
                  onStateChanged: (_) {},
                  onRatingChanged: (_) {},
                  onUpdateChapter: () {},
                  onUpdateVolume: () {},
                  l10n: LocalizationService(),
                ),
                SeriesQuickActionButton(series: series, entry: libraryEntry),
                const SeriesAddToLibraryButton(editorOpen: true, onAdd: _noop),
              ],
            ),
            floatingActionButton: SeriesDetailFAB(
              entryStream: Stream.value(null),
              editorOpen: false,
              onAdd: _noop,
            ),
          ),
        ),
      );
      await tester.pump();

      final progressIcon = tester.widget<Icon>(
        find.byIcon(Icons.menu_book_outlined),
      );
      expect(
        MbPalette.contrastRatio(progressIcon.color!, colors.surface),
        greaterThanOrEqualTo(3),
      );
      final plusOne = tester.widget<Text>(find.text('+1'));
      expect(plusOne.style?.color, colors.onAccent);
      expect(
        MbPalette.contrastRatio(plusOne.style!.color!, colors.accent),
        greaterThanOrEqualTo(4.5),
      );
      final fab = tester.widget<FloatingActionButton>(
        find.byKey(const Key('add_to_library_fab')),
      );
      expect(fab.backgroundColor, colors.accent);
      expect(fab.foregroundColor, colors.onAccent);
      expect(
        MbPalette.contrastRatio(fab.foregroundColor!, fab.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
      final wideButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('add_to_library_button')),
      );
      expect(wideButton.onPressed, isNull);
      expect(
        MbPalette.contrastRatio(
          wideButton.style!.foregroundColor!.resolve({WidgetState.disabled})!,
          wideButton.style!.backgroundColor!.resolve({WidgetState.disabled})!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(showTooltips: true, palette: colors),
          home: Scaffold(
            floatingActionButton: SeriesDetailFAB(
              entryStream: Stream.value(null),
              editorOpen: true,
              onAdd: _noop,
            ),
          ),
        ),
      );
      await tester.pump();
      final disabledFab = tester.widget<FloatingActionButton>(
        find.byKey(const Key('add_to_library_fab')),
      );
      expect(disabledFab.onPressed, isNull);
      expect(disabledFab.backgroundColor, colors.surfaceRaised);
      expect(
        MbPalette.contrastRatio(
          disabledFab.foregroundColor!,
          disabledFab.backgroundColor!,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('quick +1 keeps optimistic update and rolls back failure', (
    tester,
  ) async {
    final series = Series.fromJson({
      'id': '123',
      'title': 'Test Manga',
      'total_chapters': '12',
    });
    final entry = LibraryEntry(
      id: '123',
      state: 'reading',
      progressChapter: 2,
      series: series,
    );
    final observed = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(showTooltips: true, palette: EirenYuPalette.dark),
        home: Scaffold(
          body: SeriesQuickActionButton(
            series: series,
            entry: entry,
            onOptimisticProgressChanged: observed.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(mockLibraryService.lastProgressChapter, 3);
    expect(find.text('3 / 12'), findsOneWidget);
    expect(observed, [3]);
    mockLibraryService.failProgress = true;
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    expect(mockLibraryService.lastProgressChapter, 4);
    expect(find.text('2 / 12'), findsOneWidget);
    expect(observed, [3, 4, null]);
  });
}

void _noop() {}
