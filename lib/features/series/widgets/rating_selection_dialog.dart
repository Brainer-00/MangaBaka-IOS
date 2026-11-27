import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/widgets/guarded_draggable_sheet.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_enums.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';
import 'package:mangabaka_app/core/widgets/route_dismiss_guard.dart';

class RatingSelectionDialog extends StatefulWidget {
  final bool mobileSheet;
  final int? initialRating;
  final Future<LibrarySaveOutcome> Function(int) onRatingChanged;
  final Future<bool?> Function(int)? onCheckEntry;

  const RatingSelectionDialog({
    super.key,
    required this.initialRating,
    required this.onRatingChanged,
    this.onCheckEntry,
    this.mobileSheet = false,
  });

  @override
  State<RatingSelectionDialog> createState() => _RatingSelectionDialogState();
}

class _RatingSelectionDialogState extends State<RatingSelectionDialog>
    with
        RouteDismissGuard<RatingSelectionDialog>,
        EditorDismissal<RatingSelectionDialog> {
  @override
  bool get exitLocked => _busy;

  @override
  bool get hasPendingEdits =>
      _outcome == null && _rating != (widget.initialRating ?? 0);
  late int _rating = widget.initialRating ?? 0;
  bool _busy = false;
  LibrarySaveOutcome? _outcome;
  String? _feedback;

  Future<void> _submit() async {
    if (_busy || _outcome != null) return;
    if (_rating == (widget.initialRating ?? 0)) {
      Navigator.of(context).pop();
      return;
    }
    canPopNotifier.value = false;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final outcome = await widget.onRatingChanged(_rating);
      if (!mounted) return;
      if (outcome == LibrarySaveOutcome.saved) {
        Navigator.of(context).pop();
      } else {
        setState(() => _outcome = outcome);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if ((error.statusCode >= 400 && error.statusCode < 500) ||
          error.code == 'WRITE_DECLINED') {
        setState(() => _feedback = 'library_editor_rejected');
      } else {
        setState(() => _outcome = LibrarySaveOutcome.uncertain);
      }
    } on AuthException {
      if (mounted) setState(() => _feedback = 'library_editor_auth_retry');
    } catch (_) {
      if (mounted) setState(() => _outcome = LibrarySaveOutcome.uncertain);
    } finally {
      if (mounted) {
        canPopNotifier.value = true;
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _check() async {
    if (_busy || widget.onCheckEntry == null) return;
    canPopNotifier.value = false;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final matches = await widget.onCheckEntry!(_rating);
      if (!mounted) return;
      if (matches == true && _outcome == LibrarySaveOutcome.refreshPending) {
        Navigator.of(context).pop();
      } else {
        setState(
          () => _feedback = switch (matches) {
            true => 'library_editor_found',
            false => 'rating_not_reflected',
            null => 'library_editor_not_found',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _feedback = 'library_editor_check_failed');
    } finally {
      if (mounted) {
        canPopNotifier.value = true;
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalizationService().translate;
    final colors = context.colors;
    final outcome = _outcome;
    final hasRating = _rating > 0 || widget.initialRating == 0;
    final badge = Color.alphaBlend(
      AppConstants.starColor.withValues(alpha: 0.1),
      colors.surface,
    );
    Widget content([ScrollController? scroll]) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Material(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.largeRadius),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: badge,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: RatingStar(size: 24),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        t('rating_dialog_title').toUpperCase(),
                        style: AppTypography.display(
                          color: colors.text,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Wrap(
                        spacing: 10,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          RatingStar(
                            icon: hasRating ? Icons.star : Icons.star_outline,
                            size: 28,
                          ),
                          Text(
                            hasRating ? '$_rating / 100' : t('rating_unrated'),
                            style: AppTypography.display(
                              color: colors.text,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Slider(
                  value: _rating.toDouble(),
                  max: 100,
                  divisions: switch (SettingsManager().ratingSliderStep) {
                    RatingSliderStep.step5 => 20,
                    RatingSliderStep.step10 => 10,
                    RatingSliderStep.step20 => 5,
                    RatingSliderStep.step25 => 4,
                    RatingSliderStep.step1 => 100,
                  },
                  activeColor: colors.usesCanonicalYellow
                      ? colors.accent
                      : colors.accentOn(colors.surface, minimum: 3),
                  inactiveColor: colors.border,
                  onChanged: _busy || outcome != null
                      ? null
                      : (value) => setState(() => _rating = value.toInt()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final value in const ['0', '50', '100'])
                      Flexible(
                        child: Text(
                          value,
                          style: AppTypography.sans(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (outcome != null || _feedback != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t(
                        _feedback ??
                            (outcome == LibrarySaveOutcome.refreshPending
                                ? 'library_editor_refresh_pending'
                                : 'library_editor_uncertain'),
                      ),
                    ),
                  ),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : widget.mobileSheet
                          ? requestEditorDismissal
                          : () {
                              if (!_busy) Navigator.of(context).pop();
                            },
                      child: Text(t(outcome == null ? 'cancel' : 'close')),
                    ),
                    if (outcome == null)
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(
                          t(_busy ? 'library_editor_saving' : 'update'),
                        ),
                      )
                    else if (widget.onCheckEntry != null)
                      OutlinedButton(
                        onPressed: _busy ? null : _check,
                        child: Text(t('library_editor_check_entry')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!widget.mobileSheet) return content();
    return guardEditorDismissal(
      GuardedDraggableSheet(
        openExtent: .60,
        dismissExtent: .30,
        canDrag: () => !exitLocked,
        onDismiss: requestEditorDismissal,
        builder: (_, scroll, handle) => Column(
          children: [
            ?handle,
            Expanded(child: content(scroll)),
          ],
        ),
      ),
    );
  }
}
