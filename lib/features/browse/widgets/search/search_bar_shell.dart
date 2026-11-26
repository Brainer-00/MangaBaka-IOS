import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/widgets/search/ghost_text_editing_controller.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/browse/widgets/search/mb_search_bar_suffix.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_bar_controller.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_filter_sheet_launcher.dart';
import 'package:mangabaka_app/features/browse/widgets/search/search_suggestions_panel.dart';
import 'package:mangabaka_app/features/series/models/autocomplete_series_result.dart';

export 'package:mangabaka_app/features/browse/widgets/search/search_bar_controller.dart'
    show SuggestionRequest;

/// The search field shared by Browse and Library.
///
/// Both screens used to carry their own copy — ~1150 lines between them,
/// differing only in where suggestions come from and a handful of flags.
/// Everything fiddly was duplicated: the inline ghost completion, arrow-key
/// navigation, the suppress-after-backspace rule, the overlay lifecycle and
/// the filter sheet. They had already drifted apart on ranking and on what
/// submitting does.
///
/// This widget is the presentation; [SearchBarController] holds the rules.
/// What stays screen-specific is passed in: [requestSuggestions] supplies the
/// results, [suggestionsEnabled] gates them behind a setting, and the
/// remaining flags control the scan button and the filter sheet's contents.
class SearchBarShell extends StatefulWidget {
  /// The field's controller. When null the shell owns (and disposes) one; when
  /// provided, the caller keeps ownership.
  final GhostTextEditingController? controller;
  final FocusNode? focusNode;

  /// Fires on every keystroke, on clear with an empty string, and when a
  /// suggestion is chosen.
  final ValueChanged<String> onChanged;

  /// Fires when the field is submitted without a suggestion being chosen.
  /// Falls back to [onChanged] when null.
  final ValueChanged<String>? onSubmitted;

  /// Fires when a suggestion is chosen — by tap, by Enter on a highlighted
  /// row, or by accepting the inline completion.
  final ValueChanged<AutocompleteSeriesResult>? onResultSelected;

  /// Fires as a suggestion is hovered, for prefetching its detail page.
  final ValueChanged<AutocompleteSeriesResult>? onResultHovered;

  /// Replaces the leading search glyph with a back button that also clears the
  /// field. Null leaves the glyph.
  final VoidCallback? onBackTap;

  /// Adds a barcode-scan button to the trailing controls.
  final VoidCallback? onScanTap;

  final SearchFilters? initialFilters;
  final ValueChanged<SearchFilters>? onFilterApplied;

  /// Adds the library-only sort options to the filter sheet.
  final bool showLibrarySorts;

  /// Whether the trailing filter button (which opens the filter sheet) is
  /// shown. Desktop layouts turn it off: their filters sit in a permanent
  /// panel beside the results instead.
  final bool showFilterButton;

  final SuggestionRequest requestSuggestions;

  /// Null means suggestions are always enabled.
  final bool Function()? suggestionsEnabled;

  /// Rebuilt alongside [LocalizationService] — pass the setting that
  /// [suggestionsEnabled] reads, so toggling it takes effect immediately.
  final Listenable? rebuildOn;

  const SearchBarShell({
    super.key,
    required this.onChanged,
    required this.requestSuggestions,
    this.controller,
    this.focusNode,
    this.onSubmitted,
    this.onResultSelected,
    this.onResultHovered,
    this.onBackTap,
    this.onScanTap,
    this.initialFilters,
    this.onFilterApplied,
    this.showLibrarySorts = false,
    this.showFilterButton = true,
    this.suggestionsEnabled,
    this.rebuildOn,
  });

  @override
  State<SearchBarShell> createState() => _SearchBarShellState();
}

class _SearchBarShellState extends State<SearchBarShell> {
  /// Gap between the field and the overlay panel.
  static const double _overlayGap = 6.0;

  late final GhostTextEditingController _text;
  late final FocusNode _focusNode;
  late final SearchBarController _controller;
  late SearchFilters _filters;

  final _overlay = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _text = widget.controller ?? GhostTextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _filters = widget.initialFilters ?? SearchFilters();

    _controller = SearchBarController(
      text: _text,
      focusNode: _focusNode,
      requestSuggestions: widget.requestSuggestions,
      suggestionsEnabled: widget.suggestionsEnabled,
      onQueryChanged: widget.onChanged,
      onResultSelected: widget.onResultSelected,
    );

