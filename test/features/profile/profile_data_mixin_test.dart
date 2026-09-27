import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/mixins/profile_data_mixin.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/profile/services/snapshot_service.dart';
import 'package:mangabaka_app/features/profile/services/statistics_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

MbProfile _profile() => MbProfile(
  id: 'u1',
  role: 'user',
  scopes: [],
  preferredUsername: 'testuser',
);

class _FakeAuth extends Fake implements ProfileAuthService {
  @override
  bool get isLoggedIn => false;

  @override
  Future<MbProfile> fetchProfile({bool forceRefresh = false}) async =>
      _profile();
}

class _CompleterAuth extends _FakeAuth {
  final profileCompleter = Completer<MbProfile>();

  @override
  bool get isLoggedIn => true;

  @override
  Future<MbProfile> fetchProfile({bool forceRefresh = false}) =>
      profileCompleter.future;
}

class _ExpiredAuth extends _FakeAuth {
  @override
  Future<MbProfile> fetchProfile({bool forceRefresh = false}) {
    throw SessionExpiredException();
  }
}

class _FakeStats extends Fake implements StatisticsService {
  @override
  Future<int> getTotalSeries({List<String>? contentPreferences}) async => 10;

  @override
  Future<int> getChaptersRead({List<String>? contentPreferences}) async => 500;

  @override
  Future<int> getVolumesRead({List<String>? contentPreferences}) async => 30;

  @override
  Future<double> getMeanScore({List<String>? contentPreferences}) async => 78.5;
}

class _FakeSnapshotService extends Fake implements SnapshotService {
  @override
  Future<List<LibraryEntry>> fetchSnapshot({
    required String sortBy,
    int page = 1,
    int limit = 10,
  }) async => const [];
}

class _ScriptedSnapshotService extends Fake implements SnapshotService {
  _ScriptedSnapshotService(this.handler);

  final Future<List<LibraryEntry>> Function(String sortBy, int page) handler;
  final calls = <({String sortBy, int page})>[];

  @override
  Future<List<LibraryEntry>> fetchSnapshot({
    required String sortBy,
    int page = 1,
    int limit = 10,
  }) {
    calls.add((sortBy: sortBy, page: page));
    return handler(sortBy, page);
  }
}

class _FakeLibraryService extends Fake implements LibraryService {
  @override
  Future<void> performInitialSyncIfNeeded() async {}
}

Series _series(String id) => Series(
  id: id,
  title: 'Series $id',
  state: 'active',
  nativeTitle: '',
  romanizedTitle: '',
  secondaryTitles: const [],
  coverUrl: '',
  rawCoverUrl: '',
  authors: const [],
  artists: const [],
  description: '',
  year: '',
  status: '',
  isLicensed: '',
  hasAnime: '',
  contentRating: 'safe',
  type: 'manga',
  rating: '0',
  finalVolume: '',
  totalChapters: '',
  links: const [],
  publishers: const [],
  genres: const [],
  tags: const [],
  lastUpdated: '',
);

LibraryEntry _entry(String id) =>
    LibraryEntry(id: id, state: 'reading', series: _series(id));

// ─── Host widget ─────────────────────────────────────────────────────────────

class _TestWidget extends StatefulWidget {
  final ProfileAuthService auth;
  final StatisticsService stats;
  final SnapshotService snapshot;
  final LibraryService library;

  const _TestWidget({
    required this.auth,
    required this.stats,
    required this.snapshot,
    required this.library,
  });

  @override
  State<_TestWidget> createState() => _TestWidgetState();
}

