part of 'stack_ui.dart';

class _StackDetailPage extends StatefulWidget {
  const _StackDetailPage(this.controller, this.access, this.summary);

  final StackController controller;
  final StackAccess access;
  final StackSummary summary;

  @override
  State<_StackDetailPage> createState() => _StackDetailPageState();
}

class _StackDetailPageState extends State<_StackDetailPage> {
  final _search = CollectionHeaderSearch();
  final _selected = <int>{};
  StreamSubscription<List<LibraryEntry>>? _library;
  Map<int, LibraryEntry> _tracked = {};
  bool _selecting = false;
  bool _showSpoilers = false;
  StackAccess? _readingAccess;
  late StackAccess? _observedAccess = widget.access;
  int _observedDetailAccess = 0;
  String? _readError;
  String? _statusError;

  StackController get _controller => widget.controller;
  LibraryCacheLease get _owner => widget.access.lease;
  bool get _reading => _readingAccess != null;
  int get _id => widget.summary.id;
  bool get _owned => widget.summary.ownerId == _owner.owner.id;

  @override
  void initState() {
    super.initState();
    _observedDetailAccess = _controller.detailAccessVersion(_id);
    _controller.addListener(_accessChanged);
    if (getIt.isRegistered<LibraryService>()) {
      _library = getIt<LibraryService>().watchEntriesFromDb().listen((entries) {
        if (!mounted || !_controller.live(_owner)) return;
        setState(
          () => _tracked = {
            for (final entry in entries) ?int.tryParse(entry.series.id): entry,
          },
        );
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_accessChanged);
    unawaited(_library?.cancel());
    _search.dispose();
    super.dispose();
  }

  void _accessChanged() {
    final next = _controller.authorization;
    final nextDetail = _controller.detailAccessVersion(_id);
    final grantChanged = next != _observedAccess;
    if (!grantChanged && nextDetail == _observedDetailAccess) return;
    _observedAccess = next;
    _observedDetailAccess = nextDetail;
    _selecting = false;
    _selected.clear();
    _showSpoilers = false;
    _search.close();
    if (grantChanged) {
      _readingAccess = null;
      _readError = null;
      _statusError = null;
      if (_controller.live(_owner) && _controller.canRead) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_refresh());
        });
      }
    }
  }

  Future<void> _refresh() async {
    final access = _controller.authorization;
    if (access == null ||
        access.lease != _owner ||
        !_controller.canRead ||
        _readingAccess == access) {
      return;
    }
    bool current() => mounted && _controller.liveAccess(access);
    setState(() {
      _readingAccess = access;
      _readError = null;
      _statusError = null;
    });
    try {
      final detail = await _controller.readDetail(access, _id, owned: _owned);
      if (detail != null && current()) {
        try {
          await _controller.refreshStatus(access, _id);
        } catch (error) {
          if (current()) _statusError = _error(error);
        }
      }
    } catch (error) {
      if (current()) _readError = _error(error);
    } finally {
      if (current()) setState(() => _readingAccess = null);
    }
  }

  Future<void> _change(
    StackAccess access,
    StackSummary stack,
    StackViewer viewer,
    StackAction action,
  ) async {
    final result = await _controller.changeRelationship(
      access,
      stack,
      viewer,
      action,
      confirmCoupledRemoval: () async {
        if (!mounted) return false;
        return _confirm(
          context,
          _controller,
          access,
          'stack_unsave_and_unfollow',
          _t('stack_unsave_confirm').replaceAll('{title}', stack.title),
          available: () => _controller.detail(_id) != null,
        );
      },
    );
    if (!mounted || !_controller.liveAccess(access)) return;
    if (result == StackWriteResult.rejected ||
        result == StackWriteResult.uncertain) {
      AppSnackBar.show(
        context,
        _t(
          _controller.writeError(_id) ??
              (result == StackWriteResult.uncertain
                  ? 'stack_outcome_uncertain'
                  : 'stack_refresh_required'),
        ),
        isError: true,
      );
    }
  }

  Future<void> _remove(
    StackAccess access,
    StackDetail detail,
    Set<int> chosen,
  ) async {
    final version = _controller.detailAccessVersion(_id);
    bool available() => _controller.detailAccessVersion(_id) == version;
    final draft = StackDraft.fromDetail(detail);
    draft.entries.removeWhere((entry) => chosen.contains(entry.id));
    if (draft.validationError != null) {
      AppSnackBar.show(context, _t(draft.validationError!), isError: true);
      return;
    }
    if (!await _confirm(
      context,
      _controller,
      access,
      'stack_remove',
      _count(
        'stack_remove_confirm',
        chosen.length,
      ).replaceAll('{title}', detail.summary.title),
      available: available,
    )) {
      return;
    }
    if (!mounted || !available() || !_controller.liveAccess(access)) return;
    try {
      final saved = await _controller.update(access, draft);
      if (saved != null && mounted) _endSelection();
    } catch (error) {
      if (mounted && _controller.liveAccess(access)) {
        AppSnackBar.show(context, _error(error), isError: true);
      }
    }
  }

  void _endSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  Future<void> _edit(
    StackAccess access,
    StackDetail detail, {
    bool add = false,
  }) async {
    if (!_controller.liveAccess(access)) return;
    final deleted = await _sheet<bool>(
      context,
      _StackEditor(_controller, access, base: detail, startWithAdd: add),
    );
    if (deleted == true &&
        mounted &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _controller,
      _search,
      _search.text,
      SettingsManager(),
      LocalizationService(),
    ]),
    builder: (context, _) {
      final live = _controller.live(_owner);
      final access = live ? _controller.authorization : null;
      final detail = live ? _controller.detail(_id) : null;
      final stack = detail?.summary ?? widget.summary;
      final unavailable = _controller.isDetailUnavailable(_id);
      final deleted = _controller.wasDeleted(_id);
      final showSummary =
          live &&
          _controller.canRead &&
          !unavailable &&
          !deleted &&
          (detail != null || _controller.liveAccess(widget.access));
      final viewer = live ? _controller.viewer(_id) : null;
      final busy = _controller.busy(_id);
      final canEdit =
          access != null &&
          _owned &&
          _controller.canWrite &&
          detail?.revision != null &&
          !_reading &&
          !busy &&
          !_controller.isDetailStale(_id);
      final canShow =
          _showRating(stack.rating.name) && (!stack.spoiler || _showSpoilers);
      final query = _search.text.text.trim().toLowerCase();
      final entries = !canShow
          ? <StackEntry>[]
          : detail?.entries
                    .where((entry) {
                      if (query.isEmpty) return true;
                      final series = entry.series;
                      return series != null &&
                          _showRating(series.contentRating) &&
                          [
                            series.title,
                            series.nativeTitle,
                            series.romanizedTitle,
                          ].any((title) => title.toLowerCase().contains(query));
                    })
                    .toList(growable: false) ??
                [];
      final selectable = {
        for (final entry in entries)
          if (entry.available &&
              entry.series != null &&
              _showRating(entry.series!.contentRating))
            entry.id,
      };
      final selected = _selected.intersection(selectable);
      return PopScope(
        canPop: !_search.expanded,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _search.expanded) {
            _search.close();
            _selected.clear();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: live && _search.expanded
                ? CollectionSearchField(
                    search: _search,
                    label: _t('stack_search_detail'),
                    onChanged: (_) => _selected.clear(),
                  )
                : Text(showSummary ? stack.title : _t('collection_stacks')),
            actions: [
              if (live && !_search.expanded && detail != null)
                IconButton(
                  tooltip: _t('stack_search_detail'),
                  onPressed: _search.open,
                  icon: const Icon(Icons.search),
                ),
              if (canEdit && !_search.expanded)
                IconButton(
                  tooltip: _t('stack_edit'),
                  color: context.colors.accentForeground,
                  onPressed: () => _edit(access, detail!),
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          body: !live
              ? _StackNotice(_t('stack_session_changed'))
              : deleted
              ? _StackNotice(_t('stack_unavailable'))
              : !_controller.canRead
              ? _StackPermission(_controller, _owner)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 10,
                            children: [
                              if (_reading || busy)
                                const LinearProgressIndicator(),
                              if (unavailable)
                                _StackNotice(
                                  _t('stack_unavailable'),
                                  retry: _refresh,
                                )
                              else if (_readError case final error?)
                                _StackNotice(error, retry: _refresh),
                              if (_statusError case final error?)
                                _StackNotice(error, retry: _refresh),
                              if (_controller.isDetailStale(_id) &&
                                  detail != null)
                                Text(_t('stack_stale')),
                              if (showSummary) _metadata(stack, viewer, detail),
                              if (!_controller.canWrite)
                                _StackPermission(
                                  _controller,
                                  _owner,
                                  write: true,
                                ),
                              if (!_owned &&
                                  viewer != null &&
                                  detail != null &&
                                  access != null)
                                _relationships(access, stack, viewer, busy),
                              if (canShow)
                                if (detail?.description case final text?)
                                  if (text.isNotEmpty)
                                    LibraryNotePreview(data: text),
                              if (showSummary &&
                                  stack.spoiler &&
                                  !_showSpoilers &&
                                  _showRating(stack.rating.name))
                                OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _showSpoilers = true),
                                  child: Text(_t('stack_reveal_spoilers')),
                                ),
                              if (canEdit)
                                _ownerActions(
                                  access,
                                  detail!,
                                  selectable,
                                  selected,
                                ),
                              if (detail != null && entries.isEmpty)
                                Text(
                                  _t(
                                    !_showRating(stack.rating.name)
                                        ? 'stack_series_hidden'
                                        : !canShow
                                        ? 'stack_spoilers'
                                        : detail.entries.isEmpty
                                        ? 'stack_empty_detail'
                                        : 'no_results',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (entries.isNotEmpty)
                        _grid(
                          access!,
                          entries,
                          detail!.entries,
                          selected,
                          selectable,
                          canEdit,
                        ),
                    ],
                  ),
                ),
        ),
      );
    },
  );

  Widget _metadata(
    StackSummary stack,
    StackViewer? viewer,
    StackDetail? detail,
  ) {
    final matching = [
      for (final entry in detail?.entries ?? const <StackEntry>[])
        ?_tracked[entry.id],
    ];
    final counts = <String, int>{};
    if (viewer?.libraryCount == matching.length) {
      for (final entry in matching) {
        counts.update(entry.state, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(_t('stack_${stack.visibility.name}')),
        if (stack.ownerName.isNotEmpty) Text(stack.ownerName),
        Text(_count('stack_series_count', stack.entryCount)),
        Text(_count('stack_save_count', viewer?.saveCount ?? stack.saveCount)),
        Text(_count('stack_vote_count', viewer?.voteCount ?? stack.voteCount)),
        if (viewer?.libraryCount case final count?)
          Text(_count('stack_in_library', count)),
        for (final status in counts.entries)
          Chip(
            backgroundColor: AppConstants.getColorForState(status.key),
            label: Text(
              '${_t(status.key)} ${status.value}',
              style: TextStyle(
                color: AppConstants.getOnColorForState(status.key),
              ),
            ),
          ),
      ],
    );
  }

  Widget _relationships(
    StackAccess access,
    StackSummary stack,
    StackViewer viewer,
    bool busy,
  ) {
    final uncertain = _controller.uncertain(_id);
    final enabled =
        _controller.canWrite &&
        !busy &&
        !_reading &&
        _statusError == null &&
        !_controller.isDetailStale(_id) &&
        !uncertain;
    Widget button(StackAction action, String label) => OutlinedButton(
      onPressed: enabled ? () => _change(access, stack, viewer, action) : null,
      child: Text(_t(label)),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        button(
          viewer.saved ? StackAction.unsave : StackAction.save,
          viewer.followed
              ? 'stack_unsave_and_unfollow'
              : viewer.saved
              ? 'stack_unsave'
              : 'save',
        ),
        button(
          viewer.followed ? StackAction.unfollow : StackAction.follow,
          viewer.followed
              ? 'stack_unfollow'
              : viewer.saved
              ? 'stack_follow'
              : 'stack_follow_and_save',
        ),
        button(
          viewer.voted ? StackAction.unvote : StackAction.vote,
          viewer.voted ? 'stack_unvote' : 'stack_vote',
        ),
        if (uncertain)
          _StackNotice(_t('stack_outcome_uncertain'), retry: _refresh),
      ],
    );
  }

  Widget _ownerActions(
    StackAccess access,
    StackDetail detail,
    Set<int> selectable,
    Set<int> selected,
  ) => Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (!_selecting) ...[
        FilledButton.tonalIcon(
          onPressed: () => _edit(access, detail, add: true),
          icon: const Icon(Icons.add),
          label: Text(_t('stack_add_series')),
        ),
        if (selectable.isNotEmpty)
          OutlinedButton(
            onPressed: () => setState(() => _selecting = true),
            child: Text(_t('stack_select')),
          ),
      ] else ...[
        Text(_count('stack_selected', selected.length)),
        TextButton(
          onPressed: selectable.isEmpty
              ? null
              : () => setState(() {
                  _selected
                    ..clear()
                    ..addAll(selectable);
                }),
          child: Text(_t('stack_select_all')),
        ),
        TextButton(
          onPressed: selected.isEmpty ? null : () => setState(_selected.clear),
          child: Text(_t('stack_clear')),
        ),
        TextButton(onPressed: _endSelection, child: Text(_t('cancel'))),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: selected.isEmpty
              ? null
              : () => _remove(access, detail, selected),
          child: Text(_t('stack_remove')),
        ),
      ],
    ],
  );

  Widget _grid(
    StackAccess access,
    List<StackEntry> entries,
    List<StackEntry> allEntries,
    Set<int> selected,
    Set<int> selectable,
    bool canEdit,
  ) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.crossAxisExtent - 24;
      final columns = (width / 150).floor().clamp(1, 7);
      final cell = (width - (columns - 1) * 12) / columns;
      final text = MediaQuery.textScalerOf(context);
      return SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid.builder(
          itemCount: entries.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: cell * 1.35 + text.scale(62) + 20,
          ),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final series = entry.series;
            final visible = series != null && _showRating(series.contentRating);
            final rank = allEntries.indexOf(entry) + 1;
            return _entryCard(
              access,
              entry,
              visible,
              cell,
              rank,
              selected: selected.contains(entry.id),
              selectable: canEdit && selectable.contains(entry.id),
            );
          },
        ),
      );
    },
  );

  Widget _entryCard(
    StackAccess access,
    StackEntry entry,
    bool visible,
    double width,
    int rank, {
    required bool selected,
    required bool selectable,
  }) {
    final series = entry.series;
    final tracked = visible ? _tracked[entry.id] : null;
    void openSeries() {
      if (!_controller.liveAccess(access) ||
          _controller.detail(_id) == null ||
          series == null) {
        return;
      }
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: series)),
      );
    }

    return Semantics(
      selected: _selecting ? selected : null,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _selecting
              ? !selectable
                    ? null
                    : () => setState(() {
                        if (!_selected.add(entry.id)) {
                          _selected.remove(entry.id);
                        }
                      })
              : visible
              ? openSeries
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _cover(
                    context,
                    visible ? series?.coverUrl : null,
                    width,
                    width * 1.35,
                    rating: series?.contentRating ?? '',
                  ),
                  PositionedDirectional(
                    bottom: 4,
                    start: 4,
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('#$rank'),
                    ),
                  ),
                  if (tracked != null && !_selecting)
                    EntryProgressOverlay(
                      series: series!,
                      entry: tracked,
                      cardWidth: width,
                      progressOverride: null,
                      settings: SettingsManager(),
                      l10n: LocalizationService(),
                    ),
                  if (_selecting && selectable)
                    PositionedDirectional(
                      top: 6,
                      end: 6,
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: selected ? context.colors.accent : Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 6, color: Colors.black),
                        ],
                      ),
                    ),
                ],
              ),
              if (tracked != null)
                SizedBox(
                  height: 3,
                  width: double.infinity,
                  child: ColoredBox(
                    color: AppConstants.getColorForState(tracked.state),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visible
                            ? _title(series!)
                            : _t(
                                series == null
                                    ? 'stack_series_unavailable'
                                    : 'stack_series_hidden',
                              ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (visible && entry.note?.isNotEmpty == true)
                        Flexible(
                          child: TextButton(
                            onPressed: _selecting
                                ? null
                                : () => _showNote(access, entry.id),
                            child: Text(
                              _t('stack_entry_note'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNote(StackAccess access, int seriesId) async {
    if (!_controller.liveAccess(access) || _controller.detail(_id) == null) {
      return;
    }
    final detailAccess = _controller.detailAccessVersion(_id);
    await showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final live = _controller.liveAccess(access) && _controller.canRead;
          final detail =
              live && _controller.detailAccessVersion(_id) == detailAccess
              ? _controller.detail(_id)
              : null;
          final note = detail?.entries
              .where((entry) => entry.id == seriesId)
              .firstOrNull
              ?.note;
          return AlertDialog(
            scrollable: true,
            title: Text(_t('stack_entry_note')),
            content: note != null
                ? LibraryNotePreview(data: note)
                : Text(
                    _t(
                      live
                          ? 'stack_unavailable'
                          : _controller.live(_owner)
                          ? 'stack_authorization_changed'
                          : 'stack_session_changed',
                    ),
                  ),
          );
        },
      ),
    );
  }
}
