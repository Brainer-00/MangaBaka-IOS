import 'package:flutter/material.dart';
import 'package:mangabaka_app/features/library/widgets/collection_header_search.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';
import 'package:mangabaka_app/core/widgets/app_snack_bar.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/browse/utils/browse_helpers.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/filter_chips_row.dart';
import 'package:mangabaka_app/features/library/constants/library_screen_constants.dart';
import 'package:mangabaka_app/features/library/controllers/library_session.dart';
import 'package:mangabaka_app/features/library/controllers/library_tab_coordinator.dart';
import 'package:mangabaka_app/features/library/helpers/library_filter_helper.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/widgets/library_app_bar.dart';
import 'package:mangabaka_app/features/library/widgets/library_body.dart';
import 'package:mangabaka_app/features/library/widgets/library_collections_panel.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_banners.dart';
import 'package:mangabaka_app/features/library/widgets/library_tab_bar.dart';
import 'package:mangabaka_app/features/navigation/screens/main_screen.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';
import 'package:mangabaka_app/features/series/models/series.dart' as api;
import 'package:mangabaka_app/features/series/screens/series_detail_screen.dart';
import 'package:mangabaka_app/shared/transitions/app_transitions.dart';
import 'package:mangabaka_app/shared/widgets/app_shortcuts.dart';

/// The user's library, tabbed by reading status.
///
/// Holds the search and filter state and the widgets that display it.
/// [LibrarySession] owns the account connection — the entries stream, the
/// sync, sign-in — and [LibraryTabCoordinator] decides which tab should be
/// showing and what each one's badge reads.
class LibraryScreen extends StatefulWidget {
  static final GlobalKey<LibraryScreenState> libraryScreenKey =
      GlobalKey<LibraryScreenState>();

  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen>
    with TickerProviderStateMixin {
  static final _logger = LoggingService.logger;

  /// Widest the list grows before it is centred. Grids are left unbounded —
  /// they use the extra width for more columns, where a list would just get
  /// unreadably long lines.
  static const double _maxListWidth = 800;

  late final LibraryService _libraryService;
  late final LibrarySession _session;
  late final LibraryTabCoordinator _tabs;
  late final TabController _tabController;
  late final Map<String, ScrollController> _scrollControllers;

  final collectionSearch = CollectionHeaderSearch();
  var _collectionsKey = GlobalKey<LibraryCollectionsPanelState>();
  final FocusNode _searchFocusNode = FocusNode();

  String _query = '';
  SearchFilters _filters = SearchFilters();
  bool _isSearching = false;
  bool _showCollections = false;
  bool _openedCollections = false;

  // ─── Public surface, driven by MainScreen's shared top nav bar ───────────

  FocusNode get searchFocusNode => _searchFocusNode;
  Stream<List<LibraryEntry>>? get entriesStream => _session.entriesStream;
  SearchFilters get filters => _filters;
  String get query => _query;
  bool get showingCollections => _showCollections;

  void _selectSection(int index) {
    if (_showCollections == (index == 1)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _showCollections = index == 1;
      _openedCollections = true;
    });
    context.findAncestorStateOfType<MainScreenState>()?.updateTopNavBar();
  }

  void enterSearchMode() {
    if (_showCollections) {
      collectionSearch.open();
      return;
    }
    setState(() => _isSearching = true);
    _searchFocusNode.requestFocus();
  }

  void updateQuery(String value) {
    setState(() => _query = value);
    _tabs.setQuery(value);
    _tabs.autoSwitch();
  }

  void updateFilters(SearchFilters filters) {
    setState(() => _filters = filters);
    _tabs.setFilters(filters);
    _tabs.autoSwitch();
  }

