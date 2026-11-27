part of 'library_collections_panel.dart';

TextButtonThemeData _sheetButtonTheme(BuildContext context) =>
    TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: context.colors.accentForeground,
      ),
    );

ButtonStyle _destructiveStyle(BuildContext context) => TextButton.styleFrom(
  foregroundColor: MbPalette.ensureContrast(
    context.colors.error,
    context.colors.surface,
    minimum: 4.5,
  ),
);

Future<void> _editList(
  BuildContext context,
  _Catalog catalog, {
  AccountLibraryList? list,
}) async {
  if (!catalog.canWrite) return;
  final result = await showModalBottomSheet<CollectionWriteOutcome>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _ListEditor(catalog: catalog, list: list),
  );
  if (context.mounted &&
      catalog.live &&
      result != null &&
      result != CollectionWriteOutcome.saved) {
    _writeFeedback(context, result);
  }
}

Future<void> _addTitles(
  BuildContext context,
  _Catalog catalog,
  LibraryCollection collection,
) async {
  if (!catalog.canWrite || !collection.hasCurrentMembers) return;
  final result = await showModalBottomSheet<CollectionMembershipResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _AddTitles(catalog: catalog, collection: collection),
  );
  if (context.mounted && catalog.live && result != null) {
    _membershipFeedback(context, result, add: true);
  }
}

void _writeFeedback(BuildContext context, CollectionWriteOutcome outcome) {
  final key = switch (outcome) {
    CollectionWriteOutcome.uncertain => 'collection_write_uncertain',
    CollectionWriteOutcome.refreshPending => 'collection_write_refresh_pending',
    _ => 'collection_write_rejected',
  };
  AppSnackBar.show(context, _t(key), isError: true);
}

void _membershipFeedback(
  BuildContext context,
  CollectionMembershipResult result, {
  required bool add,
}) {
  if (result.outcome == CollectionWriteOutcome.saved) {
    AppSnackBar.show(
      context,
      _t(
        add ? 'collection_titles_added' : 'collection_titles_removed',
      ).replaceAll('{titles}', _count(result.confirmed)),
    );
    return;
  }
  final key = switch (result.outcome) {
    CollectionWriteOutcome.uncertain => 'collection_partial_uncertain',
    CollectionWriteOutcome.refreshPending =>
      'collection_partial_refresh_pending',
    _ => 'collection_partial_rejected',
  };
  AppSnackBar.show(
    context,
    _t(key)
        .replaceAll('{confirmed}', '${result.confirmed}')
        .replaceAll('{total}', '${result.requested}'),
    isError: true,
  );
}

Future<bool> _confirmMembership(
  BuildContext context,
  _Catalog catalog,
  AccountLibraryList list,
  int count, {
  required bool add,
}) => _confirmCollectionAction(
  context,
  catalog,
  action: add ? 'collection_add_titles' : 'collection_remove_from_list',
  message: _t(
    add ? 'collection_confirm_add' : 'collection_confirm_remove',
  ).replaceAll('{titles}', _count(count)).replaceAll('{list}', list.name),
  destructive: !add,
);

Future<bool> _confirmCollectionAction(
  BuildContext context,
  _Catalog catalog, {
  required String action,
  required String message,
  required bool destructive,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: catalog,
        builder: (context, _) => AlertDialog(
          scrollable: true,
          title: Text(_t(action)),
          content: Text(
            catalog.live ? message : _t('collection_session_changed'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('cancel')),
            ),
            TextButton(
              style: destructive
                  ? _destructiveStyle(context)
                  : _sheetButtonTheme(context).style,
              onPressed: catalog.canWrite
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text(_t(action)),
            ),
          ],
        ),
      ),
    ) ??
    false;

class _ListEditor extends StatefulWidget {
  const _ListEditor({required this.catalog, this.list});

