import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';
import 'package:mangabaka_app/core/widgets/design/mb_screen_header.dart';
import 'package:mangabaka_app/features/browse/screens/browse_results_screen.dart';
import 'package:mangabaka_app/features/home/services/home_service.dart';
import 'package:mangabaka_app/features/home/widgets/home_rail.dart';
import 'package:mangabaka_app/features/home/widgets/home_trending_section.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/shared/transitions/app_transitions.dart';
import 'package:mangabaka_app/features/profile/screens/settings_screen.dart';

/// The Home feed: a rotating spotlight of what's hot, then progressively broader
/// discovery — personalised, then trending, then the long tail. Mirrors the
/// sections of the web `/discover` page.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.homeService});

  /// Optional for deterministic tests. Ownership transfers to this screen.
  final HomeService? homeService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _logger = LoggingService.logger;

  late final HomeService _homeService;
  late final ProfileAuthService _auth;

  Future<void>? _activeRailsLoad;
  String? _activeRailsContext;
  int _railsGeneration = 0;
  int _trendingGeneration = 0;

  List<Series> _forYou = const [];
  List<Series> _trending = const [];
  List<Series> _rising = const [];
  List<Series> _hiddenGems = const [];
  List<Series> _newReleases = const [];
  List<TopGenre> _topGenres = const [];
  final Map<int, List<Series>> _genreSeries = {};
  final Set<int> _loadingGenreIds = {};

  /// API `type` filter for the Trending rail; null means every type.
  String? _trendingType;

  /// Trending window in days — 7 or 30.
  int _trendingWindow = 7;

  bool _loadingTrending = true;
  bool _loadingRising = true;
  bool _loadingHiddenGems = true;
  bool _loadingNewReleases = true;
  bool _loadingForYou = false;
  bool _showForYou = false;
  bool _structureEstablished = false;
  bool _structureIsFallback = false;
  String? _structureContext;

  @override
  void initState() {
    super.initState();
    _homeService = widget.homeService ?? HomeService();
    _auth = getIt<ProfileAuthService>();
    _auth.addListener(_onAuthChanged);
    _loadRails();
    _logger.info('HomeScreen initialized');
  }

  @override
  void dispose() {
    _railsGeneration++;
    _trendingGeneration++;
    _auth.removeListener(_onAuthChanged);
    _homeService.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    _loadRails();
  }

  String get _authContext =>
      '${_auth.isLoggedIn}:${_auth.cachedProfile?.id ?? ''}';

  Future<void> _loadRails({bool force = false}) {
    final context = _authContext;
    final active = _activeRailsLoad;
    if (!force && active != null && _activeRailsContext == context) {
      return active;
    }

    final generation = ++_railsGeneration;
    final trendingGeneration = ++_trendingGeneration;
    final trendingType = _trendingType;
    final trendingWindow = _trendingWindow;
    _activeRailsContext = context;
    late final Future<void> load;
    load =
        _runRailsLoad(
          generation,
          trendingGeneration: trendingGeneration,
          trendingType: trendingType,
          trendingWindow: trendingWindow,
          preserveStructure:
              _structureEstablished && _structureContext == context,
          structureContext: context,
        ).whenComplete(() {
          if (identical(_activeRailsLoad, load)) {
            _activeRailsLoad = null;
            _activeRailsContext = null;
          }
        });
    _activeRailsLoad = load;
    return load;
  }

  Future<void> _runRailsLoad(
    int generation, {
    required int trendingGeneration,
    required String? trendingType,
    required int trendingWindow,
    required bool preserveStructure,
    required String structureContext,
  }) async {
    if (!mounted) return;
    setState(() {
      // A refresh is signalled by RefreshIndicator. Keep useful rail content in
      // place rather than replacing it with skeletons while its successor loads.
      _loadingTrending = _trending.isEmpty;
      _loadingRising = _rising.isEmpty;
      _loadingHiddenGems = _hiddenGems.isEmpty;
      _loadingNewReleases = _newReleases.isEmpty;
      if (!preserveStructure) {
        _structureEstablished = false;
        _structureContext = null;
        _showForYou = false;
        _loadingForYou = false;
        _forYou = const [];
        _topGenres = const [];
        _genreSeries.clear();
        _loadingGenreIds.clear();
        _structureIsFallback = false;
      }
    });

    // Start independent work before waiting on the personalized readiness
    // probe. Each result owns only its rail, so a slow endpoint cannot keep
    // already-available public content behind a full-page skeleton.
    final readiness = _homeService.fetchForYouReadiness();
    final topGenres = _homeService.fetchTopGenres();
    final structure = _establishStructure(
      generation,
      readiness: readiness,
      topGenres: topGenres,
      preserveStructure: preserveStructure,
      structureContext: structureContext,
    );
    await Future.wait([
      _loadForYou(generation, structure),
      _loadRail(
        operation: 'Trending',
        request: _homeService.fetchTrending(
          type: trendingType,
          windowDays: trendingWindow,
        ),
        isCurrent: () =>
            _isCurrentRailsGeneration(generation) &&
            trendingGeneration == _trendingGeneration,
        apply: (series) => _trending = series,
        clearLoading: () => _loadingTrending = false,
      ),
      _loadRail(
        operation: 'Rising',
        request: _homeService.fetchRising(),
        isCurrent: () => _isCurrentRailsGeneration(generation),
        apply: (series) => _rising = series,
        clearLoading: () => _loadingRising = false,
      ),
      _loadRail(
        operation: 'Hidden gems',
        request: _homeService.fetchHiddenGems(),
        isCurrent: () => _isCurrentRailsGeneration(generation),
        apply: (series) => _hiddenGems = series,
        clearLoading: () => _loadingHiddenGems = false,
      ),
      _loadRail(
        operation: 'New releases',
        request: _homeService.fetchNewReleases(),
        isCurrent: () => _isCurrentRailsGeneration(generation),
        apply: (series) => _newReleases = series,
        clearLoading: () => _loadingNewReleases = false,
      ),
      _loadTopGenreContent(generation, structure),
    ]);
  }

  bool _isCurrentRailsGeneration(int generation) =>
      mounted && generation == _railsGeneration;

  Future<void> _loadRail<T>({
    required String operation,
    required Future<T> request,
    required bool Function() isCurrent,
    required void Function(T value) apply,
    required VoidCallback clearLoading,
  }) async {
    try {
      final value = await request;
      if (!isCurrent()) return;
      setState(() {
        apply(value);
        clearLoading();
      });
    } catch (error) {
      _logger.warning('Home $operation load failed (${error.runtimeType})');
      if (!isCurrent()) return;
      setState(clearLoading);
    }
  }

  Future<_HomeStructure?> _establishStructure(
    int generation, {
    required Future<ForYouReadiness?> readiness,
    required Future<List<TopGenre>> topGenres,
    required bool preserveStructure,
    required String structureContext,
  }) async {
    try {
      final results = await Future.wait([readiness, topGenres]);
      if (!_isCurrentRailsGeneration(generation)) return null;

      if (preserveStructure && !_structureIsFallback) {
        return _HomeStructure(showForYou: _showForYou, genres: _topGenres);
      }

      final showForYou = (results[0] as ForYouReadiness?)?.isReady ?? false;
      final genres = results[1] as List<TopGenre>;
      setState(() {
        _showForYou = showForYou;
        _loadingForYou = showForYou;
        _topGenres = genres;
        _loadingGenreIds
          ..clear()
          ..addAll(genres.map((genre) => genre.tagId));
        _structureEstablished = true;
        _structureIsFallback = false;
        _structureContext = structureContext;
      });
      return _HomeStructure(showForYou: showForYou, genres: genres);
    } catch (error) {
      _logger.warning('Home structure load failed (${error.runtimeType})');
      if (!_isCurrentRailsGeneration(generation)) return null;

      if (preserveStructure) {
        return _HomeStructure(showForYou: _showForYou, genres: _topGenres);
      }

      setState(() {
        _showForYou = false;
        _loadingForYou = false;
        _topGenres = const [];
        _loadingGenreIds.clear();
        _structureEstablished = true;
        _structureIsFallback = true;
        _structureContext = structureContext;
      });
      return const _HomeStructure(showForYou: false, genres: []);
    }
  }

  Future<void> _loadForYou(
    int generation,
    Future<_HomeStructure?> structureRequest,
  ) async {
    try {
      final structure = await structureRequest;
      if (structure == null || !structure.showForYou) return;

      final series = await _homeService.fetchForYou();
      if (!_isCurrentRailsGeneration(generation)) return;
      setState(() {
        _forYou = series;
        _showForYou = true;
        _loadingForYou = false;
      });
    } catch (error) {
      _logger.warning('For-you load failed (${error.runtimeType})');
      if (!_isCurrentRailsGeneration(generation)) return;
      setState(() {
        _loadingForYou = false;
      });
    }
  }

  Future<void> _loadTopGenreContent(
    int generation,
    Future<_HomeStructure?> structureRequest,
  ) async {
    final structure = await structureRequest;
    if (structure == null) return;
    await Future.wait([
      for (final genre in structure.genres)
        _loadRail(
          operation: 'Top in ${genre.name}',
          request: _homeService.fetchTopInGenre(genre.tagId),
          isCurrent: () => _isCurrentRailsGeneration(generation),
          apply: (series) => _genreSeries[genre.tagId] = series,
          clearLoading: () => _loadingGenreIds.remove(genre.tagId),
        ),
    ]);
  }

  /// Re-fetch only the Trending rail after a type / window change. The old
  /// results stay on screen (behind a skeleton) so the spotlight doesn't blink.
  Future<void> _reloadTrending() async {
    final generation = ++_trendingGeneration;
    final type = _trendingType;
    final window = _trendingWindow;
    setState(() => _loadingTrending = true);
    try {
      final list = await _homeService.fetchTrending(
        type: type,
        windowDays: window,
      );
      if (!mounted || generation != _trendingGeneration) return;
      setState(() {
        _trending = list;
        _loadingTrending = false;
      });
    } catch (error) {
      _logger.warning('Trending reload failed (${error.runtimeType})');
      if (!mounted || generation != _trendingGeneration) return;
      setState(() => _loadingTrending = false);
    }
  }

  void _openTrendingAll() {
    final l10n = LocalizationService();
    Navigator.of(context).push(
      AppTransitions.slideRight(
        BrowseResultsScreen(
          sortType: l10n.translate('trending'),
          sortBy: _trendingWindow == 30 ? 'trending_30d' : 'trending_7d',
          type: _trendingType,
        ),
      ),
    );
  }

  void _openGenreAll(TopGenre genre) {
    Navigator.of(context).push(
      AppTransitions.slideRight(
        BrowseResultsScreen(
          sortType: LocalizationService()
              .translate('top_in_genre')
              .replaceAll('{genre}', genre.name),
          sortBy: 'score_desc',
          tag: genre.tagId.toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([LocalizationService(), SettingsManager()]),
      builder: (context, _) {
        final l10n = LocalizationService();
        final structureEstablished = _structureEstablished;

        return Scaffold(
          backgroundColor: AppConstants.primaryBackground,
          appBar: mbScreenAppBar(
            title: l10n.translate('home'),
            isRoot: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => SettingsScreen.show(context),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: RefreshIndicator(
            color: AppConstants.accentColor,
            backgroundColor: AppConstants.secondaryBackground,
            onRefresh: () => _loadRails(force: true),
            child: WidgetUtils.responsiveConstraint(
              ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  if (!structureEstablished)
                    const _HomeInitialShell(key: ValueKey('home-initial-shell'))
                  else
                    KeyedSubtree(
                      key: const ValueKey('home-established-content'),
                      child: Column(
                        children: [
                          if (_showForYou)
                            HomeRail(
                              key: const ValueKey('home-for-you-rail'),
                              title: l10n.translate('for_you'),
                              series: _forYou,
                              loading: _loadingForYou && _forYou.isEmpty,
                            ),
                          for (final genre in _topGenres)
                            HomeRail(
                              key: ValueKey('home-top-genre-${genre.tagId}'),
                              title: l10n
                                  .translate('top_in_genre')
                                  .replaceAll('{genre}', genre.name),
                              series: _genreSeries[genre.tagId] ?? const [],
                              loading:
                                  _loadingGenreIds.contains(genre.tagId) &&
                                  (_genreSeries[genre.tagId]?.isEmpty ?? true),
                              onViewAll: () => _openGenreAll(genre),
                            ),
                          HomeTrendingSection(
                            series: _trending,
                            loading: _loadingTrending,
                            selectedType: _trendingType,
                            window: _trendingWindow,
                            onTypeChanged: (type) {
                              if (type == _trendingType) return;
                              setState(() => _trendingType = type);
                              _reloadTrending();
                            },
                            onWindowChanged: (days) {
                              if (days == _trendingWindow) return;
                              setState(() => _trendingWindow = days);
                              _reloadTrending();
                            },
                            onViewAll: _openTrendingAll,
                          ),
                          HomeRail(
                            title: l10n.translate('rising'),
                            series: _rising,
                            loading: _loadingRising && _rising.isEmpty,
                          ),
                          HomeRail(
                            title: l10n.translate('hidden_gems'),
                            series: _hiddenGems,
                            loading: _loadingHiddenGems && _hiddenGems.isEmpty,
                          ),
                          HomeRail(
                            title: l10n.translate('new_releases'),
                            series: _newReleases,
                            loading:
                                _loadingNewReleases && _newReleases.isEmpty,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeStructure {
  const _HomeStructure({required this.showForYou, required this.genres});

  final bool showForYou;
  final List<TopGenre> genres;
}

class _HomeInitialShell extends StatelessWidget {
  const _HomeInitialShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.horizontalPadding,
        vertical: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 148,
            height: 18,
            decoration: BoxDecoration(
              color: AppConstants.tertiaryBackground,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => Container(
                width: 118,
                decoration: BoxDecoration(
                  color: AppConstants.tertiaryBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
