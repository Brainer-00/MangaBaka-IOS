part of 'library_collections_panel.dart';

class _CollectionDetail extends StatefulWidget {
  const _CollectionDetail({required this.catalog, required this.listId});

  final _Catalog catalog;
  final int listId;

  @override
  State<_CollectionDetail> createState() => _CollectionDetailState();
}

class _CollectionDetailState extends State<_CollectionDetail> {
  _Catalog get _catalog => widget.catalog;
  final _search = CollectionHeaderSearch();
  bool _selecting = false;
  bool _submitting = false;
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _catalog.addListener(_invalidateSelection);
    SettingsManager().addListener(_pruneSelection);
  }

  @override
  void dispose() {
    _catalog.removeListener(_invalidateSelection);
    SettingsManager().removeListener(_pruneSelection);
    _search.dispose();
    super.dispose();
  }

  void _invalidateSelection() {
    if (!_catalog.live) _search.close();
    if (!_catalog.canWrite ||
        _catalog.find(widget.listId)?.hasCurrentMembers != true) {
      _clearSelection();
    }
  }

  void _clearSelection() {
    if (_selected.isNotEmpty) setState(_selected.clear);
  }

  void _pruneSelection() {
    final collection = _catalog.find(widget.listId);
    if (_selected.isEmpty || collection == null) return;
    final visible = _shown(collection).map((entry) => entry.series.id).toSet();
    if (!visible.containsAll(_selected)) {
      setState(() => _selected.retainAll(visible));
    }
  }

  Iterable<LibraryEntry> _shown(LibraryCollection collection) =>
      (collection.members ?? const <LibraryEntry>[]).where(
        (entry) =>
            _contentVisible(entry) &&
            _matches(entry, _search.text.text.trim().toLowerCase()),
      );

  Future<void> _removeTitles(LibraryCollection collection) async {
    if (_submitting || !_catalog.canWrite || !collection.hasCurrentMembers) {
      return;
    }
    final ids = _shown(
      collection,
    ).map((entry) => entry.series.id).toSet().intersection(_selected);
    if (ids.isEmpty) return;
    final list = collection.list;
    if (!await _confirmMembership(
      context,
      _catalog,
      list,
      ids.length,
      add: false,
    )) {
      return;
    }
    if (!mounted ||
        !_catalog.canWrite ||
        !identical(collection, _catalog.find(list.id)) ||
        !ids.every(_selected.contains) ||
        !_shown(
          collection,
        ).map((entry) => entry.series.id).toSet().containsAll(ids)) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await _catalog.library.changeCollectionMembership(
        _catalog.lease,
        listId: list.id,
        seriesIds: ids,
        add: false,
      );
      if (!mounted || !_catalog.live) return;
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      _membershipFeedback(context, result, add: false);
    } catch (_) {
      if (mounted && _catalog.live) {
        _writeFeedback(context, CollectionWriteOutcome.rejected);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _catalog,
      LocalizationService(),
      SettingsManager(),
      _search,
      _search.text,
    ]),
    builder: (context, _) {
      final collection = _catalog.find(widget.listId);
      final searching = _search.expanded;
      return PopScope(
        canPop: !searching,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && searching) {
            _search.close();
            _clearSelection();
          }
        },
        child: Actions(
          actions: {
            RefreshIntent: CallbackAction<RefreshIntent>(
              onInvoke: (_) {
                _catalog.refresh();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: !searching,
                title: searching
                    ? CollectionSearchField(
                        search: _search,
                        label: _t('collection_search_titles'),
                        onChanged: (_) => _clearSelection(),
                      )
                    : Text(_t('collection_my_lists')),
                actions: [
                  if (!searching && collection != null && _catalog.live)
                    IconButton(
                      tooltip: _t('collection_search_titles'),
                      onPressed: _search.open,
                      icon: const Icon(Icons.search),
                    ),
                ],
              ),
              body: SafeArea(
                top: false,
                child: !_catalog.live
                    ? _CollectionMessage(_t('collection_session_changed'))
                    : collection == null
                    ? _CollectionMessage(
                        _t('collection_unavailable'),
                        onRetry: _catalog.refresh,
                      )
                    : Semantics(
                        customSemanticsActions: {
                          CustomSemanticsAction(label: _t('sync_now')):
                              _catalog.refresh,
                        },
                        child: RefreshIndicator(
                          onRefresh: _catalog.refresh,
                          child: _content(context, collection),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _content(BuildContext context, LibraryCollection collection) {
    final list = collection.list;
    final entries = _shown(collection).toList();
    final selected = entries
        .map((entry) => entry.series.id)
        .toSet()
        .intersection(_selected);
    final canWrite = _catalog.canWrite && !_submitting;
    final canSelect = canWrite && collection.hasCurrentMembers;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth - 22) / 145).floor().clamp(
          1,
          12,
        );
        final width =
            (constraints.maxWidth - 24 - 10 * (columns - 1)) / columns;
        return CustomScrollView(
          key: PageStorageKey('collection-detail-${list.id}'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _ListHeading(list)),
                        IconButton(
                          color: context.colors.accentForeground,
                          tooltip: _t('collection_edit_list'),
                          onPressed: canWrite && !_selecting
                              ? () => _editList(context, _catalog, list: list)
                              : null,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    Text(_count(list.seriesCount!)),
                    const SizedBox(height: 8),
                    if (_selecting)
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _t(
                                'collection_selected',
                              ).replaceAll('{count}', '${selected.length}'),
                            ),
                          ),
                          TextButton(
                            onPressed: !canSelect || entries.isEmpty
                                ? null
                                : () => setState(() {
                                    _selected.clear();
                                    if (selected.length != entries.length) {
                                      _selected.addAll(
                                        entries.map((entry) => entry.series.id),
                                      );
                                    }
                                  }),
                            child: Text(
                              _t(
                                entries.isNotEmpty &&
                                        selected.length == entries.length
                                    ? 'collection_deselect_all'
                                    : 'select_all',
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(() {
                                    _selecting = false;
                                    _selected.clear();
                                  }),
                            child: Text(_t('cancel')),
                          ),
                          TextButton(
                            style: _destructiveStyle(context),
                            onPressed: !canSelect || selected.isEmpty
                                ? null
                                : () => _removeTitles(collection),
                            child: Text(_t('collection_remove_from_list')),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: canSelect
                                ? () =>
                                      _addTitles(context, _catalog, collection)
                                : null,
                            icon: const Icon(Icons.add),
                            label: Text(_t('collection_add_titles')),
                          ),
                          TextButton.icon(
                            onPressed: !canSelect || entries.isEmpty
                                ? null
                                : () => setState(() => _selecting = true),
                            icon: const Icon(Icons.checklist),
                            label: Text(_t('collection_select')),
                          ),
                        ],
                      ),
                    if (_catalog.busy || _submitting)
                      const LinearProgressIndicator(),
                    if (collection.membersStale && entries.isNotEmpty)
                      _CollectionMessage(
                        _t('collection_members_stale'),
                        onRetry: _catalog.refresh,
                      ),
                    if (_catalog.failed)
                      _CollectionMessage(
                        _t('collection_refresh_failed'),
                        onRetry: _catalog.refresh,
                      ),
                  ],
                ),
              ),
            ),
            if (entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _CollectionMessage(
                  _t(
                    collection.membersStale
                        ? 'collection_members_stale'
                        : collection.members == null
                        ? 'collection_list_incomplete'
                        : list.seriesCount == 0
                        ? 'collection_no_titles'
                        : _search.text.text.trim().isNotEmpty
                        ? 'no_results'
                        : 'collection_no_visible_titles',
                  ),
                ),
              ),
            if (entries.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: _cardHeight(context, width),
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final entry = entries[index];
                      void toggle() {
                        if (!canSelect || !_catalog.canWrite) return;
                        setState(() {
                          if (!_selected.add(entry.series.id)) {
                            _selected.remove(entry.series.id);
                          }
                        });
                      }

                      return _CollectionCard(
                        key: ValueKey(entry.series.id),
                        entry: entry,
                        lease: _catalog.lease,
                        prefix: 'collection_detail_${list.id}',
                        selected: _selecting
                            ? selected.contains(entry.series.id)
                            : null,
                        onTap: _selecting
                            ? toggle
                            : () {
                                if (_catalog.live) {
                                  _openSeries(context, entry.series);
                                }
                              },
                      );
                    },
                    childCount: entries.length,
                    findChildIndexCallback: (key) {
                      final index = entries.indexWhere(
                        (entry) =>
                            entry.series.id == (key as ValueKey<String>).value,
                      );
                      return index < 0 ? null : index;
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
