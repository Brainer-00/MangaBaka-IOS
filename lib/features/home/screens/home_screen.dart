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
  List<TopGenreRail> _genreRails = const [];

  /// API `type` filter for the Trending rail; null means every type.
  String? _trendingType;

  /// Trending window in days — 7 or 30.
  int _trendingWindow = 7;

  bool _loadingTrending = true;
  bool _loadingRising = true;
  bool _loadingHiddenGems = true;
  bool _loadingNewReleases = true;
  bool _showForYou = false;

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
  }) async {
    if (!mounted) return;
    setState(() {
      // A refresh is signalled by RefreshIndicator. Keep useful rail content in
      // place rather than replacing it with skeletons while its successor loads.
      _loadingTrending = _trending.isEmpty;
      _loadingRising = _rising.isEmpty;
      _loadingHiddenGems = _hiddenGems.isEmpty;
      _loadingNewReleases = _newReleases.isEmpty;
    });

    // Start independent work before waiting on the personalized readiness
    // probe. Each result owns only its rail, so a slow endpoint cannot keep
    // already-available public content behind a full-page skeleton.
    final readiness = _homeService.fetchForYouReadiness();
    await Future.wait([
      _loadForYou(generation, readiness),
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
      _loadRail(
        operation: 'Top genre rails',
        request: _homeService.fetchTopGenreRails(),
        isCurrent: () => _isCurrentRailsGeneration(generation),
        apply: (rails) => _genreRails = rails,
        clearLoading: () {},
      ),
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

  Future<void> _loadForYou(
    int generation,
    Future<ForYouReadiness?> readinessRequest,
  ) async {
    try {
      // "For You" remains gated so cold profiles do not show an empty rail.
      final readiness = await readinessRequest;
      if (!_isCurrentRailsGeneration(generation)) return;
      final wantsForYou = readiness?.isReady ?? false;
      if (!wantsForYou) {
        setState(() {
          _showForYou = false;
        });
        return;
      }

      final series = await _homeService.fetchForYou();
      if (!_isCurrentRailsGeneration(generation)) return;
      setState(() {
        _forYou = series;
        _showForYou = true;
      });
    } catch (error) {
      _logger.warning('For-you load failed (${error.runtimeType})');
      if (!_isCurrentRailsGeneration(generation)) return;
      setState(() {
        _showForYou = false;
      });
    }
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
                  if (_showForYou)
                    HomeRail(title: l10n.translate('for_you'), series: _forYou),
                  for (final rail in _genreRails)
                    HomeRail(
                      title: l10n
                          .translate('top_in_genre')
                          .replaceAll('{genre}', rail.genre.name),
                      series: rail.series,
                      onViewAll: () => _openGenreAll(rail.genre),
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
                    loading: _loadingNewReleases && _newReleases.isEmpty,
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
