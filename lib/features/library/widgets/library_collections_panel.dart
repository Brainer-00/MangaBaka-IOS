import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/database/database.dart'
    show LibraryCacheLease;
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/widgets/app_snack_bar.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/widgets/login/mb_login_prompt.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/series/screens/series_detail_screen.dart';
import 'package:mangabaka_app/features/series/widgets/entry_list_item.dart';
import 'package:mangabaka_app/shared/transitions/app_transitions.dart';

part 'library_collection_detail.dart';
part 'library_collection_sheets.dart';

String _t(String key) => LocalizationService().translate(key);

String _count(int count) => _t(
  count == 1 ? 'collection_one_title' : 'collection_title_count',
).replaceAll('{count}', '$count');

String _title(Series series) =>
    series.getDisplayTitle(SettingsManager().defaultTitleLanguage);

bool _contentVisible(LibraryEntry entry) {
  final preferences = SettingsManager().contentPreferences;
  return preferences.isEmpty ||
      preferences.contains(entry.series.contentRating.toLowerCase());
}

bool _matches(LibraryEntry entry, String query) =>
    query.isEmpty ||
    [
      entry.series.title,
      entry.series.nativeTitle,
      entry.series.romanizedTitle,
      ...entry.series.secondaryTitles,
    ].any((title) => title.toLowerCase().contains(query));

void _openSeries(BuildContext context, Series series) => Navigator.of(
  context,
).push(AppTransitions.slideUp(SeriesDetailScreen(series: series)));

