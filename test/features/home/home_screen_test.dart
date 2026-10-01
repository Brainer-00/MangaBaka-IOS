import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/features/home/screens/home_screen.dart';
import 'package:mangabaka_app/features/home/services/home_service.dart';
import 'package:mangabaka_app/features/home/widgets/home_trending_section.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

class MockProfileAuthService extends Fake implements ProfileAuthService {
  @override
  bool get isLoggedIn => false;
  @override
  MbProfile? get cachedProfile => null;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _MutableAuthService extends Fake implements ProfileAuthService {
  final List<VoidCallback> _listeners = [];
  bool loggedIn = true;
  String? userId = 'user-a';

  @override
  bool get isLoggedIn => loggedIn;

  @override
  MbProfile? get cachedProfile => userId == null
      ? null
      : MbProfile(id: userId!, role: 'user', scopes: const []);

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Future<String> getValidAccessToken() async => 'access-token';

  @override
  Future<String> recoverAfterUnauthorized(String rejectedAccessToken) async =>
      'recovered-token';

  void notifyAuthChanged() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

Series _series(String title) => Series(
  id: title,
  state: 'published',
  title: title,
  nativeTitle: '',
  romanizedTitle: '',
  secondaryTitles: const [],
  coverUrl: '',
  rawCoverUrl: '',
  authors: const [],
  artists: const [],
  description: '',
  year: '2024',
  status: 'ongoing',
  isLicensed: 'no',
  hasAnime: 'no',
  contentRating: 'safe',
  type: 'manga',
  rating: '',
  finalVolume: '',
  totalChapters: '',
  links: const [],
  publishers: const [],
  genres: const [],
  tags: const [],
  lastUpdated: '',
);

TopGenre _genre(int id, String name) =>
    TopGenre(tagId: id, name: name, affinity: 1);

Finder get _forYouRail => find.byKey(const ValueKey('home-for-you-rail'));

Finder _topGenreRail(int tagId) =>
    find.byKey(ValueKey('home-top-genre-$tagId'), skipOffstage: false);

Finder _homeText(String text) => find.text(text, skipOffstage: false);

class _ControlledHomeService extends Fake implements HomeService {
  final readinessRequests = <Completer<ForYouReadiness?>>[];
  final forYouRequests = <Completer<List<Series>>>[];
  final trendingRequests = <_TrendingRequest>[];
  final risingRequests = <Completer<List<Series>>>[];
  final hiddenGemsRequests = <Completer<List<Series>>>[];
  final newReleasesRequests = <Completer<List<Series>>>[];
  final topGenreRequests = <Completer<List<TopGenre>>>[];
  final topInGenreRequests = <_GenreRequest>[];
  final readyBatchLabels = <String>[];
  List<Series> immediateTrending = const [];
  List<Series> immediateRising = const [];
  List<Series> immediateHiddenGems = const [];
  List<Series> immediateNewReleases = const [];
  List<TopGenre> immediateTopGenres = [
    _genre(1, 'Action'),
    _genre(2, 'Drama'),
    _genre(3, 'Fantasy'),
  ];
  bool holdTrending = false;
  bool holdForYou = false;
  bool holdRising = false;
  bool holdHiddenGems = false;
  bool holdNewReleases = false;
  bool holdTopGenres = false;
  bool holdTopInGenre = false;
  int trendingFetches = 0;
  int risingFetches = 0;
  int hiddenGemsFetches = 0;
  int newReleasesFetches = 0;
  int topGenreFetches = 0;
  int topInGenreFetches = 0;
  int requestCount = 0;
  int _readyBatch = -1;
  int disposeCount = 0;

  @override
  Future<ForYouReadiness?> fetchForYouReadiness() {
    requestCount++;
    final completer = Completer<ForYouReadiness?>();
    readinessRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<Series>> fetchForYou({int limit = 20}) async {
    requestCount++;
    if (holdForYou) {
      final completer = Completer<List<Series>>();
      forYouRequests.add(completer);
      return completer.future;
    }
    _readyBatch++;
    return [_series(readyBatchLabels[_readyBatch])];
  }

  @override
  Future<List<Series>> fetchTrending({
    String? type,
    int windowDays = 7,
    int limit = 20,
  }) async {
    requestCount++;
    trendingFetches++;
    if (!holdTrending) return immediateTrending;
    final completer = Completer<List<Series>>();
    trendingRequests.add(
      _TrendingRequest(type: type, window: windowDays, completer: completer),
    );
    return completer.future;
  }

  @override
  Future<List<Series>> fetchRising({int limit = 20, int windowDays = 7}) async {
    requestCount++;
    risingFetches++;
    if (!holdRising) return immediateRising;
    final completer = Completer<List<Series>>();
    risingRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<Series>> fetchHiddenGems({int limit = 20}) async {
    requestCount++;
    hiddenGemsFetches++;
    if (!holdHiddenGems) return immediateHiddenGems;
    final completer = Completer<List<Series>>();
    hiddenGemsRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<Series>> fetchNewReleases({int limit = 20}) async {
    requestCount++;
    newReleasesFetches++;
    if (!holdNewReleases) return immediateNewReleases;
    final completer = Completer<List<Series>>();
    newReleasesRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<TopGenre>> fetchTopGenres({int limit = 3}) async {
    requestCount++;
    topGenreFetches++;
    if (!holdTopGenres) return immediateTopGenres;
    final completer = Completer<List<TopGenre>>();
    topGenreRequests.add(completer);
    return completer.future;
  }

  @override
  Future<List<Series>> fetchTopInGenre(int tagId, {int limit = 20}) async {
    requestCount++;
    topInGenreFetches++;
    if (!holdTopInGenre) return const [];
    final completer = Completer<List<Series>>();
    topInGenreRequests.add(_GenreRequest(tagId: tagId, completer: completer));
    return completer.future;
  }

  @override
  void dispose() => disposeCount++;
}

class _TrendingRequest {
  const _TrendingRequest({
    required this.type,
    required this.window,
    required this.completer,
  });

  final String? type;
  final int window;
  final Completer<List<Series>> completer;
}

class _GenreRequest {
  const _GenreRequest({required this.tagId, required this.completer});

  final int tagId;
  final Completer<List<Series>> completer;
}

const _ready = ForYouReadiness(
  coldStart: false,
  profileStale: false,
  libraryCount: 10,
);

void main() {
  setUp(() async {
    await resetServiceLocator();
    setupServiceLocator();
    getIt.unregister<ProfileAuthService>();
    getIt.registerSingleton<ProfileAuthService>(MockProfileAuthService());
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HomeScreen renders its header', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    // Header is uppercased by the design system; 'home' is the untranslated key.
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('HomeScreen no longer shows the library-backed Now hero', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    // The "Now / Continue Reading" hero was removed — MangaBaka tracks reading
    // rather than hosting it, so Home leads with discovery instead.
    expect(find.text('NOW'), findsNothing);
    expect(find.text('CONTINUE READING'), findsNothing);
  });

  group('Home load concurrency', () {
    late _MutableAuthService auth;
    late _ControlledHomeService home;

    setUp(() {
      auth = _MutableAuthService();
      home = _ControlledHomeService();
      getIt.unregister<ProfileAuthService>();
      getIt.registerSingleton<ProfileAuthService>(auth);
    });

    testWidgets(
      'rapid same-context triggers coalesce one actual ten-request fan-out',
      (tester) async {
        var actualRequests = 0;
        final heldReadiness = Completer<http.Response>();
        final client = MockClient((request) async {
          actualRequests++;
          if (request.url.path.endsWith('/recommendations/status')) {
            return heldReadiness.future;
          }
          if (request.url.path.endsWith('/discover/top-genres')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {'tag_id': 1, 'tag_name': 'Action'},
                  {'tag_id': 2, 'tag_name': 'Drama'},
                  {'tag_id': 3, 'tag_name': 'Fantasy'},
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/recommendations')) {
            return http.Response('{"results":[]}', 200);
          }
          return http.Response('{"data":[]}', 200);
        });
        final realHome = HomeService(client: client, auth: auth);
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(homeService: realHome)),
        );

        auth.notifyAuthChanged();
        auth.notifyAuthChanged();
        await tester.pump();

        // The public rails, readiness, and genre metadata start together.
        // Personalized and per-genre content waits only for structure.
        expect(actualRequests, 6);

        heldReadiness.complete(
          http.Response(
            jsonEncode({
              'data': {
                'cold_start': false,
                'profile_stale': false,
                'library_count': 10,
              },
            }),
            200,
          ),
        );
        await tester.pumpAndSettle();

        expect(actualRequests, 10);
      },
    );

    testWidgets('older delayed generation cannot overwrite newer results', (
      tester,
    ) async {
      home.readyBatchLabels.addAll(['New Result', 'Old Result']);
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));

      auth.userId = 'user-b';
      auth.notifyAuthChanged();
      await tester.pump();
      expect(home.readinessRequests, hasLength(2));

      home.readinessRequests[1].complete(_ready);
      await tester.pumpAndSettle();
      expect(find.text('New Result'), findsOneWidget);

      home.readinessRequests[0].complete(_ready);
      await tester.pumpAndSettle();

      expect(home.requestCount, 16);
      expect(find.text('New Result'), findsOneWidget);
      expect(find.text('Old Result'), findsNothing);
    });

    testWidgets('auth generation changes discard stale personalized data', (
      tester,
    ) async {
      home.readyBatchLabels.addAll(['New Account', 'Old Account']);
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));

      auth
        ..loggedIn = false
        ..userId = null
        ..notifyAuthChanged();
      auth
        ..loggedIn = true
        ..userId = 'user-b'
        ..notifyAuthChanged();
      await tester.pump();
      expect(home.readinessRequests, hasLength(3));

      home.readinessRequests[2].complete(_ready);
      await tester.pumpAndSettle();
      expect(find.text('New Account'), findsOneWidget);

      home.readinessRequests[0].complete(_ready);
      home.readinessRequests[1].complete(null);
      await tester.pumpAndSettle();

      expect(find.text('New Account'), findsOneWidget);
      expect(find.text('Old Account'), findsNothing);
    });

    testWidgets('failed generation does not poison a later load', (
      tester,
    ) async {
      home.readyBatchLabels.add('Recovered Result');
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));

      home.readinessRequests.single.completeError(StateError('held failure'));
      await tester.pump();
      await tester.pump();

      auth.userId = 'user-b';
      auth.notifyAuthChanged();
      await tester.pump();
      expect(home.readinessRequests, hasLength(2));
      home.readinessRequests[1].complete(_ready);
      await tester.pumpAndSettle();

      expect(_homeText('Recovered Result'), findsOneWidget);
    });

    testWidgets('disposal owns the service and ignores a late completion', (
      tester,
    ) async {
      home.readyBatchLabels.add('Too Late');
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      final held = home.readinessRequests.single;

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(home.disposeCount, 1);

      held.complete(_ready);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Too Late'), findsNothing);
    });

    testWidgets('public rails start before For-You readiness completes', (
      tester,
    ) async {
      home
        ..holdRising = true
        ..holdHiddenGems = true
        ..holdNewReleases = true
        ..holdTopGenres = true
        ..holdTrending = true;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      await tester.pump();

      expect(home.readinessRequests, hasLength(1));
      expect(home.trendingFetches, 1);
      expect(home.risingFetches, 1);
      expect(home.hiddenGemsFetches, 1);
      expect(home.newReleasesFetches, 1);
      expect(home.topGenreFetches, 1);
      expect(find.byKey(const ValueKey('home-initial-shell')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-established-content')),
        findsNothing,
      );
    });

    testWidgets('held readiness does not display the For You rail', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      await tester.pump();

      expect(home.readinessRequests.single.isCompleted, isFalse);
      expect(_forYouRail, findsNothing);
    });

    testWidgets('structure failure establishes a public-only fallback', (
      tester,
    ) async {
      home.immediateRising = [_series('Public Rising')];
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      await tester.pump();

      home.readinessRequests.single.completeError(StateError('readiness'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('home-initial-shell')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-established-content')),
        findsOneWidget,
      );
      expect(_forYouRail, findsNothing);
      expect(_homeText('Public Rising'), findsOneWidget);
    });

    testWidgets('fallback refresh retries and upgrades the structure', (
      tester,
    ) async {
      home.immediateRising = [_series('Public Rising')];
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      await tester.pump();

      home.readinessRequests.single.completeError(StateError('readiness'));
      await tester.pump();
      await tester.pump();
      expect(_homeText('Public Rising'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-initial-shell')), findsNothing);

      home
        ..holdTopGenres = true
        ..holdForYou = true
        ..holdTopInGenre = true;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();

      expect(find.byKey(const ValueKey('home-initial-shell')), findsNothing);
      expect(_homeText('Public Rising'), findsOneWidget);
      expect(home.readinessRequests, hasLength(2));
      expect(home.topGenreRequests, hasLength(1));

      home.readinessRequests[1].complete(_ready);
      home.topGenreRequests.single.complete([_genre(7, 'Upgraded Genre')]);
      await tester.pump();
      await tester.pump();

      expect(_forYouRail, findsOneWidget);
      expect(_topGenreRail(7), findsOneWidget);
      expect(home.forYouRequests, hasLength(1));
      expect(home.topInGenreRequests, hasLength(1));

      home.forYouRequests.single.complete([_series('Upgraded For You')]);
      home.topInGenreRequests.single.completer.complete(const []);
      await refresh;
    });

    testWidgets('auth context change clears previous For You content', (
      tester,
    ) async {
      home.readyBatchLabels.add('Account A For You');
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pumpAndSettle();
      expect(_homeText('Account A For You'), findsOneWidget);

      home.holdForYou = true;
      auth.userId = 'user-b';
      auth.notifyAuthChanged();
      await tester.pump();
      home.readinessRequests[1].complete(_ready);
      await tester.pump();
      await tester.pump();

      expect(_homeText('Account A For You'), findsNothing);
      expect(_forYouRail, findsOneWidget);
      expect(home.forYouRequests, hasLength(1));

      home.forYouRequests.single.complete([_series('Account B For You')]);
      await tester.pump();
      expect(_homeText('Account A For You'), findsNothing);
      expect(_homeText('Account B For You'), findsOneWidget);
    });

    testWidgets(
      'public content waits for the initial structure instead of shifting later',
      (tester) async {
        home
          ..immediateRising = [_series('Fast Rising')]
          ..holdTopGenres = true
          ..readyBatchLabels.add('For You');
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(homeService: home)),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('home-initial-shell')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-established-content')),
          findsNothing,
        );
        expect(find.text('Fast Rising'), findsNothing);
        home.readinessRequests.single.complete(_ready);
        home.topGenreRequests.single.complete([_genre(1, 'Action')]);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('home-initial-shell')), findsNothing);
        expect(
          find.byKey(const ValueKey('home-established-content')),
          findsOneWidget,
        );
        expect(_forYouRail, findsOneWidget);
        expect(find.text('Fast Rising'), findsOneWidget);
      },
    );