class _TestWidgetState extends State<_TestWidget>
    with ProfileDataMixin<_TestWidget> {
  @override
  ProfileAuthService get auth => widget.auth;

  @override
  LibraryService get libraryService => widget.library;

  @override
  StatisticsService get statisticsService => widget.stats;

  @override
  SnapshotService get snapshotService => widget.snapshot;

  @override
  Widget build(BuildContext context) => Container();
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;
  late LibraryService libraryService;

  setUpAll(() async => LoggingService.setup());

  setUp(() async {
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt.registerSingleton<AppDatabase>(db);
    libraryService = LibraryService(auth: _FakeAuth(), database: db);
  });

  tearDown(() async {
    await db.close();
    await resetServiceLocator();
  });

  Widget buildTestWidget({
    ProfileAuthService? auth,
    StatisticsService? stats,
    SnapshotService? snapshot,
    LibraryService? library,
  }) {
    return MaterialApp(
      home: _TestWidget(
        auth: auth ?? _FakeAuth(),
        stats: stats ?? _FakeStats(),
        snapshot: snapshot ?? _FakeSnapshotService(),
        library: library ?? libraryService,
      ),
    );
  }

  group('ProfileDataMixin.fetchStatistics', () {
    testWidgets('populates totalSeries, chaptersRead, volumesRead, meanScore', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      await state.fetchStatistics();
      await tester.pump();

      expect(state.totalSeries, 10);
      expect(state.chaptersRead, 500);
      expect(state.volumesRead, 30);
      expect(state.meanScore, 78.5);
    });
  });

  group('ProfileDataMixin.fetchRecentlyChanged', () {
    testWidgets('is a no-op when isLoadingChanged is true', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      state.isLoadingChanged = true;
      await state.fetchRecentlyChanged();
      await tester.pump();
      expect(state.recentlyChanged, isEmpty);
    });

    testWidgets('is a no-op when hasMoreChanged is false', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      state.hasMoreChanged = false;
      await state.fetchRecentlyChanged();
      await tester.pump();
      expect(state.recentlyChanged, isEmpty);
    });

    testWidgets('sets hasMoreChanged false when snapshot returns empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(snapshot: _FakeSnapshotService()),
      );
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      await state.fetchRecentlyChanged();
      await tester.pump();
      expect(state.hasMoreChanged, isFalse);
    });

    testWidgets('initial refresh restarts at page 1 and replaces old entries', (
      tester,
    ) async {
      final replacement = _entry('replacement');
      final snapshot = _ScriptedSnapshotService((_, _) async => [replacement]);
      await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      state
        ..recentlyChanged.add(_entry('old'))
        ..pageChanged = 4
        ..hasMoreChanged = false;

      await state.fetchRecentlyChanged(initial: true);
      await tester.pump();

      expect(snapshot.calls.single.page, 1);
      expect(state.recentlyChanged, [replacement]);
      expect(state.pageChanged, 2);
      expect(state.hasMoreChanged, isTrue);
    });

    testWidgets('failed initial refresh preserves entries and pagination', (
      tester,
    ) async {
      final existing = _entry('existing');
      final snapshot = _ScriptedSnapshotService(
        (_, _) async => throw StateError('network failed'),
      );
      await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      state
        ..recentlyChanged.add(existing)
        ..pageChanged = 3
        ..hasMoreChanged = false;

      await state.fetchRecentlyChanged(initial: true);
      await tester.pump();

      expect(snapshot.calls.single.page, 1);
      expect(state.recentlyChanged, [existing]);
      expect(state.pageChanged, 3);
      expect(state.hasMoreChanged, isFalse);
    });

    testWidgets('normal load more appends and advances pagination', (
      tester,
    ) async {
      final next = _entry('next');
      final snapshot = _ScriptedSnapshotService((_, page) async {
        expect(page, 2);
        return [next];
      });
      await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      final existing = _entry('existing');
      state
        ..recentlyChanged.add(existing)
        ..pageChanged = 2;

      await state.fetchRecentlyChanged();
      await tester.pump();

      expect(state.recentlyChanged, [existing, next]);
      expect(state.pageChanged, 3);
    });

    testWidgets('stale load-more result cannot corrupt a newer refresh', (
      tester,
    ) async {
      final loadMore = Completer<List<LibraryEntry>>();
      final refresh = Completer<List<LibraryEntry>>();
      final snapshot = _ScriptedSnapshotService((_, page) {
        return page == 1 ? refresh.future : loadMore.future;
      });
      await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      state.pageChanged = 2;

      final loadMoreFuture = state.fetchRecentlyChanged();
      final refreshFuture = state.fetchRecentlyChanged(initial: true);
      refresh.complete([_entry('fresh')]);
      await refreshFuture;
      loadMore.complete([_entry('stale')]);
      await loadMoreFuture;
      await tester.pump();

      expect(state.recentlyChanged.map((entry) => entry.id), ['fresh']);
      expect(state.pageChanged, 2);
    });
  });

  group('ProfileDataMixin.fetchRecentlyAdded', () {
    testWidgets('increments pageAdded after fetch', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      expect(state.pageAdded, 1);
      await state.fetchRecentlyAdded();
      await tester.pump();
      expect(state.pageAdded, 2);
    });

    testWidgets('initial refresh bypasses stale hasMore and requests page 1', (
      tester,
    ) async {
      final snapshot = _ScriptedSnapshotService(
        (_, _) async => [_entry('fresh')],
      );
      await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      state
        ..pageAdded = 5
        ..hasMoreAdded = false;

      await state.fetchRecentlyAdded(initial: true);
      await tester.pump();

      expect(snapshot.calls.single.page, 1);
      expect(state.pageAdded, 2);
      expect(state.hasMoreAdded, isTrue);
    });
  });

  group('ProfileDataMixin.bootstrap', () {
    testWidgets('keeps the logged-out state clear after session expiry', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget(auth: _ExpiredAuth()));
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));

      await state.bootstrap();
      await tester.pump();

      expect(state.loading, isFalse);
      expect(state.profile, isNull);
      expect(state.error, isNull);
    });

    testWidgets('keeps an available profile visible while refreshing', (
      tester,
    ) async {
      final auth = _CompleterAuth();
      await tester.pumpWidget(
        buildTestWidget(auth: auth, library: _FakeLibraryService()),
      );
      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      final existing = _profile();
      state
        ..profile = existing
        ..loading = false;

      final refresh = state.bootstrap();
      await tester.pump();

      expect(state.loading, isFalse);
      expect(state.profile, same(existing));

      auth.profileCompleter.complete(_profile());
      await refresh;
      await tester.pump();
      expect(state.loading, isFalse);
    });
  });
}
