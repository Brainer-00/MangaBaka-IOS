import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/screens/library_screen.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/widgets/library_grid_list.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/profile/widgets/login/mb_login_prompt.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/services/metadata_service.dart';
import 'package:mangabaka_app/features/series/services/series_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends ChangeNotifier implements ProfileAuthService {
  @override
  LibraryCacheLease? libraryLease;

  @override
  bool get isLoggedIn => libraryLease != null;

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

  @override
  Stream<List<LibraryEntry>> watchEntriesFromDb() => entries.stream;

  @override
  Stream<LibraryEntry?> watchEntryFromDb(String id) => const Stream.empty();

  @override
  Future<void> performInitialSyncIfNeeded() async {}

  @override
  Future<bool> isLibraryIncomplete() async => false;
}

class _SeriesService extends Fake implements SeriesService {}

class _Metadata extends Fake implements MetadataService {}

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
  });

  tearDown(() async {
    await library.entries.close();
    await resetServiceLocator();
    library.syncStatus.dispose();
    auth.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LibraryScreen()));
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
}
