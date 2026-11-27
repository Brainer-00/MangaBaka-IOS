import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/theme/app_theme.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/screens/library_screen.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/widgets/library_grid_list.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/profile/widgets/login/mb_login_prompt.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/screens/series_detail_screen.dart';
import 'package:mangabaka_app/features/series/widgets/entry_progress_overlay.dart';
import 'package:mangabaka_app/features/series/widgets/entry_list_item.dart';
import 'package:mangabaka_app/features/series/widgets/progress_update_dialog.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/features/series/services/series_search_service.dart';
import 'package:mangabaka_app/features/series/services/series_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends ChangeNotifier implements ProfileAuthService {
  @override
  LibraryCacheLease? libraryLease;

  @override
  bool get isLoggedIn => libraryLease != null;

  @override
  Future<String> getValidAccessToken() async => 'fixture-token';

  void changeAccount(LibraryCacheLease lease) {
    libraryLease = lease;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library extends Fake implements LibraryService {
  @override
  final syncStatus = ValueNotifier(const LibrarySyncStatus());
  var entries = StreamController<List<LibraryEntry>>.broadcast();
  Stream<LibraryEntry?> entryStream = const Stream.empty();

  @override
  Stream<List<LibraryEntry>> watchEntriesFromDb() => entries.stream;

  @override
  Stream<LibraryEntry?> watchEntryFromDb(String id) => entryStream;

  @override
  Future<void> performInitialSyncIfNeeded() async {}

  @override
  Future<bool> isLibraryIncomplete() async => false;
}

class _SeriesService extends Fake implements SeriesService {
  @override
  get logger => LoggingService.logger;
}

class _Metadata extends Fake implements MetadataService {}

class _CollectionMembershipCache extends Fake implements OwnedLibraryDao {
  @override
  Future<void> updateListMembership(
    LibraryCacheLease lease,
    int listId, {
    required bool add,
    Set<String>? seriesIds,
    void Function()? beforeCommit,
  }) async => beforeCommit?.call();
}

class _CollectionsLibrary extends LibraryService {
  _CollectionsLibrary({
    required super.auth,
    required super.database,
    required super.httpClient,
    required this.entries,
  });

  final Stream<List<LibraryEntry>> entries;

  @override
  final owned = _CollectionMembershipCache();

  @override
  Stream<List<LibraryEntry>> watchEntriesFromDb() => entries;

  @override
  Stream<LibraryEntry?> watchEntryFromDb(String id) => const Stream.empty();

  @override
  Future<void> performInitialSyncIfNeeded() async {}
}

LibraryEntry _entry(String id, String state, {String? title}) => LibraryEntry(
  id: id,
  state: state,
  series: Series.fromJson({
    'id': id,
    'title': title ?? 'Owned series $id',
    'content_rating': 'safe',
    'type': 'manga',
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryCacheLease firstLease;
  late LibraryCacheLease secondLease;
  late _Library library;
  late _Auth auth;

  setUpAll(() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      firstLease = await db.ownedLibraryDao.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId('first'),
      );
      secondLease = await db.ownedLibraryDao.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId('second'),
      );
    } finally {
      await db.close();
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsManager.resetForTesting();
    await SettingsManager().init();
    await SettingsManager().setShowLibraryTabCounts(true);
    LocalizationService.resetForTesting();
    await LocalizationService().init();
    library = _Library();
    auth = _Auth();
    getIt.registerSingleton<LibraryService>(library);
    getIt.registerSingleton<ProfileAuthService>(auth);
    getIt.registerSingleton<SeriesService>(_SeriesService());
    getIt.registerSingleton<MetadataService>(_Metadata());
    getIt.registerSingleton<SeriesSearchService>(
      SeriesSearchService(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
    );
  });

  tearDown(() async {
    await library.entries.close();
    await resetServiceLocator();
    library.syncStatus.dispose();
    auth.dispose();
  });

  Future<void> mount(WidgetTester tester, {MbPalette? palette}) async {
    tester.view.physicalSize = const Size(375, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: palette == null
            ? null
            : AppTheme.build(showTooltips: true, palette: palette),
        home: const LibraryScreen(),
      ),
    );
    await tester.pump();
  }

  testWidgets('Library shows the login prompt when signed out', (tester) async {
    await mount(tester);
    expect(find.byType(MBLoginPrompt), findsOneWidget);
  });

  testWidgets('All shares filtered counts and clears them on account change', (
    tester,
  ) async {
    auth.changeAccount(firstLease);
    await mount(tester);
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    final state = tester.state<LibraryScreenState>(find.byType(LibraryScreen));
    final allTab = find.ancestor(
      of: find.text('ALL'),
      matching: find.byType(Tab),
    );
    Finder count(String number) =>
        find.descendant(of: allTab, matching: find.text(number));
    LibraryGridList page(String key) =>
        tester.widget<LibraryGridList>(find.byKey(PageStorageKey(key)));
    expect(controller.index, 0);
    expect(count('0'), findsOneWidget);

    final reading = _entry('1', 'reading');
    final completed = _entry('2', 'completed', title: 'Distinct result');
    final moved = _entry('1', 'paused');
    library.entries.add([reading, completed]);
    await tester.pumpAndSettle();
    expect(page('all').items, [reading, completed]);
    expect(count('2'), findsOneWidget);

    await tester.tap(find.text('READING'));
    await tester.pumpAndSettle();
    expect(controller.index, 1);
    state.updateFilters(SearchFilters(type: ['manga']));
    state.updateQuery('Owned');
    await tester.pumpAndSettle();
    expect(controller.index, 1);
    state.updateQuery('Distinct');
    await tester.pumpAndSettle();
    expect(controller.index, 0);
    expect(page('all').items, [completed]);
    expect(count('1'), findsOneWidget);
    state.updateQuery('');
    await tester.pumpAndSettle();
    expect(controller.index, 0);

    library.entries.add([moved, completed, _entry('3', 'considering')]);
    await tester.pumpAndSettle();
    expect(page('all').items, hasLength(3));
    expect(count('3'), findsOneWidget);
    library.entries.add([moved]);
    await tester.pumpAndSettle();
    expect(page('all').items, [moved]);
    expect(count('1'), findsOneWidget);
    await SettingsManager().setShowLibraryTabCounts(false);
    await tester.pumpAndSettle();
    expect(count('1'), findsNothing);
    await SettingsManager().setShowLibraryTabCounts(true);

    final old = library.entries;
    library.entries = StreamController<List<LibraryEntry>>.broadcast();
    auth.changeAccount(secondLease);
    old.add([reading, completed]);
    await tester.pump();
    expect(find.byType(LibraryGridList), findsNothing);
    expect(count('0'), findsOneWidget);
    final newEntry = _entry('4', 'rereading', title: 'New account');
    library.entries.add([newEntry]);
    await tester.pumpAndSettle();
    expect(page('all').items, [newEntry]);
    expect(count('1'), findsOneWidget);
    await old.close();
  });

  testWidgets('eight pages swipe and keep individual scroll offsets', (
    tester,
  ) async {
    auth.changeAccount(firstLease);
    await mount(tester);
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    final controller = tabs.controller!;
    expect(tabs.tabs, hasLength(8));
    final entries = [
      for (var index = 0; index < 50; index++) _entry('$index', 'reading'),
    ];
    library.entries.add(entries);
    await tester.pumpAndSettle();
    ScrollController scroll(String key) => tester
        .widget<LibraryGridList>(find.byKey(PageStorageKey(key)))
        .scrollController;
    scroll('all').jumpTo(260);
    await tester.pumpAndSettle();
    await tester.tap(find.text('READING'));
    await tester.pumpAndSettle();
    expect(scroll('reading').offset, 0);
    scroll('reading').jumpTo(500);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ALL'));
    await tester.pumpAndSettle();
    expect(scroll('all').offset, 260);
    for (var index = 1; index < tabs.tabs.length; index++) {
      await tester.drag(find.byType(TabBarView), const Offset(-305, 0));
      await tester.pumpAndSettle();
      expect(controller.index, index);
      if (index == 1) expect(scroll('reading').offset, 500);
    }
    expect(find.byKey(const PageStorageKey('considering')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'progress uses actual status in both badge layouts and opens the update sheet',
    (tester) async {
      auth.changeAccount(firstLease);
      final settings = SettingsManager();
      await settings.setShowLibraryProgress(true);
      await settings.setShowRemainingProgress(true);
      final series = Series.fromJson({
        'id': 1,
        'title': 'Progress fixture',
        'total_chapters': 12,
        'final_volume': 6,
      });
      final statuses = {
        'reading': AppConstants.successColor,
        'paused': const Color(0xFFFBD24B),
        'completed': Colors.white,
        'plan_to_read': AppConstants.infoColor,
        'dropped': AppConstants.errorColor,
        'rereading': AppConstants.rereadingColor,
        'considering': AppConstants.consideringColor,
        'unknown': Colors.white,
      };
      Future<void> show(
        String state, {
        required double width,
        double scale = 1,
        int? override,
      }) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            showTooltips: true,
            palette: EirenYuPalette.light,
          ),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: SizedBox(
                  width: width,
                  height: 200,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: Colors.black),
                      ),
                      EntryProgressOverlay(
                        series: series,
                        cardWidth: width,
                        settings: settings,
                        progressOverride: override,
                        l10n: LocalizationService(),
                        entry: LibraryEntry(
                          id: '1',
                          state: state,
                          series: series,
                          progressChapter: 4,
                          progressVolume: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Color? ink(String text) =>
          tester.widget<Text>(find.text(text)).style!.color;
      for (final type in LibraryProgressType.values) {
        await settings.setLibraryProgressType(type);
        final chapter = type == LibraryProgressType.chapters;
        for (final MapEntry(key: state, value: color) in statuses.entries) {
          await show(state, width: chapter ? 120 : 180);
          expect(ink(chapter ? 'Ch. 4/12' : 'Vol. 2/6'), color, reason: state);
          expect(ink(chapter ? '8' : '4'), AppConstants.semanticYellow);
        }
      }
      await settings.setLibraryProgressType(LibraryProgressType.chapters);
      await show('paused', width: 125, scale: 1.8, override: 5);
      expect(ink('Ch. 5/12'), const Color(0xFFFBD24B));
      expect(ink('7'), AppConstants.semanticYellow);
      await tester.tap(find.text('Ch. 5/12'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgressUpdateDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('progress fallback belongs to the waiting cache lease', (
    tester,
  ) async {
    auth.changeAccount(firstLease);
    final first = StreamController<LibraryEntry?>.broadcast(sync: true);
    final second = StreamController<LibraryEntry?>.broadcast(sync: true);
    addTearDown(first.close);
    addTearDown(second.close);
    library.entryStream = first.stream;
    await SettingsManager().setShowLibraryProgress(true);
    final entry = LibraryEntry(
      id: '1',
      state: 'reading',
      progressChapter: 4,
      series: Series.fromJson({
        'id': 1,
        'title': 'Fallback',
        'total_chapters': 12,
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 150,
            height: 300,
            child: EntryListItem(
              series: entry.series,
              listStyle: AppListStyle.compactGrid,
              fallbackEntry: (firstLease, entry),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Ch. 4/12'), findsOneWidget);
    first.add(null);
    await tester.pump();
    expect(find.text('Ch. 4/12'), findsNothing);
    library.entryStream = second.stream;
    auth.changeAccount(secondLease);
    await tester.pump();
    expect(find.text('Ch. 4/12'), findsNothing);
    second.add(entry);
    await tester.pumpAndSettle();
    expect(find.text('Ch. 4/12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Collections preserves Library search and uses scoped list actions',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      auth.changeAccount(firstLease);
      final lists = <int, (String, bool, Set<int>)>{
        1: ('Reading room', false, {1, 2}),
        2: ('Private shelf', true, {}),
      };
      final titles = {1: 'Alpha story', 2: 'Beta story', 3: 'Gamma story'};
      final writes = <Map<String, dynamic>>[];
      var failReads = false;
      var failMembers = false;
      Map<String, dynamic> listJson(int id) => {
        'id': id,
        'name': lists[id]!.$1,
        'is_private': lists[id]!.$2,
        'series_count': lists[id]!.$3.length,
        'created_at': '2026-02-01T03:00:00Z',
      };
      http.Response result(Object? data, {bool paged = false}) => http.Response(
        jsonEncode({
          'status': 200,
          'data': data,
          if (paged)
            'pagination': {'count': (data as List).length, 'next': null},
        }),
        200,
      );
      final client = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET') {
          if (failReads) return http.Response('{"status":503}', 503);
          if (path.endsWith('/lists')) {
            if (identical(auth.libraryLease, secondLease)) {
              return result([], paged: true);
            }
            return result(
              lists.keys.toList().reversed.map(listJson).toList(),
              paged: true,
            );
          }
          final id = int.parse(request.url.queryParameters['list']!);
          if (failMembers) return http.Response('{"status":503}', 503);
          return result([
            for (final seriesId in lists[id]!.$3)
              {
                'entry': {
                  'id': seriesId + 20,
                  'user_id': 'first',
                  'series_id': seriesId,
                  'state': 'reading',
                  'progress_chapter': 2,
                },
                'lists': [listJson(id)],
                'series': {
                  'id': seriesId,
                  'title': titles[seriesId],
                  'content_rating': 'safe',
                  'type': 'manga',
                  'total_chapters': 12,
                },
              },
          ], paged: true);
        }
        if (request.method == 'DELETE') {
          lists.remove(int.parse(path.split('/').last));
          return http.Response('{"status":200}', 200);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        writes.add(body);
        if (path.endsWith('/bulk')) {
          final change = body['change'] as Map;
          final series = (body['target'] as Map)['series_ids'] as List;
          final add = (change['add'] as List).isNotEmpty;
          final id = (change[add ? 'add' : 'remove'] as List).single as int;
          for (final item in series.cast<int>()) {
            add ? lists[id]!.$3.add(item) : lists[id]!.$3.remove(item);
          }
          return result({
            'updated': series.length,
            'skipped': 0,
            'added': add ? series.length : 0,
            'removed': add ? 0 : series.length,
          });
        }
        final id = request.method == 'POST'
            ? 3
            : int.parse(path.split('/').last);
        lists[id] = (
          body['name'] as String? ?? lists[id]!.$1,
          body['is_private'] as bool? ?? lists[id]!.$2,
          lists[id]?.$3 ?? <int>{},
        );
        return result(listJson(id));
      });
      final collections = _CollectionsLibrary(
        auth: auth,
        database: db,
        httpClient: client,
        entries: library.entries.stream,
      );
      addTearDown(collections.dispose);
      await getIt.unregister<LibraryService>();
      getIt.registerSingleton<LibraryService>(collections);
      Future<void> confirmWrite(Finder button) async {
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await SettingsManager().setAutoSuggestLibrary(false);
      await mount(tester, palette: EirenYuPalette.dark);
      library.entries.add([
        for (final title in titles.entries)
          _entry('${title.key}', 'reading', title: title.value),
      ]);
      await tester.pumpAndSettle();
      final libraryState = tester.state<LibraryScreenState>(
        find.byType(LibraryScreen),
      );
      await tester.tap(find.text('READING'));
      await tester.pumpAndSettle();
      libraryState.enterSearchMode();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Alpha');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collections'));
      await tester.pumpAndSettle();
      expect(find.text('Reading room'), findsOneWidget);
      expect(find.text('2 titles'), findsOneWidget);
      expect(find.text('No titles added yet.'), findsOneWidget);
      // Verify the overview under representative tablet and compact split
      // constraints, with large text and Amber on a light palette.
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(
            showTooltips: true,
            palette: EirenYuPalette.light.withAccent(
              AppConstants.semanticYellow,
            ),
          ),
          home: const LibraryScreen(),
        ),
      );
      for (final size in [const Size(1050, 820), const Size(320, 600)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.byTooltip('Create list'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size');
      }
      tester.view.physicalSize = const Size(375, 720);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Private'));
      await tester.pumpAndSettle();
      expect(find.text('Reading room'), findsNothing);
      expect(find.text('Private shelf'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'All'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();
      expect(find.text('Private shelf'), findsNothing);
      expect(find.text('Showing 1 matching title'), findsOneWidget);
      expect(find.text('2 titles'), findsOneWidget);
      await tester.tap(find.text('Stacks'));
      await tester.pumpAndSettle();
      expect(
        find.text('Stacks are not available in this version yet.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Create list'), findsNothing);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Alpha',
      );
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      await tester.tap(find.text('Collections'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Lists').first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Beta',
      );
      await tester.tap(find.text('Reading room'));
      await tester.pumpAndSettle();
      expect(find.text('2 titles'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Beta');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta story'));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesDetailScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(SeriesDetailScreen))).pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Beta',
      );
      expect(find.text('Alpha story'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byType(EntryProgressOverlay),
          matching: find.byWidgetPredicate(
            (widget) => widget is ExcludeFocus && widget.excluding,
          ),
        ),
        findsNWidgets(2),
      );
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await SettingsManager().setContentPreferences(['suggestive']);
      await tester.pumpAndSettle();
      await SettingsManager().setContentPreferences(['safe']);
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Beta');
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();
      final confirm = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: confirm,
          matching: find.textContaining('They will remain'),
        ),
        findsOneWidget,
      );
      await confirmWrite(
        find.descendant(
          of: confirm,
          matching: find.widgetWithText(TextButton, 'Remove from list'),
        ),
      );
      expect(writes.last['target'], {
        'series_ids': [2],
      });
      expect(lists[1]!.$3, {1});
      expect(find.text('1 title'), findsOneWidget);
      await tester.tap(find.text('Add titles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      library.entries.add([
        for (final title in titles.entries)
          _entry('${title.key}', 'reading', title: title.value),
      ]);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(CheckboxListTile, 'Alpha story'),
        findsNothing,
      );
      final picker = find.byType(BottomSheet);
      await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        'Gamma',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'Beta story'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gamma story'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add titles'));
      await tester.pumpAndSettle();
      await confirmWrite(
        find.descendant(
          of: confirm,
          matching: find.widgetWithText(TextButton, 'Add titles'),
        ),
      );
      expect(writes.last['change'], {
        'action': 'update_lists',
        'add': [1],
        'remove': [],
      });
      expect(lists[1]!.$3, {1, 3});
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Create list'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Visible on your MangaBaka profile when your Library is public.',
        ),
        findsOneWidget,
      );
      final form = find.byType(Form);
      await tester.enterText(
        find.descendant(of: form, matching: find.byType(TextFormField)),
        'New shelf',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(lists[3]!.$1, 'New shelf');
      // The server lists ID 3 first. It is still appended in the current overview.
      final overview = find.byKey(const PageStorageKey('my-lists-overview'));
      await tester.scrollUntilVisible(
        find.text('New shelf'),
        180,
        scrollable: find
            .descendant(of: overview, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      final newList = find.ancestor(
        of: find.text('New shelf'),
        matching: find.byKey(const ValueKey(3)),
      );
      await tester.tap(
        find.descendant(of: newList, matching: find.byTooltip('Edit list')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Created'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Edited shelf');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((lists[3]!.$1, lists[3]!.$2), ('Edited shelf', true));
      await tester.scrollUntilVisible(
        find.text('Edited shelf'),
        160,
        scrollable: find
            .descendant(of: overview, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      final editedList = find.ancestor(
        of: find.text('Edited shelf'),
        matching: find.byKey(const ValueKey(3)),
      );
      await tester.tap(
        find.descendant(of: editedList, matching: find.byTooltip('Edit list')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete list'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('progress, notes and ratings'),
        findsOneWidget,
      );
      lists[3] = ('Edited shelf', false, {});
      await confirmWrite(
        find.descendant(
          of: confirm,
          matching: find.widgetWithText(TextButton, 'Delete list'),
        ),
      );
      expect(lists, contains(3));
      await tester.tap(find.text('Reload list details'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Delete list'));
      await tester.pumpAndSettle();
      await confirmWrite(
        find.descendant(
          of: confirm,
          matching: find.widgetWithText(TextButton, 'Delete list'),
        ),
      );
      expect(lists, isNot(contains(3)));
      final overviewScroll = find
          .descendant(of: overview, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(overviewScroll).position;
      Future<void> refreshOverview() async {
        position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
        await tester.pumpAndSettle();
      }

      failMembers = true;
      await refreshOverview();
      expect(
        find.textContaining('Showing previously verified titles'),
        findsOneWidget,
      );
      expect(find.text('Alpha story'), findsOneWidget);
      await tester.tap(find.text('Reading room'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Select'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Add titles'))
            .onPressed,
        isNull,
      );
      failMembers = false;
      await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Showing previously verified titles'),
        findsNothing,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Select'))
            .onPressed,
        isNotNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      lists[1]!.$3.clear();
      for (var id = 10; id < 32; id++) {
        lists[id] = ('Shelf $id', false, {});
      }
      await refreshOverview();
      expect(find.text('Alpha story'), findsNothing);
      expect(find.text('No titles added yet.'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'shelf');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'shelf',
      );
      expect(find.text('Reading room'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      lists.remove(1);
      await refreshOverview();
      expect(find.text('Reading room'), findsNothing);
      failReads = true;
      final scrollable = find
          .descendant(of: overview, matching: find.byType(Scrollable))
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Previously loaded lists may be out of date'),
        findsOneWidget,
      );
      failReads = false;
      auth.changeAccount(secondLease);
      await tester.pumpAndSettle();
      expect(find.text('Reading room'), findsNothing);
      expect(find.text('You have no lists yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
