import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/widgets/guarded_draggable_sheet.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart'
    show LibraryCacheLease;
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/widgets/route_dismiss_guard.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/widgets/library_notes_editor.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_dropdown.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

enum _Phase {
  loading,
  loadFailed,
  missing,
  editing,
  saving,
  conflict,
  refreshPending,
  uncertain,
  refreshed,
  sessionChanged,
}

enum _Field {
  priority('library_editor_priority', min: 10, max: 30),
  startDate('library_editor_start_date'),
  finishDate('library_editor_finish_date'),
  chapter('chapters', min: 0, max: 10000),
  volume('volumes', min: 0, max: 10000),
  rereads('library_editor_rereads', min: 0, max: 1000),
  readLink('library_editor_read_link'),
  rating('rating', min: 0, max: 100),
  note('library_editor_notes');

  const _Field(this.label, {this.min, this.max});

  final String label;
  final int? min;
  final int? max;
}

/// Presents a draft created from an authoritative read, under one Library lease.
class LibraryEntryEditorSheet extends StatefulWidget {
  const LibraryEntryEditorSheet._({
    required this.library,
    required this.auth,
    required this.lease,
    required this.series,
    required this.title,
    required this.defaultState,
    required this.edit,
    required this.mobile,
  });

  final LibraryService library;
  final ProfileAuthService auth;
  final LibraryCacheLease lease;
  final Series series;
  final String title;
  final String defaultState;
  final bool edit;
  final bool mobile;

  static Future<void> show(
    BuildContext context, {
    required LibraryService library,
    required ProfileAuthService auth,
    required LibraryCacheLease lease,
    required Series series,
    required String title,
    required String defaultState,
    required bool edit,
  }) {
    final desktop = DesktopLayout.isActive(context);
    final editor = LibraryEntryEditorSheet._(
      library: library,
      auth: auth,
      lease: lease,
      series: series,
      title: title,
      defaultState: defaultState,
      edit: edit,
      mobile: !desktop,
    );
    if (desktop) {
      return showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => Dialog(
          backgroundColor: context.colors.surface,
          child: SizedBox(width: 600, height: 720, child: editor),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: editor,
      ),
    );
  }

  @override
  State<LibraryEntryEditorSheet> createState() =>
      _LibraryEntryEditorSheetState();
}

