part of 'stack_ui.dart';

class AddToStackAction extends StatelessWidget {
  const AddToStackAction({super.key, required this.series});

  final Series series;

  @override
  Widget build(BuildContext context) {
    if (!getIt.isRegistered<StackController>() ||
        series.state != 'active' ||
        int.tryParse(series.id) == null) {
      return const SizedBox.shrink();
    }
    final controller = getIt<StackController>();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final owner = controller.lease;
        if (owner == null) return const SizedBox.shrink();
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
            child: TextButton.icon(
              icon: const Icon(Icons.playlist_add),
              label: Text(_t('stack_add_to')),
              onPressed: () async {
                final added = await _sheet<StackAccess>(
                  context,
                  _StackPicker(controller, owner, series),
                );
                if (added != null &&
                    context.mounted &&
                    controller.liveAccess(added)) {
                  AppSnackBar.show(context, _t('stack_series_added'));
                }
              },
            ),
          ),
        );
      },
    );
  }
}

class _StackPicker extends StatefulWidget {
  const _StackPicker(this.controller, this.owner, this.series);

  final StackController controller;
  final LibraryCacheLease owner;
  final Series series;

  @override
  State<_StackPicker> createState() => _StackPickerState();
}

class _StackPickerState extends State<_StackPicker>
    with EditorDismissal<_StackPicker> {
  List<OwnedSeriesStack>? _stacks;
  String? _failure;
  bool _loading = false;
  bool _saving = false;
  bool _uncertain = false;
  StackAccess? _access;
  StackController get _controller => widget.controller;
  LibraryCacheLease get _owner => widget.owner;
  bool get _live => _controller.live(_owner);
  bool _current(StackAccess access) =>
      mounted && _controller.liveAccess(access);
  int get _seriesId => int.parse(widget.series.id);

  @override
  bool get exitLocked => _saving && _live;
  @override
  bool get hasPendingEdits => false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_permissionsChanged);
    _permissionsChanged();
  }

  void _permissionsChanged() {
    final access = _live ? _controller.authorization : null;
    if (access == _access) return;
    _access = access;
    _stacks = null;
    _failure = null;
    _loading = false;
    _saving = false;
    _uncertain = false;
    if (access != null && _controller.canRead) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current(access)) unawaited(_load());
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_permissionsChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final access = _access;
    if (access == null ||
        !_current(access) ||
        _loading ||
        !_controller.canRead) {
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final stacks = await _controller.service.forSeries(access, _seriesId);
      if (_current(access)) {
        setState(() {
          _stacks = stacks;
          _uncertain = false;
        });
      }
    } catch (error) {
      if (_current(access)) setState(() => _failure = _error(error));
    } finally {
      if (_current(access)) setState(() => _loading = false);
    }
  }

  Future<void> _add(StackAccess access, OwnedSeriesStack stack) async {
    if (!_current(access) ||
        !_controller.canWrite ||
        _saving ||
        _loading ||
        _uncertain) {
      return;
    }
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final base = await _controller.readDetail(access, stack.id, owned: true);
      if (!_current(access) || base == null) return;
      final draft = StackDraft.fromDetail(base);
      if (!draft.entries.any((entry) => entry.id == _seriesId)) {
        draft.entries.add(StackEntry(_seriesId, series: widget.series));
        final saved = await _controller.update(access, draft);
        if (saved == null) return;
      }
      if (mounted &&
          _controller.liveAccess(access) &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, access);
      }
    } catch (error) {
      if (!_current(access)) return;
      setState(() {
        _failure = _error(error);
        _uncertain =
            error is StackFailure && (error.uncertain || error.status == 409);
      });
    } finally {
      if (_current(access)) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => guardEditorDismissal(
      _editorSheet(
        context,
        compact: true,
        canDrag: () => !exitLocked,
        dismiss: requestEditorDismissal,
        body: (scroll) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            controller: scroll,
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('stack_add_to'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!_live)
                  _StackNotice(_t('stack_session_changed'))
                else if (!_controller.canRead)
                  _StackPermission(_controller, _owner)
                else ...[
                  if (!_controller.canWrite)
                    _StackPermission(_controller, _owner, write: true),
                  if (_loading || _saving) const LinearProgressIndicator(),
                  if (_failure case final failure?)
                    _StackNotice(failure, retry: _saving ? null : _load),
                  if (!_loading && _stacks?.isEmpty == true)
                    _StackNotice(_t('stack_no_eligible')),
                  for (final stack in _stacks ?? const <OwnedSeriesStack>[])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(stack.title),
                      subtitle: stack.contains
                          ? Text(_t('stack_already_added'))
                          : null,
                      trailing: Icon(stack.contains ? Icons.check : Icons.add),
                      enabled:
                          stack.canAdd &&
                          !stack.contains &&
                          !_loading &&
                          !_saving &&
                          !_uncertain &&
                          _controller.canWrite,
                      onTap: _addAction(stack),
                    ),
                ],
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: exitLocked ? null : requestEditorDismissal,
                    child: Text(_t('close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  VoidCallback? _addAction(OwnedSeriesStack stack) {
    final access = _access;
    return access == null ? null : () => _add(access, stack);
  }
}

class _StackEditor extends StatefulWidget {
  const _StackEditor(
    this.controller,
    this.access, {
    this.base,
    this.startWithAdd = false,
  });

  final StackController controller;
  final StackAccess access;
  final StackDetail? base;
  final bool startWithAdd;

  @override
  State<_StackEditor> createState() => _StackEditorState();
}

class _StackEditorState extends State<_StackEditor>
    with EditorDismissal<_StackEditor> {
  late final _titleField = TextEditingController(
    text: widget.base?.summary.title,
  );
  late final _description = TextEditingController(
    text: widget.base?.description,
  );
  final _query = TextEditingController();
  late final StackDraft? _draft = widget.base == null
      ? null
      : StackDraft.fromDetail(widget.base!);
  late bool _adding = widget.startWithAdd;
  Timer? _debounce;
  int _searchVersion = 0;
  bool _searching = false;
  bool _saving = false;
  bool _edited = false;
  bool _refreshRequired = false;
  String? _type;
  String? _ratingFilter;
  String? _errorText;
  String? _searchError;
  List<Series> _results = const [];
  static const _mediaTypes = [
    'manga',
    'novel',
    'manhwa',
    'manhua',
    'oel',
    'other',
  ];

  StackController get _controller => widget.controller;
  late final int? _detailAccess;
  bool get _authorized =>
      _controller.liveAccess(widget.access) && _controller.canRead;
  bool get _available =>
      widget.base == null ||
      (_controller.detailAccessVersion(widget.base!.summary.id) ==
              _detailAccess &&
          _controller.detail(widget.base!.summary.id) != null);
  bool get _live => _authorized && _available;
  String get _inactiveMessage => !_controller.live(widget.access.lease)
      ? 'stack_session_changed'
      : _authorized
      ? 'stack_unavailable'
      : 'stack_authorization_changed';
  bool get _enabled =>
      _live &&
      _controller.canWrite &&
      !_saving &&
      !_refreshRequired &&
      (widget.base == null
          ? !_controller.createUncertain
          : !_controller.isDetailStale(widget.base!.summary.id) &&
                _controller.detail(widget.base!.summary.id)?.revision ==
                    widget.base!.revision &&
                !_controller.busy(widget.base!.summary.id));

  @override
  bool get exitLocked => _saving && _live;
  @override
  bool get hasPendingEdits =>
      _live &&
      (_edited ||
          _titleField.text != (widget.base?.summary.title ?? '') ||
          _description.text != (widget.base?.description ?? ''));

  @override
  void initState() {
    super.initState();
    final id = widget.base?.summary.id;
    _detailAccess = id == null ? null : _controller.detailAccessVersion(id);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleField.dispose();
    _description.dispose();
    _query.dispose();
    super.dispose();
  }

  void _change(VoidCallback action) => setState(() {
    action();
    _edited = true;
    _errorText = null;
  });

  void _search() {
    final request = ++_searchVersion;
    _debounce?.cancel();
    final query = _query.text.trim();
    final rating = _ratingFilter;
    final type = _type;
    setState(() {
      _searching = query.isNotEmpty;
      _searchError = null;
      _results = [];
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || !_live) return;
      try {
        final results = await getIt<SeriesSearchService>().searchSeriesByName(
          query,
          type: type,
          extraParams: {
            if (rating != null) 'content_rating': [rating],
          },
        );
        if (!mounted || !_live || request != _searchVersion) return;
        setState(() {
          _results = results
              .where(
                (series) =>
                    _showRating(series.contentRating) &&
                    (rating == null || series.contentRating == rating),
              )
              .toList();
          _searching = false;
        });
      } catch (error) {
        if (!mounted || !_live || request != _searchVersion) return;
        setState(() {
          _searchError = _error(error);
          _searching = false;
        });
      }
    });
  }

  Future<void> _save() async {
    if (!_enabled) return;
    final draft = _draft;
    if (draft != null) {
      draft.title = _titleField.text;
      if (_description.text != (draft.base.description ?? '') ||
          draft.base.description != null) {
        draft.description = _description.text;
      }
      if (draft.validationError case final error?) {
        setState(() => _errorText = _t(error));
        return;
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final saved = draft == null
          ? await _controller.create(widget.access, _titleField.text)
          : await _controller.update(widget.access, draft);
      if (mounted &&
          _live &&
          saved != null &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, draft == null ? saved : false);
      }
    } catch (error) {
      if (!mounted || !_live) return;
      setState(() {
        _errorText = _error(error);
        if (error is StackFailure && (error.uncertain || error.status == 409)) {
          _refreshRequired = true;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final base = widget.base!;
    if (!_enabled ||
        !await _confirm(
          context,
          _controller,
          widget.access,
          'stack_delete',
          _t('stack_delete_confirm').replaceAll('{title}', base.summary.title),
          available: () => _available,
        )) {
      return;
    }
    if (!mounted || !_enabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      final deleted = await _controller.delete(widget.access, base);
      if (mounted &&
          _authorized &&
          deleted &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted || !_live) return;
      setState(() {
        _errorText = _error(error);
        if (error is StackFailure && (error.uncertain || error.status == 409)) {
          _refreshRequired = true;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _move(int from, int to) {
    final entries = _draft!.entries;
    if (to < 0 || to >= entries.length || !_enabled) return;
    _change(() => entries.insert(to, entries.removeAt(from)));
  }

  Future<void> _note(int index) async {
    final entry = _draft!.entries[index];
    final note = await _sheet<String>(
      context,
      _StackEntryNote(
        _controller,
        () => _live,
        () => _inactiveMessage,
        entry.note,
      ),
    );
    if (!mounted || !_enabled || note == null) return;
    _change(
      () => _draft.entries[index] = entry.withNote(note.isEmpty ? null : note),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _controller,
      SettingsManager(),
      LocalizationService(),
    ]),
    builder: (context, _) {
      final draft = _draft;
      final enabled = _enabled;
      return guardEditorDismissal(
        _editorSheet(
          context,
          compact: draft == null,
          canDrag: () => !exitLocked,
          dismiss: requestEditorDismissal,
          body: (scroll) => SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: scroll,
              physics: draft == null
                  ? const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    )
                  : const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: !_live
                  ? _StackNotice(
                      _t(_inactiveMessage),
                      retry: requestEditorDismissal,
                      label: 'close',
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Text(
                          _t(
                            draft == null ? 'stack_create_title' : 'stack_edit',
                          ),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (draft != null && _adding)
                          ..._catalogue(draft, enabled),
                        TextField(
                          controller: _titleField,
                          enabled: enabled,
                          decoration: InputDecoration(
                            labelText: _t('stack_title'),
                          ),
                        ),
                        if (draft == null) Text(_t('stack_create_help')),
                        if (draft != null) ..._fields(draft, enabled),
                        if (_errorText case final error?)
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (_saving) const LinearProgressIndicator(),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: exitLocked
                                  ? null
                                  : requestEditorDismissal,
                              child: Text(_t('cancel')),
                            ),
                            FilledButton(
                              onPressed: enabled ? _save : null,
                              child: Text(
                                _t(draft == null ? 'stack_create' : 'save'),
                              ),
                            ),
                          ],
                        ),
                        if (draft != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: context.colors.error,
                              ),
                              onPressed: enabled ? _delete : null,
                              icon: const Icon(Icons.delete_outline),
                              label: Text(_t('stack_delete')),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );

  List<Widget> _catalogue(StackDraft draft, bool enabled) => [
    TextField(
      controller: _query,
      enabled: enabled,
      textInputAction: TextInputAction.search,
      onChanged: (_) => _search(),
      decoration: InputDecoration(
        labelText: _t('stack_search_catalogue'),
        prefixIcon: const Icon(Icons.search),
      ),
    ),
    Wrap(
      spacing: 12,
      children: [
        DropdownButton<String>(
          value: _type ?? '',
          onChanged: enabled
              ? (type) {
                  _type = type?.isEmpty == true ? null : type;
                  _search();
                }
              : null,
          items: [
            DropdownMenuItem(value: '', child: Text(_t('stack_all_types'))),
            for (final type in _mediaTypes)
              DropdownMenuItem(
                value: type,
                child: Text(_t('stack_type_$type')),
              ),
          ],
        ),
        DropdownButton<String>(
          value: _ratings().contains(_ratingFilter) ? _ratingFilter : '',
          onChanged: enabled
              ? (rating) {
                  _ratingFilter = rating?.isEmpty == true ? null : rating;
                  _search();
                }
              : null,
          items: [
            DropdownMenuItem(value: '', child: Text(_t('stack_rating'))),
            for (final rating in _ratings())
              DropdownMenuItem(
                value: rating,
                child: Text(_t('stack_rating_$rating')),
              ),
          ],
        ),
      ],
    ),
    if (_searching) const LinearProgressIndicator(),
    if (_searchError case final error?) _StackNotice(error, retry: _search),
    if (!_searching &&
        _searchError == null &&
        _query.text.trim().isNotEmpty &&
        _results.isEmpty)
      Text(_t('no_results')),
    if (_results.isNotEmpty)
      SizedBox(
        height: math.min(260, MediaQuery.sizeOf(context).height * .35),
        child: ListView.builder(
          primary: false,
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final series = _results[index];
            final id = int.tryParse(series.id);
            final chosen = draft.entries.any((entry) => entry.id == id);
            return ListTile(
              dense: true,
              title: Text(
                _title(series),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(chosen ? Icons.check : Icons.add),
              onTap:
                  !enabled ||
                      chosen ||
                      id == null ||
                      draft.entries.length >= StackDraft.maxEntries
                  ? null
                  : () => _change(
                      () => draft.entries.add(
                        StackEntry(
                          id,
                          series: series,
                          available: series.state == 'active',
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    Text(_count('stack_selected', draft.entries.length)),
    if (draft.entries.isNotEmpty)
      SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: draft.entries.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final entry = draft.entries[index];
            final series = entry.series;
            final visible = series != null && _showRating(series.contentRating);
            return Stack(
              children: [
                _cover(
                  context,
                  visible ? series.coverUrl : null,
                  72,
                  108,
                  rating: series?.contentRating ?? '',
                ),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: IconButton.filledTonal(
                    tooltip: _t('stack_remove'),
                    onPressed: enabled
                        ? () => _change(() => draft.entries.removeAt(index))
                        : null,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            );
          },
        ),
      ),
  ];

  List<Widget> _fields(StackDraft draft, bool enabled) => [
    LibraryNotesEditor(
      controller: _description,
      enabled: enabled,
      decoration: InputDecoration(labelText: _t('stack_description')),
      validator: (value) => (value?.runes.length ?? 0) > 10000
          ? _t('stack_markdown_limit')
          : null,
    ),
    DropdownButtonFormField<StackVisibility>(
      initialValue: draft.visibility,
      isExpanded: true,
      decoration: InputDecoration(labelText: _t('stack_visibility')),
      onChanged: enabled
          ? (value) => _change(() => draft.visibility = value!)
          : null,
      items: [
        for (final value in StackVisibility.values)
          DropdownMenuItem(
            value: value,
            child: Text(_t('stack_${value.name}')),
          ),
      ],
    ),
    Text(_t('stack_${draft.visibility.name}_help')),
    DropdownButtonFormField<StackRating>(
      initialValue: draft.rating,
      isExpanded: true,
      decoration: InputDecoration(labelText: _t('stack_rating')),
      onChanged: enabled
          ? (value) => _change(() => draft.rating = value!)
          : null,
      items: [
        for (final value in StackRating.values)
          DropdownMenuItem(
            value: value,
            child: Text(_t('stack_rating_${value.name}')),
          ),
      ],
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_t('stack_spoilers')),
      value: draft.spoiler,
      onChanged: enabled && !draft.base.spoilerLocked
          ? (value) => _change(() => draft.spoiler = value)
          : null,
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(_t('stack_comments')),
      value: draft.comments,
      onChanged: enabled
          ? (value) => _change(() => draft.comments = value)
          : null,
    ),
    if (!_adding)
      OutlinedButton.icon(
        onPressed: enabled ? () => setState(() => _adding = true) : null,
        icon: const Icon(Icons.add),
        label: Text(_t('stack_add_series')),
      ),
    if (draft.entries.isNotEmpty)
      ReorderableListView.builder(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: draft.entries.length,
        onReorderItem: _move,
        itemBuilder: (context, index) =>
            _entryMenu(index, draft.entries[index], enabled),
      ),
  ];

  Widget _entryMenu(int index, StackEntry entry, bool enabled) => ListTile(
    key: ValueKey(entry.id),
    contentPadding: EdgeInsets.zero,
    leading: enabled
        ? ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: _t('stack_reorder'),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text('#${index + 1}'),
              ),
            ),
          )
        : Text('#${index + 1}'),
    title: Text(
      entry.series == null
          ? _t('stack_series_unavailable')
          : !_showRating(entry.series!.contentRating)
          ? _t('stack_series_hidden')
          : _title(entry.series!),
    ),
    trailing: PopupMenuButton<String>(
      enabled: enabled,
      onSelected: (action) {
        switch (action) {
          case 'note':
            unawaited(_note(index));
          case 'up':
            _move(index, index - 1);
          case 'down':
            _move(index, index + 1);
          case 'remove':
            _change(() => _draft!.entries.removeAt(index));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'note', child: Text(_t('stack_entry_note'))),
        PopupMenuItem(
          value: 'up',
          enabled: index > 0,
          child: Text(_t('stack_move_up')),
        ),
        PopupMenuItem(
          value: 'down',
          enabled: index < _draft!.entries.length - 1,
          child: Text(_t('stack_move_down')),
        ),
        PopupMenuItem(value: 'remove', child: Text(_t('stack_remove'))),
      ],
    ),
  );
}

class _StackEntryNote extends StatefulWidget {
  const _StackEntryNote(
    this.controller,
    this.available,
    this.inactiveMessage,
    this.original,
  );

  final StackController controller;
  final bool Function() available;
  final String Function() inactiveMessage;
  final String? original;

  @override
  State<_StackEntryNote> createState() => _StackEntryNoteState();
}

class _StackEntryNoteState extends State<_StackEntryNote>
    with EditorDismissal<_StackEntryNote> {
  late final _text = TextEditingController(text: widget.original);
  final _form = GlobalKey<FormState>();
  bool get _live => widget.available() && widget.controller.canWrite;

  @override
  bool get exitLocked => false;
  @override
  bool get hasPendingEdits => _live && _text.text != (widget.original ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => guardEditorDismissal(
      _editorSheet(
        context,
        compact: true,
        canDrag: () => true,
        dismiss: requestEditorDismissal,
        body: (scroll) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            controller: scroll,
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_live)
                    LibraryNotesEditor(
                      controller: _text,
                      enabled: true,
                      decoration: InputDecoration(
                        labelText: _t('stack_entry_note'),
                      ),
                      validator: (value) => (value?.runes.length ?? 0) > 5000
                          ? _t('stack_markdown_limit')
                          : null,
                    )
                  else
                    Text(_t(widget.inactiveMessage())),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: requestEditorDismissal,
                        child: Text(_t('cancel')),
                      ),
                      FilledButton(
                        onPressed: !_live
                            ? null
                            : () {
                                if (!_form.currentState!.validate()) return;
                                FocusManager.instance.primaryFocus?.unfocus();
                                Navigator.pop(context, _text.text);
                              },
                        child: Text(_t('save')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