/// A scrollable selector keeps translated labels and large text tappable.
class LibrarySectionSelector extends StatelessWidget {
  const LibrarySectionSelector({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Semantics(
                  selected: i == selected,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: i == selected
                          ? colors.onAccent
                          : colors.text,
                      backgroundColor: i == selected
                          ? colors.accent
                          : Colors.transparent,
                      minimumSize: const Size(48, 44),
                    ),
                    onPressed: () => onChanged(i),
                    child: Text(labels[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LibraryCollectionsPanel extends StatefulWidget {
  const LibraryCollectionsPanel({
    super.key,
    required this.lease,
    required this.active,
    required this.loggedIn,
    required this.onLogin,
  });

  final LibraryCacheLease? lease;
  final bool active;
  final bool loggedIn;
  final VoidCallback onLogin;

  @override
  State<LibraryCollectionsPanel> createState() =>
      _LibraryCollectionsPanelState();
}

class _LibraryCollectionsPanelState extends State<LibraryCollectionsPanel>
    with WidgetsBindingObserver {
  late final _Catalog? _catalog;
  final _storage = PageStorageBucket();
  var _stacks = false;
  final _search = TextEditingController();
  bool? _private;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lease = widget.lease;
    _catalog = lease == null ? null : _Catalog(getIt<LibraryService>(), lease);
    _setActive();
  }

  @override
  void didUpdateWidget(LibraryCollectionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _setActive();
  }

  void _setActive() => _catalog?.setActive(widget.active && !_stacks);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active && !_stacks) {
      unawaited(_catalog?.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _catalog?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibrarySectionSelector(
          labels: [_t('collection_my_lists'), _t('collection_stacks')],
          selected: _stacks ? 1 : 0,
          onChanged: (index) {
            if (_stacks == (index == 1)) return;
            FocusScope.of(context).unfocus();
            setState(() => _stacks = index == 1);
            _setActive();
          },
        ),
        Expanded(
          child: IndexedStack(
            index: _stacks ? 1 : 0,
            sizing: StackFit.expand,
            children: [
              if (catalog != null)
                ExcludeFocus(
                  excluding: _stacks,
                  child: PageStorage(bucket: _storage, child: _lists(catalog)),
                )
              else if (widget.loggedIn)
                const Center(child: CircularProgressIndicator())
              else
                MBLoginPrompt(
                  onLogin: widget.onLogin,
                  message: _t('login_prompt_library'),
                ),
              _CollectionMessage(_t('collection_stacks_unavailable')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lists(_Catalog catalog) => ListenableBuilder(
    listenable: Listenable.merge([catalog, SettingsManager()]),
    builder: (context, _) {
      if (!catalog.live) {
        return _CollectionMessage(_t('collection_session_changed'));
      }
      final query = _search.text.trim().toLowerCase();
      final all = catalog.collections;
      final shown = [
        for (final collection in all ?? const <LibraryCollection>[])
          if (_private == null || collection.list.isPrivate == _private)
            if (query.isEmpty ||
                collection.list.name.toLowerCase().contains(query))
              (
                collection,
                collection.members?.where(_contentVisible).toList(),
                false,
              )
            else if (collection.members != null)
              (
                collection,
                collection.members!
                    .where(
                      (entry) =>
                          _contentVisible(entry) && _matches(entry, query),
                    )
                    .toList(),
                true,
              ),
      ].where((row) => !row.$3 || row.$2!.isNotEmpty).toList();
      final incomplete = all?.any((item) => !item.hasCurrentMembers) ?? false;
      final controls = Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _t('collection_my_lists'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  color: context.colors.accentForeground,
                  tooltip: _t('collection_create_list'),
                  onPressed: catalog.canWrite
                      ? () => _editList(context, catalog)
                      : null,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  color: context.colors.accentForeground,
                  tooltip: _t('sync_now'),
                  onPressed: catalog.busy ? null : catalog.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: _CollectionSearch(
              label: _t('collection_search_lists'),
              controller: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          LibrarySectionSelector(
            labels: [
              _t('all'),
              _t('collection_public'),
              _t('collection_private'),
            ],
            selected: _private == null
                ? 0
                : _private!
                ? 2
                : 1,
            onChanged: (index) =>
                setState(() => _private = index == 0 ? null : index == 2),
          ),
          if (catalog.busy && all != null) const LinearProgressIndicator(),
        ],
      );
      return RefreshIndicator(
        onRefresh: catalog.refresh,
        child: CustomScrollView(
          key: const PageStorageKey('my-lists-overview'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: controls),
            if (all == null && catalog.busy)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
            if (catalog.failed || incomplete)
              SliverToBoxAdapter(
                child: _CollectionMessage(
                  _t(
                    catalog.failed
                        ? 'collection_refresh_failed'
                        : 'collection_members_incomplete',
                  ),
                  onRetry: catalog.refresh,
                ),
              ),
            if (all != null && shown.isEmpty && !catalog.failed)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _CollectionMessage(
                  _t(
                    all.isEmpty
                        ? 'collection_no_lists'
                        : incomplete && query.isNotEmpty
                        ? 'collection_no_loaded_matches'
                        : 'no_results',
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final (collection, entries, filtered) = shown[index];
                return _listSection(
                  context,
                  catalog,
                  collection,
                  entries,
                  filtered,
                );
              },
              findChildIndexCallback: (key) {
                final index = shown.indexWhere(
                  (row) => row.$1.list.id == (key as ValueKey<int>).value,
                );
                return index == -1 ? null : index;
              },
            ),
          ],
        ),
      );
    },
  );

  Widget _listSection(
    BuildContext context,
    _Catalog catalog,
    LibraryCollection collection,
    List<LibraryEntry>? entries,
    bool filtered,
  ) {
    final list = collection.list;
    return Padding(
      key: ValueKey(list.id),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (!catalog.live) return;
                    Navigator.of(context).push(
                      AppTransitions.slideUp(
                        _CollectionDetail(catalog: catalog, listId: list.id),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: _ListHeading(list),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      color: context.colors.accentForeground,
                      tooltip: _t('collection_edit_list'),
                      onPressed: catalog.canWrite
                          ? () => _editList(context, catalog, list: list)
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    Text(_count(list.seriesCount!), textAlign: TextAlign.end),
                  ],
                ),
              ),
            ],
          ),
          if (collection.membersStale) Text(_t('collection_members_stale')),
          if (filtered)
            Text(
              _t(
                entries!.length == 1
                    ? 'collection_one_match'
                    : 'collection_matches',
              ).replaceAll('{count}', '${entries.length}'),
            ),
          if (entries == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_t('collection_list_incomplete')),
            )
          else if (list.seriesCount == 0)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_t('collection_no_titles')),
                TextButton(
                  onPressed: catalog.canWrite && collection.hasCurrentMembers
                      ? () => _addTitles(context, catalog, collection)
                      : null,
                  child: Text(_t('collection_add_titles')),
                ),
              ],
            )
          else if (entries.isEmpty && !collection.membersStale)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_t('collection_no_visible_titles')),
            )
          else if (entries.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth / 2.45).clamp(
                  100.0,
                  144.0,
                );
                return SizedBox(
                  height: _cardHeight(context, cardWidth),
                  child: ListView.separated(
                    key: PageStorageKey('collection-preview-${list.id}'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(top: 4),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => SizedBox(
                      width: cardWidth,
                      child: _CollectionCard(
                        entry: entries[index],
                        lease: catalog.lease,
                        prefix: 'collection_preview_${list.id}',
                        onTap: () {
                          if (catalog.live) {
                            _openSeries(context, entries[index].series);
                          }
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Catalog extends ChangeNotifier {
  _Catalog(this.library, this.lease) {
    library.auth.addListener(_sessionChanged);
    library.collectionsRevision.addListener(_revisionChanged);
  }

  final LibraryService library;
  final LibraryCacheLease lease;
  List<LibraryCollection>? collections;
  Future<void>? _reading;
  bool _active = false;
  bool _dirty = true;
  bool _disposed = false;
  bool failed = false;

  bool get live => !_disposed && identical(lease, library.currentLease);
  bool get busy => _reading != null || (_active && _dirty);
  bool get canWrite => live && !busy && !failed && collections != null;

  LibraryCollection? find(int id) =>
      collections?.where((item) => item.list.id == id).firstOrNull;

  void setActive(bool active) {
    _active = active;
    if (live && active && _dirty) unawaited(refresh());
  }

  void _sessionChanged() {
    if (_disposed || live) return;
    collections = null;
    notifyListeners();
  }

  void _revisionChanged() {
    if (!live) return;
    _dirty = true;
    if (_active) unawaited(refresh());
  }

  Future<void> refresh() {
    if (!live) return Future.value();
    return _reading ??= Future<void>.microtask(_read);
  }

  Future<void> _read() async {
    try {
      while (live) {
        _dirty = false;
        notifyListeners();
        try {
          final result = await library.fetchCollections(lease);
          if (!live) return;
          if (_dirty) continue;
          // Keep existing rows in place. Newly discovered IDs are appended.
          final byId = {for (final item in result) item.list.id: item};
          collections = [
            for (final item in collections ?? const <LibraryCollection>[])
              if (byId.containsKey(item.list.id))
                byId.remove(item.list.id)!.retainMembersFrom(item),
            ...byId.values,
          ];
          failed = false;
        } catch (_) {
          if (!live) return;
          if (_dirty) continue;
          failed = true;
        }
        break;
      }
    } finally {
      _reading = null;
      if (live) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    library.auth.removeListener(_sessionChanged);
    library.collectionsRevision.removeListener(_revisionChanged);
    super.dispose();
  }
}

class _ListHeading extends StatelessWidget {
  const _ListHeading(this.list);

  final AccountLibraryList list;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(list.name, style: Theme.of(context).textTheme.titleMedium),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Text(
              _t(list.isPrivate ? 'collection_private' : 'collection_public'),
            ),
          ),
        ),
      ],
    );
  }
}

class _CollectionMessage extends StatelessWidget {
  const _CollectionMessage(
    this.message, {
    this.onRetry,
    this.buttonLabel = 'retry',
  });

  final String message;
  final VoidCallback? onRetry;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(_t(buttonLabel))),
        ],
      ),
    ),
  );
}

