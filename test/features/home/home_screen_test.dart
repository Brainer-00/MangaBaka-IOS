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

class _ControlledHomeService extends Fake implements HomeService {
  final readinessRequests = <Completer<ForYouReadiness?>>[];
  final trendingRequests = <_TrendingRequest>[];
  final readyBatchLabels = <String>[];
  List<Series> immediateTrending = const [];
  bool holdTrending = false;
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
    return const [];
  }

  @override
  Future<List<Series>> fetchHiddenGems({int limit = 20}) async {
    requestCount++;
    return const [];
  }

  @override
  Future<List<Series>> fetchNewReleases({int limit = 20}) async {
    requestCount++;
    return const [];
  }

  @override
  Future<List<TopGenreRail>> fetchTopGenreRails({int genres = 3}) async {
    // One top-genres request plus up to three top-in-genre requests.
    requestCount += 4;
    return const [];
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

        expect(actualRequests, 1);

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

      expect(home.requestCount, 20);
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
      await tester.pumpAndSettle();

      auth.notifyAuthChanged();
      await tester.pump();
      expect(home.readinessRequests, hasLength(2));
      home.readinessRequests[1].complete(_ready);
      await tester.pumpAndSettle();

      expect(find.text('Recovered Result'), findsOneWidget);
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