    testWidgets(
      'a fast public rail renders once structure is ready while another is pending',
      (tester) async {
        home
          ..immediateHiddenGems = [_series('Fast Hidden Gem')]
          ..holdRising = true
          ..readyBatchLabels.add('For You');
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(homeService: home)),
        );
        home.readinessRequests.single.complete(_ready);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(home.risingRequests.single.isCompleted, isFalse);
        expect(_homeText('Fast Hidden Gem'), findsOneWidget);
      },
    );

    testWidgets('not-ready readiness keeps For You absent', (tester) async {
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(null);
      await tester.pumpAndSettle();

      expect(_forYouRail, findsNothing);
    });

    testWidgets(
      'ready For You occupies its final location before its content resolves',
      (tester) async {
        home
          ..holdForYou = true
          ..holdTopInGenre = true;
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(homeService: home)),
        );
        home.readinessRequests.single.complete(_ready);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(home.forYouRequests, hasLength(1));
        expect(_forYouRail, findsOneWidget);
        expect(_topGenreRail(1), findsOneWidget);
      },
    );

    testWidgets(
      'top genre names and positions establish before their series complete',
      (tester) async {
        home
          ..holdTopInGenre = true
          ..readyBatchLabels.add('For You');
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(homeService: home)),
        );
        home.readinessRequests.single.complete(_ready);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(home.topInGenreRequests, hasLength(3));
        expect(home.topInGenreRequests.map((request) => request.tagId), [
          1,
          2,
          3,
        ]);
        expect(_topGenreRail(1), findsOneWidget);
        expect(_topGenreRail(2), findsOneWidget);
      },
    );

    testWidgets('stale structure metadata cannot affect a newer generation', (
      tester,
    ) async {
      home
        ..holdTopGenres = true
        ..holdTopInGenre = true
        ..readyBatchLabels.add('Current For You');
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      await tester.pump();

      auth.userId = 'user-b';
      auth.notifyAuthChanged();
      await tester.pump();
      expect(home.readinessRequests, hasLength(2));
      expect(home.topGenreRequests, hasLength(2));

      home.readinessRequests[1].complete(_ready);
      home.topGenreRequests[1].complete([_genre(2, 'Current Genre')]);
      await tester.pump();
      await tester.pump();
      expect(_topGenreRail(2), findsOneWidget);
      expect(find.text('Current For You'), findsOneWidget);

      home.readinessRequests[0].complete(_ready);
      home.topGenreRequests[0].complete([_genre(1, 'Stale Genre')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Stale Genre'), findsNothing);
      expect(find.text('Current For You'), findsOneWidget);
    });

    testWidgets(
      'public content remains in the structural shell while readiness is pending',
      (tester) async {
        home
          ..immediateTrending = [_series('Fast Trending')]
          ..holdRising = true;
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(homeService: home)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(home.readinessRequests.single.isCompleted, isFalse);
        expect(home.risingRequests.single.isCompleted, isFalse);
        expect(find.text('Fast Trending'), findsNothing);
      },
    );

    testWidgets('top-genre content latency does not hold public rail results', (
      tester,
    ) async {
      home
        ..immediateHiddenGems = [_series('Fast Hidden Gem')]
        ..immediateTopGenres = [_genre(1, 'Action')]
        ..holdTopInGenre = true
        ..readyBatchLabels.add('Unused');
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(home.topInGenreRequests, hasLength(1));
      expect(_homeText('Fast Hidden Gem'), findsOneWidget);
    });

    testWidgets('refresh keeps existing rail content while replacement loads', (
      tester,
    ) async {
      home
        ..immediateRising = [_series('Existing Rising')]
        ..readyBatchLabels.add('For You');
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pumpAndSettle();
      expect(find.text('Existing Rising'), findsOneWidget);

      home.holdRising = true;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();

      expect(find.text('Existing Rising'), findsOneWidget);
      expect(home.risingRequests.single.isCompleted, isFalse);

      home.risingRequests.single.complete([_series('Replacement Rising')]);
      home.readinessRequests[1].complete(_ready);
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('Replacement Rising'), findsOneWidget);
    });

    testWidgets('refresh preserves the established section structure', (
      tester,
    ) async {
      home
        ..holdTopInGenre = true
        ..readyBatchLabels.addAll(['For You', 'Refreshed For You']);
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_topGenreRail(1), findsOneWidget);

      home.immediateTopGenres = [_genre(99, 'Science')];
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();

      expect(_topGenreRail(1), findsOneWidget);
      expect(_topGenreRail(99), findsNothing);

      home.readinessRequests[1].complete(_ready);
      await tester.pump();
      for (final request in home.topInGenreRequests.skip(3)) {
        request.completer.complete(const []);
      }
      await refresh;
    });

    testWidgets(
      'stale public rail results cannot overwrite a newer generation',
      (tester) async {
        home.holdRising = true;
        await tester.pumpWidget(
          MaterialApp(home: HomeScreen(homeService: home)),
        );
        await tester.pump();
        expect(home.risingRequests, hasLength(1));

        auth.userId = 'user-b';
        auth.notifyAuthChanged();
        await tester.pump();
        expect(home.risingRequests, hasLength(2));

        home.readinessRequests[1].complete(null);
        await tester.pump();
        home.risingRequests[1].complete([_series('Current Rising')]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Current Rising'), findsOneWidget);

        home.risingRequests[0].complete([_series('Stale Rising')]);
        await tester.pumpAndSettle();
        expect(find.text('Current Rising'), findsOneWidget);
        expect(find.text('Stale Rising'), findsNothing);
      },
    );

    testWidgets('rapid Trending changes apply only request B', (tester) async {
      home
        ..readyBatchLabels.add('For You')
        ..immediateTrending = [_series('Initial Trending')];
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pumpAndSettle();

      home.holdTrending = true;
      var section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onTypeChanged('manga');
      await tester.pump();
      section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onWindowChanged(30);
      await tester.pump();

      expect(home.trendingRequests, hasLength(2));
      expect(home.trendingRequests[0].type, 'manga');
      expect(home.trendingRequests[0].window, 7);
      expect(home.trendingRequests[1].type, 'manga');
      expect(home.trendingRequests[1].window, 30);

      home.trendingRequests[1].completer.complete([_series('Trending B')]);
      await tester.pumpAndSettle();
      home.trendingRequests[0].completer.complete([_series('Trending A')]);
      await tester.pumpAndSettle();

      expect(find.text('Trending B'), findsOneWidget);
      expect(find.text('Trending A'), findsNothing);
    });

    testWidgets('targeted Trending reload supersedes older full-load result', (
      tester,
    ) async {
      home
        ..readyBatchLabels.add('For You')
        ..holdTrending = true;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pump();
      expect(home.trendingRequests, hasLength(1));

      final section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onTypeChanged('manga');
      await tester.pump();
      expect(home.trendingRequests, hasLength(2));

      home.trendingRequests[1].completer.complete([
        _series('Targeted Trending'),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Targeted Trending'), findsOneWidget);

      home.trendingRequests[0].completer.complete([_series('Full Trending')]);
      await tester.pumpAndSettle();
      expect(find.text('Targeted Trending'), findsOneWidget);
      expect(find.text('Full Trending'), findsNothing);
    });

    testWidgets('newer full generation supersedes targeted Trending reload', (
      tester,
    ) async {
      home
        ..readyBatchLabels.addAll(['Initial For You', 'New For You'])
        ..immediateTrending = [_series('Initial Trending')];
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pumpAndSettle();

      home.holdTrending = true;
      final section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onTypeChanged('manga');
      await tester.pump();
      expect(home.trendingRequests, hasLength(1));

      auth.userId = 'user-b';
      auth.notifyAuthChanged();
      await tester.pump();
      expect(home.readinessRequests, hasLength(2));

      home.trendingRequests[0].completer.complete([_series('Stale Targeted')]);
      home.readinessRequests[1].complete(_ready);
      await tester.pump();
      expect(home.trendingRequests, hasLength(2));
      home.trendingRequests[1].completer.complete([
        _series('New Full Trending'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('New Full Trending'), findsOneWidget);
      expect(find.text('Stale Targeted'), findsNothing);
    });

    testWidgets('stale Trending failure cannot clear newer loading or data', (
      tester,
    ) async {
      home
        ..readyBatchLabels.add('For You')
        ..immediateTrending = [_series('Initial Trending')];
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pumpAndSettle();

      home.holdTrending = true;
      var section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onTypeChanged('manga');
      await tester.pump();
      section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onWindowChanged(30);
      await tester.pump();

      home.trendingRequests[0].completer.completeError(
        StateError('stale failure'),
      );
      await tester.pump();
      section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      expect(section.loading, isTrue);

      home.trendingRequests[1].completer.complete([
        _series('Current Trending'),
      ]);
      await tester.pumpAndSettle();
      section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      expect(section.loading, isFalse);
      expect(find.text('Current Trending'), findsOneWidget);
    });

    testWidgets('current Trending failure clears loading and later succeeds', (
      tester,
    ) async {
      home
        ..readyBatchLabels.add('For You')
        ..immediateTrending = [_series('Initial Trending')];
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pumpAndSettle();

      home.holdTrending = true;
      var section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onTypeChanged('manga');
      await tester.pump();
      home.trendingRequests.single.completer.completeError(
        StateError('current failure'),
      );
      await tester.pumpAndSettle();
      section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      expect(section.loading, isFalse);
      expect(find.text('Initial Trending'), findsOneWidget);

      section.onWindowChanged(30);
      await tester.pump();
      home.trendingRequests[1].completer.complete([
        _series('Recovered Trending'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Recovered Trending'), findsOneWidget);
    });

    testWidgets('disposal ignores late targeted Trending completion', (
      tester,
    ) async {
      home
        ..readyBatchLabels.add('For You')
        ..immediateTrending = [_series('Initial Trending')];
      await tester.pumpWidget(MaterialApp(home: HomeScreen(homeService: home)));
      home.readinessRequests.single.complete(_ready);
      await tester.pumpAndSettle();

      home.holdTrending = true;
      final section = tester.widget<HomeTrendingSection>(
        find.byType(HomeTrendingSection),
      );
      section.onTypeChanged('manga');
      await tester.pump();
      final held = home.trendingRequests.single.completer;

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      held.complete([_series('Too Late Trending')]);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Too Late Trending'), findsNothing);
    });
  });
}