    _controller.addListener(_onStateChanged);
    // The field's own text is part of what it renders (the clear button
    // appears with it), so every controller change repaints.
    _text.addListener(_onStateChanged);
  }

  @override
  void didUpdateWidget(SearchBarShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilters != oldWidget.initialFilters &&
        widget.initialFilters != null) {
      setState(() => _filters = widget.initialFilters!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _text.ghostColor = MbPalette.ensureContrast(
      context.colors.textMuted,
      context.colors.surfaceRaised,
      minimum: 4.5,
    );
  }

  @override
  void dispose() {
    _text.removeListener(_onStateChanged);
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    if (widget.controller == null) _text.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    final visible = _controller.isOverlayVisible;
    if (visible != _overlay.isShowing) {
      if (visible) {
        _overlay.show();
      } else {
        _overlay.hide();
      }
    }
  }

  Widget _buildSuggestions(BuildContext context, OverlayChildLayoutInfo info) {
    final field = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom + media.padding.bottom;
    final below =
        info.overlaySize.height - bottomInset - field.bottom - _overlayGap;
    final above = field.top - media.padding.top - _overlayGap;
    // Keep results attached to the field while reserving room for the keyboard.
    final placeAbove = below < 160 && above > below;
    final maxHeight = placeAbove ? above : below;
    if (maxHeight <= 0) return const SizedBox.shrink();

    return Positioned(
      left: field.left,
      width: field.width,
      top: placeAbove ? null : field.bottom + _overlayGap,
      bottom: placeAbove
          ? info.overlaySize.height - field.top + _overlayGap
          : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          elevation: 8,
          color: Colors.transparent,
          child: SearchSuggestionsPanel(
            results: _controller.results,
            onResultTapped: _controller.selectResult,
            showSuggestions: true,
            selectedIndex: _controller.selectedIndex,
            onResultHovered: widget.onResultHovered,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rebuildOn = widget.rebuildOn;
    return ListenableBuilder(
      listenable: rebuildOn == null
          ? LocalizationService()
          : Listenable.merge([LocalizationService(), rebuildOn]),
      builder: (context, _) => OverlayPortal.overlayChildLayoutBuilder(
        controller: _overlay,
        overlayChildBuilder: _buildSuggestions,
        child: _buildTextField(context),
      ),
    );
  }

  Widget _buildTextField(BuildContext context) {
    final l10n = LocalizationService();

    // Kerning is disabled so the ghost span lines up exactly with the typed
    // text; with it on, the completion visibly shifts as it is accepted.
    const features = [FontFeature.disable('kern')];
    final baseStyle =
        Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: context.colors.text,
          fontSize: 16,
          letterSpacing: 0,
          fontFeatures: features,
        ) ??
        TextStyle(
          color: context.colors.text,
          fontSize: 16,
          letterSpacing: 0,
          fontFeatures: features,
        );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      borderSide: BorderSide.none,
    );

    return TextField(
      controller: _text,
      focusNode: _focusNode,
      style: baseStyle,
      textAlignVertical: TextAlignVertical.center,
      textInputAction: TextInputAction.search,
      onChanged: _controller.onTextChanged,
      onSubmitted: (text) {
        // A chosen suggestion already ran its own selection path; only a plain
        // submission needs the query handed on.
        if (_controller.resolveSubmission() != null) return;
        (widget.onSubmitted ?? widget.onChanged)(text);
      },
      decoration: InputDecoration(
        hintText: l10n.translate('search_hint'),
        hintStyle: AppTypography.sans(
          color: MbPalette.ensureContrast(
            context.colors.textMuted,
            context.colors.surfaceRaised,
            minimum: 4.5,
          ),
          fontSize: 16,
        ),
        prefixIcon: widget.onBackTap == null
            ? Icon(Icons.search, color: context.colors.text)
            : IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: context.colors.text,
                ),
                onPressed: () {
                  _controller.clear();
                  widget.onBackTap!();
                },
              ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 48,
        ),
        suffixIcon: MBSearchBarSuffix(
          controllerText: _text.text,
          onClear: _controller.clear,
          onScanTap: widget.onScanTap,
          onFilterTap: widget.showFilterButton ? _openFilterSheet : null,
          currentFilters: _filters,
        ),
        filled: true,
        fillColor: context.colors.surfaceRaised,
        border: border,
        enabledBorder: border,
        // Amber ring on focus: the pill is otherwise identical focused and
        // unfocused, which leaves keyboard users with no cue at all.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          borderSide: BorderSide(
            color: context.colors.accentForeground,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 20,
        ),
      ),
    );
  }

  void _openFilterSheet() {
    SearchFilterSheetLauncher.show(
      context,
      initialFilters: _filters,
      showLibrarySorts: widget.showLibrarySorts,
      onApply: (filters) {
        setState(() => _filters = filters);
        widget.onFilterApplied?.call(filters);
      },
    );
  }
}