  void handleResultSelected(AutocompleteSeriesResult result) {
    _logger.info('Library autocomplete result selected');
    _navigateToSeriesDetail(BrowseHelpers.convertAutocompleteToSeries(result));
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _logger.info('Library screen initialized');

    _libraryService = getIt<LibraryService>();

    _tabController = TabController(
      length: LibraryScreenConstants.tabs.length,
      vsync: this,
    );
    _tabController.addListener(_handleTabSelection);
    _tabs = LibraryTabCoordinator(controller: _tabController);
    _scrollControllers = {
      for (final tab in LibraryScreenConstants.tabs)
        tab.key: ScrollController(),
    };

    _session = LibrarySession(onEntries: _onEntriesUpdate);
    _observedEntries = _session.entriesStream;
    _observedLease = _session.lease;
    _session.addListener(_onSessionChanged);

    // The shared top nav bar hosts this screen's search field on wide
    // layouts, and can only pick it up once this screen is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.findAncestorStateOfType<MainScreenState>()?.updateTopNavBar();
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    collectionSearch.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (!_tabController.indexIsChanging) return;
    _logger.info('Library tab switched to: ${_tabController.index}');
  }

  Stream<List<LibraryEntry>>? _observedEntries;
  Object? _observedLease;

  void _onSessionChanged() {
    if (!mounted) return;
    if (!identical(_observedEntries, _session.entriesStream)) {
      _observedEntries = _session.entriesStream;
      _tabs.setEntries(const []);
    }
    if (!identical(_observedLease, _session.lease)) {
      _observedLease = _session.lease;
      _collectionsKey = GlobalKey<LibraryCollectionsPanelState>();
      collectionSearch.reset();
      collectionSearch.setAvailable(true);
    }
    setState(() {});
  }

  void _onEntriesUpdate(List<LibraryEntry> entries) {
    if (!mounted) return;
    _tabs.setEntries(entries);
    _tabs.autoSwitch();
  }

  Future<void> _login() async {
    final errorKey = await _session.login();
    if (errorKey == null || !mounted) return;
    AppSnackBar.show(
      context,
      LocalizationService().translate(errorKey),
      isError: true,
    );
  }

  // ─── Search ──────────────────────────────────────────────────────────────