class _CollectionSearch extends StatelessWidget {
  const _CollectionSearch({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;

  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.search),
    ),
  );
}

double _cardHeight(BuildContext context, double width) =>
    width / .65 +
    12 +
    MediaQuery.textScalerOf(context).scale(17) *
        SettingsManager().compactGridTitleRows.clamp(1, 3);

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    super.key,
    required this.entry,
    required this.lease,
    required this.prefix,
    required this.onTap,
    this.selected,
  });

  final LibraryEntry entry;
  final LibraryCacheLease lease;
  final String prefix;
  final VoidCallback onTap;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: selected == null ? null : _title(entry.series),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              ExcludeFocus(
                excluding: selected != null,
                child: IgnorePointer(
                  ignoring: selected != null,
                  child: ExcludeSemantics(
                    excluding: selected != null,
                    child: EntryListItem(
                      key: ValueKey(entry.series.id),
                      series: entry.series,
                      isLibrary: true,
                      heroTagPrefix: prefix,
                      listStyle: AppListStyle.compactGrid,
                      fallbackEntry: (lease, entry),
                    ),
                  ),
                ),
              ),
              if (selected != null)
                PositionedDirectional(
                  bottom: 8,
                  end: 6,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected! ? colors.accent : colors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.accentForeground),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          selected! ? Icons.check : Icons.circle_outlined,
                          size: 18,
                          color: selected!
                              ? colors.onAccent
                              : colors.accentForeground,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