class _LibraryEntryEditorSheetState extends State<LibraryEntryEditorSheet>
    with
        RouteDismissGuard<LibraryEntryEditorSheet>,
        EditorDismissal<LibraryEntryEditorSheet> {
  static final _firstDate = DateTime(1679);
  static final _lastDate = DateTime(2262, 12, 31);
  static const _maxLists = 30;
  static const _openExtent = .92;
  static const _dismissExtent = .48;

  final _form = GlobalKey<FormState>();
  final _dialogScroll = ScrollController();
  ScrollController? _sheetScroll;
  final _controllers = {
    for (final field in _Field.values) field: TextEditingController(),
  };

  _Phase _phase = _Phase.loading;
  LibraryEntry? _original;
  late bool _requiresEntry = widget.edit;
  late String _state;
  bool? _private;
  bool _closed = false;
  bool _reading = false;
  bool _checking = false;
  bool? _entryFound;
  String? _feedback;

  List<AccountLibraryList>? _lists;
  bool _loadingLists = false;
  Set<int>? _originalLists;
  final _selectedLists = <int>{};

  String _t(String key) => LocalizationService().translate(key);
  bool get _current => identical(widget.lease, widget.auth.libraryLease);
  bool get _live => mounted && !_closed && _current;
  bool get _editable => _phase == _Phase.editing && _live;
  bool get _listsEditable {
    final original = _originalLists;
    final lists = _lists;
    return original != null &&
        lists != null &&
        lists.map((list) => list.id).toSet().containsAll(original);
  }

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_sessionChanged);
    widget.library.collectionsRevision.addListener(_collectionOptionsChanged);
    if (_current) {
      unawaited(_load());
    } else {
      _phase = _Phase.sessionChanged;
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_sessionChanged);
    widget.library.collectionsRevision.removeListener(
      _collectionOptionsChanged,
    );
    _dialogScroll.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted || _closed || _current || _phase == _Phase.sessionChanged) {
      return;
    }
    FocusScope.of(context).unfocus();
    canPopNotifier.value = true;
    setState(() {
      _phase = _Phase.sessionChanged;
      _original = null;
      _private = null;
      _lists = null;
      _originalLists = null;
      _selectedLists.clear();
    });
    // Replace the form first so active text inputs release the controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final controller in _controllers.values) {
        controller.clear();
      }
    });
  }

  Future<LibraryEntry?> _readEntry() => widget.library
      .fetchAuthoritativeLibraryEntry(widget.series.id, lease: widget.lease);

  Future<void> _load() async {
    if (!_live || _reading) return;
    _reading = true;
    setState(() => _phase = _Phase.loading);
    try {
      final entry = await _readEntry();
      if (!_live) return;
      if (entry == null && _requiresEntry) {
        setState(() => _phase = _Phase.missing);
        return;
      }
      setState(() {
        _original = entry;
        _state = entry?.state ?? _defaultEntryState;
        _private = entry?.isPrivate;
        _originalLists = entry == null ? <int>{} : entry.listIds?.toSet();
        _selectedLists
          ..clear()
          ..addAll(_originalLists ?? const <int>{});
        _lists = null;
        for (final field in _Field.values) {
          final text = _initial(field)?.toString() ?? '';
          _controllers[field]!.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
        _feedback = null;
        _phase = _Phase.editing;
      });
      unawaited(_loadLists());
    } catch (_) {
      if (_live) setState(() => _phase = _Phase.loadFailed);
    } finally {
      _reading = false;
    }
  }

  Future<void> _loadLists() async {
    if (!_editable || _loadingLists) return;
    final revision = widget.library.collectionsRevision.value;
    setState(() => _loadingLists = true);
    try {
      final lists = await widget.library.fetchAccountLibraryLists(widget.lease);
      if (_live && revision == widget.library.collectionsRevision.value) {
        setState(() => _lists = lists);
      }
    } catch (_) {
      // The rest of the draft stays editable with membership omitted.
    } finally {
      if (_live) setState(() => _loadingLists = false);
      if (_editable && revision != widget.library.collectionsRevision.value) {
        _collectionOptionsChanged();
      }
    }
  }

  void _collectionOptionsChanged() => unawaited(_loadLists());

  Object? _initial(_Field field) => switch (field) {
    _Field.priority => _original?.priority,
    _Field.startDate => _original?.startDate,
    _Field.finishDate => _original?.finishDate,
    _Field.chapter => _original?.progressChapter,
    _Field.volume => _original?.progressVolume,
    _Field.rereads => _original?.numberOfRereads,
    _Field.readLink => _original?.readLink,
    _Field.rating => _original?.rating,
    _Field.note => _original?.note,
  };

  String _value(_Field field, String text) =>
      field == _Field.note ? text : text.trim();

  num? _number(_Field field, String text) {
    if (field == _Field.priority) {
      // iOS decimal keyboards can use a comma as the decimal separator.
      if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text)) return null;
      return num.tryParse(text.replaceAll(',', '.'));
    }
    return RegExp(r'^\d+$').hasMatch(text) ? int.tryParse(text) : null;
  }

  String? _validate(_Field field, String raw) {
    final before = _initial(field)?.toString() ?? '';
    final text = _value(field, raw);
    if (raw == before || text == before) return null;
    if (text.isEmpty) return _t('library_editor_clearing_unavailable');

    final min = field.min;
    if (min != null) {
      final max = field.max!;
      final number = _number(field, text);
      if (number != null && number.isFinite && number >= min && number <= max) {
        return null;
      }
      return _t(
        field == _Field.priority
            ? 'library_editor_number_range'
            : 'library_editor_integer_range',
      ).replaceAll('{min}', '$min').replaceAll('{max}', '$max');
    }
    if (field == _Field.readLink) {
      final uri = Uri.tryParse(text);
      if (uri == null ||
          !uri.isAbsolute ||
          RegExp(r'\s').hasMatch(text) ||
          ((uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.host.isEmpty)) {
        return _t('library_editor_invalid_link');
      }
    }
    if (field == _Field.startDate || field == _Field.finishDate) {
      final date = DateTime.tryParse('${text}T00:00:00Z');
      if (date == null ||
          date.toIso8601String().substring(0, 10) != text ||
          text.compareTo('1679-01-01') < 0 ||
          text.compareTo('2262-12-31') > 0) {
        return _t('library_editor_invalid_date');
      }
    }
    return null;
  }

  EntryField<T> _changed<T>(T? initial, T? value) =>
      value == null || value == initial
      ? const EntryField.omitted()
      : EntryField.set(value);

  EntryField<String> _textField(_Field field) {
    final initial = _initial(field) as String?;
    final raw = _controllers[field]!.text;
    if (raw == initial) return const EntryField.omitted();
    final value = _value(field, raw);
    return _changed(initial, value.isEmpty ? null : value);
  }

  EntryField<T> _numericField<T extends num>(_Field field) {
    final raw = _controllers[field]!.text.trim();
    final initial = _initial(field) as T?;
    if (raw == (initial?.toString() ?? '')) return const EntryField.omitted();
    return _changed(initial, _number(field, raw) as T?);
  }

  LibraryEntryDraft _draft() => LibraryEntryDraft(
    lease: widget.lease,
    seriesId: widget.series.id,
    state: _changed(_original?.state, _state),
    priority: _numericField<num>(_Field.priority),
    startDate: _textField(_Field.startDate),
    finishDate: _textField(_Field.finishDate),
    progressChapter: _numericField<int>(_Field.chapter),
    progressVolume: _numericField<int>(_Field.volume),
    numberOfRereads: _numericField<int>(_Field.rereads),
    readLink: _textField(_Field.readLink),
    isPrivate: _changed(_original?.isPrivate ?? false, _private),
    lists: _listsEditable && !setEquals(_originalLists, _selectedLists)
        ? EntryField.set(_selectedLists.toList())
        : const EntryField.omitted(),
    originalListIds: _original == null ? null : _originalLists,
    rating: _numericField<int>(_Field.rating),
    note: _textField(_Field.note),
  );

  Future<void> _save() async {
    if (!_editable) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      unawaited(
        Scrollable.ensureVisible(
          invalid.first.context,
          duration: AppConstants.shortAnimationDuration,
        ),
      );
      return;
    }

    final draft = _draft();
    final create = _original == null;
    try {
      if (draft.toJson().isEmpty) {
        _close();
        return;
      }
    } on ArgumentError {
      _rejected('library_editor_invalid_fields');
      return;
    }

    FocusScope.of(context).unfocus();
    canPopNotifier.value = false;
    setState(() {
      _phase = _Phase.saving;
      _feedback = null;
    });
    try {
      final result = await (create
          ? widget.library.createCompleteLibraryEntry(draft)
          : widget.library.updateCompleteLibraryEntry(draft));
      if (!_live) return;
      switch (result.outcome) {
        case LibrarySaveOutcome.saved:
          _close();
        case LibrarySaveOutcome.refreshPending:
          setState(() => _phase = _Phase.refreshPending);
        case LibrarySaveOutcome.uncertain:
          setState(() => _phase = _Phase.uncertain);
      }
    } on ApiException catch (error) {
      if (!_live) return;
      if (create && error.statusCode == 409) {
        setState(() => _phase = _Phase.conflict);
      } else if (!create && error.statusCode == 404) {
        setState(() => _phase = _Phase.missing);
      } else if ((error.statusCode >= 400 && error.statusCode < 500) ||
          error.code == 'WRITE_DECLINED') {
        _rejected('library_editor_rejected');
      } else {
        setState(() => _phase = _Phase.uncertain);
      }
    } on AuthException {
      if (_live) _rejected('library_editor_auth_retry');
    } on ArgumentError {
      if (_live) _rejected('library_editor_invalid_fields');
    } catch (_) {
      if (_live) setState(() => _phase = _Phase.uncertain);
    } finally {
      if (mounted) canPopNotifier.value = true;
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) _closed = true;
  }

  @override
  bool get exitLocked => _current && !canPopNotifier.value;

  @override
  bool get hasPendingEdits =>
      _editable &&
      (_state != (_original?.state ?? _defaultEntryState) ||
          (_private ?? false) != (_original?.isPrivate ?? false) ||
          !setEquals(_originalLists ?? const <int>{}, _selectedLists) ||
          _controllers.entries.any(
            (field) =>
                field.value.text != (_initial(field.key)?.toString() ?? ''),
          ));

  String get _defaultEntryState =>
      LibraryEntryDraft.states.contains(widget.defaultState)
      ? widget.defaultState
      : 'plan_to_read';

  void _cancel() => unawaited(requestEditorDismissal());

  void _close() {
    final route = ModalRoute.of(context);
    final navigator = route?.navigator;
    if (route == null || navigator == null || !route.isActive) return;
    _closed = true;
    if (route.isCurrent) {
      FocusScope.of(context).unfocus();
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  void _rejected(String message) {
    setState(() {
      _phase = _Phase.editing;
      _feedback = message;
    });
    final scroll = widget.mobile ? _sheetScroll : _dialogScroll;
    if (scroll != null && scroll.hasClients) {
      unawaited(
        scroll.animateTo(
          0,
          duration: AppConstants.shortAnimationDuration,
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Future<void> _checkEntry() async {
    if (!_live || _checking) return;
    setState(() {
      _checking = true;
      _feedback = null;
      _entryFound = null;
    });
    try {
      final entry = await _readEntry();
      if (!_live) return;
      setState(() {
        _entryFound = entry != null;
        // A GET can reconcile an acknowledged write, but cannot establish
        // whether an ambiguous write was applied.
        if (entry != null && _phase == _Phase.refreshPending) {
          _phase = _Phase.refreshed;
        }
      });
    } catch (_) {
      if (_live) setState(() => _feedback = 'library_editor_check_failed');
    } finally {
      if (_live) setState(() => _checking = false);
    }
  }

  Future<void> _pickDate(_Field field) async {
    if (!_editable) return;
    FocusScope.of(context).unfocus();
    final selected = DateTime.tryParse(_controllers[field]!.text);
    final initial =
        selected != null &&
            !selected.isBefore(_firstDate) &&
            !selected.isAfter(_lastDate)
        ? selected
        : null;
    final date = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: initial,
      firstDate: _firstDate,
      lastDate: _lastDate,
      helpText: _t(field.label),
      builder: (context, child) => ListenableBuilder(
        listenable: widget.auth,
        builder: (context, _) => _current
            ? child!
            : AlertDialog(
                content: Text(_t('library_editor_session_changed')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_t('close')),
                  ),
                ],
              ),
      ),
    );
    if (_editable && date != null) {
      _controllers[field]!.text = date.toIso8601String().substring(0, 10);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LocalizationService(),
    builder: (context, _) {
      final colors = context.colors;
      final saving = _phase == _Phase.saving;
      final showForm = _current && (_phase == _Phase.editing || saving);
      final invalidated = !_current || _phase == _Phase.sessionChanged;
      final isEdit = _requiresEntry || _original != null;
      final header = Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                _t(isEdit ? 'library_editor_edit' : 'add_to_library'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: colors.text),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textMuted),
            ),
          ],
        ),
      );
      final content = Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: showForm
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  if (_feedback != null)
                    _message(_feedback!, color: colors.error),
                  _fields(),
                ],
              )
            : _status(invalidated),
      );
      final footer = Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 8,
          overflowSpacing: 4,
          children: [
            TextButton(
              onPressed: saving && !invalidated ? null : _cancel,
              child: Text(
                _t(showForm || _phase == _Phase.loading ? 'cancel' : 'close'),
              ),
            ),
            if (showForm)
              FilledButton(
                onPressed: saving ? null : _save,
                child: Text(_t(saving ? 'library_editor_saving' : 'save')),
              ),
          ],
        ),
      );
      Widget frame(ScrollController scroll, [Widget? handle]) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?handle,
            Expanded(
              child: IgnorePointer(
                ignoring: saving,
                child: SingleChildScrollView(
                  controller: scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, content],
                  ),
                ),
              ),
            ),
            Divider(color: colors.border, height: 1),
            footer,
          ],
        ),
      );
      return guardEditorDismissal(
        widget.mobile
            ? GuardedDraggableSheet(
                openExtent: _openExtent,
                dismissExtent: _dismissExtent,
                handleKey: const ValueKey('library_editor_drag_handle'),
                canDrag: () => !_closed && !exitLocked,
                onDismiss: requestEditorDismissal,
                builder: (_, scroll, handle) {
                  _sheetScroll = scroll;
                  return frame(scroll, handle);
                },
              )
            : frame(_dialogScroll),
      );
    },
  );

  Widget _message(String key, {Color? color}) => Semantics(
    liveRegion: true,
    child: Text(_t(key), style: TextStyle(color: color ?? context.colors.text)),
  );

  Widget _status(bool invalidated) {
    final phase = invalidated ? _Phase.sessionChanged : _phase;
    final message = switch (phase) {
      _Phase.loading => 'library_editor_loading',
      _Phase.loadFailed => 'library_editor_load_failed',
      _Phase.missing => 'library_editor_missing',
      _Phase.conflict => 'library_editor_conflict',
      _Phase.refreshPending => 'library_editor_refresh_pending',
      _Phase.uncertain => 'library_editor_uncertain',
      _Phase.refreshed => 'library_editor_refreshed',
      _Phase.sessionChanged => 'library_editor_session_changed',
      _ => throw StateError('Expected a Library editor status'),
    };
    final canCheck =
        phase == _Phase.refreshPending || phase == _Phase.uncertain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _message(message),
        if (phase == _Phase.loading || (canCheck && _checking)) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (phase == _Phase.loadFailed)
          OutlinedButton(onPressed: _load, child: Text(_t('retry'))),
        if (phase == _Phase.conflict)
          OutlinedButton(
            onPressed: () {
              _requiresEntry = true;
              unawaited(_load());
            },
            child: Text(_t('library_editor_open_existing')),
          ),
        if (canCheck) ...[
          if (_feedback != null)
            _message(_feedback!, color: context.colors.error)
          else if (_entryFound case final found?)
            _message(
              found ? 'library_editor_found' : 'library_editor_not_found',
            ),
          OutlinedButton(
            onPressed: _checking ? null : _checkEntry,
            child: Text(_t('library_editor_check_entry')),
          ),
        ],
      ],
    );
  }

  Widget _fields() {
    final enabled = _editable;
    final colors = context.colors;
    final chapter = _input(
      _Field.chapter,
      helper: _total(widget.series.totalChapters),
    );
    final volume = _input(
      _Field.volume,
      helper: _total(widget.series.finalVolume),
    );
    return Form(
      key: _form,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pairFields =
              constraints.maxWidth >= 400 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              _labeledField(
                _t('status'),
                LibraryStatusDropdown(
                  value: _state,
                  onChanged: enabled
                      ? (value) => setState(() => _state = value)
                      : null,
                ),
              ),
              _input(_Field.priority, helper: '10–30'),
              if (pairFields)
                _pair(
                  _dateInput(_Field.startDate),
                  _dateInput(_Field.finishDate),
                )
              else ...[
                _dateInput(_Field.startDate),
                _dateInput(_Field.finishDate),
              ],
              Divider(color: colors.border, height: 1),
              if (pairFields) _pair(chapter, volume) else ...[chapter, volume],
              _input(_Field.rereads),
              Divider(color: colors.border, height: 1),
              _input(_Field.readLink, hint: 'https://'),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(_t('library_editor_private')),
                value: _private ?? false,
                onChanged: enabled
                    ? (value) => setState(() => _private = value)
                    : null,
              ),
              _listPicker(),
              Divider(color: colors.border, height: 1),
              _input(
                _Field.rating,
                hint: _t('library_editor_unset'),
                helper: _t('library_editor_rating_hint'),
              ),
              LibraryNotesEditor(
                controller: _controllers[_Field.note]!,
                decoration: _decoration(),
                validator: (value) => _validate(_Field.note, value ?? ''),
                enabled: enabled,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pair(Widget first, Widget second) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 12,
    children: [
      Expanded(child: first),
      Expanded(child: second),
    ],
  );

  String? _total(String raw) {
    final total = num.tryParse(raw);
    return total != null && total.isFinite && total > 0
        ? _t('library_editor_series_total').replaceAll('{total}', raw)
        : null;
  }

  Widget _dateInput(_Field field) => _input(
    field,
    hint: 'YYYY-MM-DD',
    suffix: IconButton(
      tooltip: _t(field.label),
      onPressed: _editable ? () => _pickDate(field) : null,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
    ),
  );

  Widget _input(_Field field, {String? hint, String? helper, Widget? suffix}) {
    final label = _t(field.label);
    return _labeledField(
      label,
      Semantics(
        label: label,
        child: TextFormField(
          key: ValueKey(field.label),
          controller: _controllers[field],
          enabled: _editable,
          keyboardType: switch (field) {
            _Field.readLink => TextInputType.url,
            _Field.startDate || _Field.finishDate => TextInputType.datetime,
            _ => TextInputType.numberWithOptions(
              decimal: field == _Field.priority,
            ),
          },
          textInputAction: TextInputAction.next,
          enableIMEPersonalizedLearning: false,
          autocorrect: false,
          style: TextStyle(color: context.colors.text),
          textAlignVertical: TextAlignVertical.center,
          decoration: _decoration().copyWith(
            hintText: hint,
            helperText: helper,
            helperMaxLines: 3,
            suffixIcon: suffix,
          ),
          validator: (value) => _validate(field, value ?? ''),
        ),
      ),
    );
  }

  Widget _labeledField(String label, Widget control) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 6,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: AppTypography.sans(
              color: MbPalette.ensureContrast(
                context.colors.textMuted,
                context.colors.surface,
                minimum: 4.5,
              ),
              fontSize: 14,
            ),
          ),
        ),
      ),
      control,
    ],
  );

  InputDecoration _decoration() {
    final colors = context.colors;
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
      gapPadding: 0,
    );
    return InputDecoration(
      border: outline,
      enabledBorder: outline,
      disabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(
          color: colors.usesCanonicalYellow
              ? colors.accentOn(colors.surfaceRaised, minimum: 3)
              : colors.accent,
        ),
      ),
      errorBorder: outline.copyWith(
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: outline.copyWith(
        borderSide: BorderSide(color: colors.error, width: 2),
      ),
      fillColor: colors.surfaceRaised,
      filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      helperStyle: TextStyle(
        color: MbPalette.ensureContrast(
          colors.textMuted,
          colors.surface,
          minimum: 4.5,
        ),
      ),
      errorMaxLines: 4,
    );
  }

  Widget _listPicker() {
    final title = _t('library_editor_lists');
    final lists = _lists;
    if (_listsEditable && lists!.isNotEmpty) {
      return ExpansionTile(
        title: Text(title),
        subtitle: Text(
          _t('library_editor_list_count')
              .replaceAll('{count}', '${_selectedLists.length}')
              .replaceAll('{max}', '$_maxLists'),
        ),
        enabled: _editable,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final list in lists)
            CheckboxListTile(
              key: ValueKey(list.id),
              title: Text(list.name),
              subtitle: list.isPrivate
                  ? Text(_t('library_editor_private_list'))
                  : null,
              value: _selectedLists.contains(list.id),
              onChanged:
                  !_editable ||
                      (!_selectedLists.contains(list.id) &&
                          _selectedLists.length >= _maxLists)
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _selectedLists.add(list.id);
                      } else {
                        _selectedLists.remove(list.id);
                      }
                    }),
            ),
        ],
      );
    }
    final message = _loadingLists
        ? 'library_editor_lists_loading'
        : lists == null
        ? 'library_editor_lists_failed'
        : _listsEditable
        ? 'library_editor_lists_empty'
        : 'library_editor_membership_unknown';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: context.colors.text)),
          _message(message, color: context.colors.textMuted),
          if (!_loadingLists && lists == null)
            TextButton(
              onPressed: _editable ? _loadLists : null,
              child: Text(_t('library_editor_retry_lists')),
            ),
        ],
      ),
    );
  }
}