  void _exitSearch() {
    if (_showCollections) {
      collectionSearch.close();
      return;
    }
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _query = '';
      _filters = SearchFilters();
    });
    _tabs.reset();
  }

  void _navigateToSeriesDetail(api.Series series) {
    Navigator.of(
      context,
    ).push(AppTransitions.slideUp(SeriesDetailScreen(series: series)));
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        LocalizationService(),
        SettingsManager(),
        collectionSearch,
      ]),
      builder: (context, _) {
        final isGrid = SettingsManager().resolvedLibraryListStyle.isGrid;

        return PopScope(
          // Back leaves search before it leaves the tab.
          canPop: _showCollections ? !collectionSearch.expanded : !_isSearching,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || (_showCollections && !collectionSearch.expanded)) {
              return;
            }
            _exitSearch();
          },
          child: StreamBuilder<List<LibraryEntry>>(
            // A new account must never inherit the previous stream snapshot.
            key: ObjectKey(_session.entriesStream),
            stream: _session.entriesStream,
            builder: (context, snapshot) {
              final result = snapshot.hasData
                  ? _tabs.filterFor(snapshot.data!).result
                  : null;
              return Scaffold(
                backgroundColor: context.colors.background,
                appBar: _buildAppBar(context),
                body: Column(
                  children: [
                    if (MainScreen.showSearchBarInTopNavBar(context))
                      _sectionSelector(),
                    Expanded(
                      child: IndexedStack(
                        index: _showCollections ? 1 : 0,
                        sizing: StackFit.expand,
                        children: [
                          ExcludeFocus(
                            excluding: _showCollections,
                            child: TickerMode(
                              enabled: !_showCollections,
                              child: Column(
                                children: [
                                  _statusTabs(context, result),
                                  Expanded(
                                    child:
                                        ValueListenableBuilder<
                                          LibrarySyncStatus
                                        >(
                                          valueListenable:
                                              _libraryService.syncStatus,
                                          builder: (context, status, _) => Actions(
                                            actions: <Type, Action<Intent>>{
                                              SearchIntent:
                                                  CallbackAction<SearchIntent>(
                                                    onInvoke: (_) {
                                                      enterSearchMode();
                                                      return null;
                                                    },
                                                  ),
                                              RefreshIntent:
                                                  CallbackAction<RefreshIntent>(
                                                    onInvoke: (_) {
                                                      _session.refresh();
                                                      return null;
                                                    },
                                                  ),
                                            },
                                            child:
                                                WidgetUtils.responsiveConstraint(
                                                  _buildContent(
                                                    status,
                                                    snapshot,
                                                    result,
                                                  ),
                                                  maxWidth: isGrid
                                                      ? double.infinity
                                                      : _maxListWidth,
                                                ),
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ExcludeFocus(
                            excluding: !_showCollections,
                            child: TickerMode(
                              enabled: _showCollections,
                              child: _openedCollections
                                  ? LibraryCollectionsPanel(
                                      key: _collectionsKey,
                                      search: collectionSearch,
                                      lease: _session.lease,
                                      active: _showCollections,
                                      loggedIn: _session.isLoggedIn,
                                      onLogin: _login,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildContent(
    LibrarySyncStatus status,
    AsyncSnapshot<List<LibraryEntry>> snapshot,
    LibraryFilterResult? result,
  ) {
    return Column(
      children: [
        LibraryStatusBanners(
          loggedIn: _session.isLoggedIn,
          status: status,
          onRetrySync: _session.refresh,
          onDismissError: () => _libraryService.syncStatus.value =
              _libraryService.syncStatus.value.copyWith(clearError: true),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilterChipsRow(
            filters: _filters,
            onFiltersChanged: updateFilters,
          ),
        ),
        Expanded(
          child: LibraryBody(
            loggedIn: _session.isLoggedIn,
            hasEntriesStream: _session.entriesStream != null,
            snapshot: snapshot,
            result: result,
            tabController: _tabController,
            scrollControllers: _scrollControllers,
            onRefresh: _session.refresh,
            onLogin: _login,
            onItemTap: _navigateToSeriesDetail,
          ),
        ),
      ],
    );
  }

  /// Null when the shared top nav bar is hosting the search field instead —
  /// two search fields on one screen would be a confusing duplicate.
  PreferredSizeWidget? _buildAppBar(BuildContext context) {
    if (MainScreen.showSearchBarInTopNavBar(context)) return null;

    return LibraryAppBar(
      isSearching: _showCollections ? collectionSearch.expanded : _isSearching,
      searchAvailable: !_showCollections || collectionSearch.available,
      contextualSearch: _showCollections
          ? CollectionSearchField(
              search: collectionSearch,
              label: LocalizationService().translate(collectionSearch.labelKey),
            )
          : null,
      showLibraryActions: !_showCollections,
      isLandscape: MediaQuery.orientationOf(context) == Orientation.landscape,
      searchFocusNode: _searchFocusNode,
      entriesStream: _session.entriesStream,
      filters: _filters,
      query: _query,
      onEnterSearch: enterSearchMode,
      onExitSearch: _exitSearch,
      onQueryChanged: updateQuery,
      onFiltersChanged: updateFilters,
      onResultSelected: handleResultSelected,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(
          MediaQuery.textScalerOf(context).scale(16) + 32,
        ),
        child: _sectionSelector(),
      ),
    );
  }

  Widget _sectionSelector() {
    final l10n = LocalizationService();
    return LibrarySectionSelector(
      labels: [l10n.translate('library'), l10n.translate('collection_section')],
      selected: _showCollections ? 1 : 0,
      onChanged: _selectSection,
    );
  }

  LibraryTabBar _statusTabs(
    BuildContext context,
    LibraryFilterResult? result,
  ) => LibraryTabBar(
    controller: _tabController,
    counts: result?.counts ?? const {},
    isLandscape: MediaQuery.orientationOf(context) == Orientation.landscape,
  );
}