  final _Catalog catalog;
  final AccountLibraryList? list;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  final _form = GlobalKey<FormState>();
  late var _original = widget.list;
  late final _name = TextEditingController(text: _original?.name);
  late bool _private = _original?.isPrivate ?? false;
  bool _submitting = false;
  String? _error;
  _Catalog get _catalog => widget.catalog;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit({bool delete = false}) async {
    if (_submitting || !_catalog.canWrite) return;
    if (_error == 'collection_metadata_conflict') return;
    final list = _original;
    final confirmed = list == null ? null : _catalog.find(list.id)?.list;
    if (list != null && confirmed == null) return;
    if (delete) {
      if (!await _confirmCollectionAction(
        context,
        _catalog,
        action: 'collection_delete_list',
        message: _t(
          'collection_confirm_delete',
        ).replaceAll('{list}', confirmed!.name),
        destructive: true,
      )) {
        return;
      }
      if (!mounted ||
          _submitting ||
          !_catalog.canWrite ||
          _catalog.find(confirmed.id) == null) {
        return;
      }
    } else if (!_form.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = delete
          ? await _catalog.library.deleteCollection(_catalog.lease, confirmed!)
          : await _catalog.library.saveCollection(
              _catalog.lease,
              original: list,
              name: _name.text,
              isPrivate: _private,
            );
      if (mounted && _catalog.live) Navigator.pop(context, result);
    } on ApiException catch (error) {
      if (mounted && _catalog.live) {
        setState(
          () => _error = switch (error.code) {
            'DUPLICATE_LIST_NAME' => 'collection_duplicate_name',
            'COLLECTION_METADATA_CONFLICT' => 'collection_metadata_conflict',
            _ => 'collection_write_rejected',
          },
        );
      }
    } catch (_) {
      if (mounted && _catalog.live) {
        setState(() => _error = 'collection_write_rejected');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reloadMetadata() async {
    await _catalog.refresh();
    if (!mounted || !_catalog.canWrite) return;
    final latest = _catalog.find(_original!.id)?.list;
    if (latest == null) return;
    setState(() {
      _original = latest;
      _name.text = latest.name;
      _private = latest.isPrivate;
      _error = null;
    });
  }

  String? _validate(String? raw) {
    final normalized = LibraryCollections.normalizeListName(raw ?? '');
    final original = _original;
    if (original != null &&
        normalized == LibraryCollections.normalizeListName(original.name)) {
      return null;
    }
    if (!LibraryCollections.validListName(normalized)) {
      return _t('collection_invalid_name');
    }
    final key = LibraryCollections.listNameKey(normalized);
    if (_catalog.collections!.any(
      (item) =>
          item.list.id != widget.list?.id &&
          LibraryCollections.listNameKey(item.list.name) == key,
    )) {
      return _t('collection_duplicate_name');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_catalog, LocalizationService()]),
    builder: (context, _) {
      final list = widget.list == null
          ? null
          : _catalog.find(widget.list!.id)?.list;
      final valid = _catalog.live && (widget.list == null || list != null);
      final conflict = _error == 'collection_metadata_conflict';
      final editable = valid && !_submitting && _catalog.canWrite && !conflict;
      return PopScope(
        canPop: !_submitting || !_catalog.live,
        child: TextButtonTheme(
          data: _sheetButtonTheme(context),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: !valid
                  ? _CollectionMessage(
                      _t(
                        _catalog.live
                            ? 'collection_unavailable'
                            : 'collection_session_changed',
                      ),
                      onRetry: () => Navigator.pop(context),
                      buttonLabel: 'close',
                    )
                  : Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _t(
                              list == null
                                  ? 'collection_create_list'
                                  : 'collection_edit_list',
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _name,
                            enabled: editable,
                            validator: _validate,
                            decoration: InputDecoration(
                              labelText: _t('collection_name'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _t(
                                _private
                                    ? 'collection_private'
                                    : 'collection_public',
                              ),
                            ),
                            subtitle: Text(
                              _t(
                                _private
                                    ? 'collection_private_help'
                                    : 'collection_public_help',
                              ),
                            ),
                            activeThumbColor: context.colors.onAccent,
                            activeTrackColor: context.colors.accent,
                            value: _private,
                            onChanged: editable
                                ? (value) => setState(() => _private = value)
                                : null,
                          ),
                          if (list != null) ...[
                            Text(_count(list.seriesCount!)),
                            if (list.createdAt case final created?)
                              Text(
                                _t('collection_created').replaceAll(
                                  '{date}',
                                  MaterialLocalizations.of(
                                    context,
                                  ).formatMediumDate(created.toLocal()),
                                ),
                              ),
                          ],
                          if (_error != null)
                            _CollectionMessage(
                              _t(_error!),
                              onRetry: conflict && !_catalog.busy
                                  ? _reloadMetadata
                                  : null,
                              buttonLabel: 'collection_reload_metadata',
                            ),
                          if (_submitting) const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _submitting
                                    ? null
                                    : () => Navigator.pop(context),
                                child: Text(_t('cancel')),
                              ),
                              FilledButton(
                                onPressed: editable ? _submit : null,
                                child: Text(
                                  _t(
                                    list == null ? 'collection_create' : 'save',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (list != null) ...[
                            const Divider(),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                style: _destructiveStyle(context),
                                onPressed: editable
                                    ? () => _submit(delete: true)
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                                label: Text(_t('collection_delete_list')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
      );
    },
  );
}

class _AddTitles extends StatefulWidget {
  const _AddTitles({required this.catalog, required this.collection});

  final _Catalog catalog;
  final LibraryCollection collection;

  @override
  State<_AddTitles> createState() => _AddTitlesState();
}

class _AddTitlesState extends State<_AddTitles> {
  _Catalog get _catalog => widget.catalog;
  late final Stream<List<LibraryEntry>> _entries;
  final _selected = <String>{};
  final _search = TextEditingController();
  bool _submitting = false;
  List<LibraryEntry> _eligible = const [];

  @override
  void initState() {
    super.initState();
    _entries = _catalog.library.watchEntriesFromDb();
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
    if (!_catalog.live) _search.clear();
    if (!_catalog.canWrite ||
        _catalog.find(widget.collection.list.id)?.hasCurrentMembers != true) {
      _clearSelection();
    }
  }

  void _clearSelection() {
    if (_selected.isNotEmpty) setState(_selected.clear);
  }

  void _pruneSelection() {
    if (_selected.isEmpty) return;
    final visible = _eligible
        .where(_contentVisible)
        .map((entry) => entry.series.id)
        .toSet();
    if (!visible.containsAll(_selected)) {
      setState(() => _selected.retainAll(visible));
    }
  }

  Future<void> _submit(Set<String> ids) async {
    final list = widget.collection.list;
    final collection = _catalog.find(list.id);
    if (_submitting ||
        !_catalog.canWrite ||
        ids.isEmpty ||
        collection?.hasCurrentMembers != true) {
      return;
    }
    if (!await _confirmMembership(
      context,
      _catalog,
      list,
      ids.length,
      add: true,
    )) {
      return;
    }
    if (!mounted ||
        !_catalog.canWrite ||
        !identical(collection, _catalog.find(list.id)) ||
        !ids.every(_selected.contains) ||
        !_eligible
            .where(_contentVisible)
            .map((entry) => entry.series.id)
            .toSet()
            .containsAll(ids)) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await _catalog.library.changeCollectionMembership(
        _catalog.lease,
        listId: list.id,
        seriesIds: ids,
        add: true,
      );
      if (mounted && _catalog.live) Navigator.pop(context, result);
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
    ]),
    builder: (context, _) {
      final current = _catalog.find(widget.collection.list.id);
      final members = current?.hasCurrentMembers == true
          ? current!.members
          : null;
      return PopScope(
        canPop: !_submitting || !_catalog.live,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: FractionallySizedBox(
              heightFactor: .9,
              child: !_catalog.live || members == null
                  ? _CollectionMessage(
                      _t(
                        _catalog.live
                            ? 'collection_list_incomplete'
                            : 'collection_session_changed',
                      ),
                      onRetry: () => Navigator.pop(context),
                      buttonLabel: 'close',
                    )
                  : StreamBuilder<List<LibraryEntry>>(
                      stream: _entries,
                      builder: (context, snapshot) =>
                          _buildPicker(context, snapshot, members),
                    ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildPicker(
    BuildContext context,
    AsyncSnapshot<List<LibraryEntry>> snapshot,
    List<LibraryEntry> members,
  ) {
    final memberIds = members.map((entry) => entry.series.id).toSet();
    final eligible = [
      for (final entry in snapshot.data ?? const <LibraryEntry>[])
        if (!memberIds.contains(entry.series.id) && _contentVisible(entry))
          entry,
    ];
    _eligible = eligible
        .where((entry) => _matches(entry, _search.text.trim().toLowerCase()))
        .toList();
    final selection = _eligible
        .map((entry) => entry.series.id)
        .toSet()
        .intersection(_selected);
    final enabled = _catalog.canWrite && !_submitting;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('collection_add_titles'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _CollectionSearch(
                  label: _t('collection_search_library'),
                  controller: _search,
                  onChanged: (_) => setState(_selected.clear),
                ),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _t(
                          'collection_selected',
                        ).replaceAll('{count}', '${selection.length}'),
                      ),
                    ),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: Text(_t('cancel')),
                    ),
                    FilledButton(
                      onPressed: !enabled || selection.isEmpty
                          ? null
                          : () => _submit(selection),
                      child: Text(_t('collection_add_titles')),
                    ),
                  ],
                ),
                if (_submitting) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        if (snapshot.hasError ||
            (!snapshot.hasData &&
                snapshot.connectionState == ConnectionState.done))
          SliverToBoxAdapter(
            child: _CollectionMessage(_t('collection_library_unavailable')),
          )
        else if (!snapshot.hasData)
          const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_eligible.isEmpty)
          SliverToBoxAdapter(
            child: _CollectionMessage(
              _t(
                eligible.isEmpty
                    ? 'collection_no_eligible_titles'
                    : 'no_results',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: _eligible.length,
            itemBuilder: (context, index) {
              final item = _eligible[index];
              return CheckboxListTile(
                key: ValueKey(item.series.id),
                title: Text(_title(item.series)),
                value: selection.contains(item.series.id),
                activeColor: context.colors.accent,
                checkColor: context.colors.onAccent,
                onChanged: enabled
                    ? (value) => setState(() {
                        if (value == true) {
                          _selected.add(item.series.id);
                        } else {
                          _selected.remove(item.series.id);
                        }
                      })
                    : null,
              );
            },
          ),
      ],
    );
  }
}
