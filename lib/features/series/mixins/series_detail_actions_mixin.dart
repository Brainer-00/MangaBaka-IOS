import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/database/database.dart'
    show LibraryCacheLease;
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/core/widgets/app_snack_bar.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/widgets/library_entry_editor_sheet.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/series/widgets/progress_update_dialog.dart';
import 'package:mangabaka_app/features/series/widgets/rating_selection_dialog.dart';

mixin SeriesDetailActionsMixin<T extends StatefulWidget> on State<T> {
  LibraryService get libraryService;
  Series get series;
  LibraryCacheLease? _editorLease;
  LibraryCacheLease? _ratingLease;

  bool get libraryEditorOpen =>
      _editorLease != null &&
      identical(_editorLease, getIt<ProfileAuthService>().libraryLease);

  Future<void> showUpdateRatingDialog(LibraryEntry entry) async {
    final auth = getIt<ProfileAuthService>();
    final lease = auth.libraryLease;
    if (lease == null || identical(_ratingLease, lease)) return;
    bool current() => identical(lease, auth.libraryLease);
    final id = series.id;
    _ratingLease = lease;

    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        enableDrag: false,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 540),
        builder: (context) => ListenableBuilder(
          listenable: auth,
          builder: (context, _) => !current()
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: RatingSelectionDialog(
                    mobileSheet: true,
                    initialRating: entry.rating,
                    onRatingChanged: (rating) async {
                      final result = await libraryService
                          .updateLibraryEntryRating(id, rating, lease: lease);
                      if (!current()) {
                        throw AuthException(message: 'Library session changed');
                      }
                      return result.outcome;
                    },
                    onCheckEntry: (rating) async {
                      final entry = await libraryService
                          .fetchAuthoritativeLibraryEntry(id, lease: lease);
                      if (!current()) {
                        throw AuthException(message: 'Library session changed');
                      }
                      return entry == null
                          ? null
                          : entry.rating == (rating == 0 ? null : rating);
                    },
                  ),
                ),
        ),
      );
    } finally {
      if (identical(_ratingLease, lease)) _ratingLease = null;
    }
  }

  void showUpdateProgressDialog(LibraryEntry entry, {bool isChapter = true}) {
    final auth = getIt<ProfileAuthService>();
    final lease = auth.libraryLease;
    if (lease == null) return;
    bool current() => identical(lease, auth.libraryLease);

    final l10n = LocalizationService();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: false,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 540),
      builder: (context) => ListenableBuilder(
        listenable: auth,
        builder: (context, _) => !current()
            ? const SizedBox.shrink()
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ProgressUpdateDialog(
                  mobileSheet: true,
                  initialValue:
                      (isChapter
                          ? entry.progressChapter
                          : entry.progressVolume) ??
                      0,
                  title: isChapter
                      ? l10n.translate('update_chapters')
                      : l10n.translate('update_volumes'),
                  maxValue: isChapter
                      ? series.totalChapters
                      : series.finalVolume,
                  onUpdate: (value) async {
                    if (!current()) return;
                    if (isChapter) {
                      await libraryService.updateLibraryEntryProgress(
                        series.id,
                        progressChapter: value,
                      );
                    } else {
                      await libraryService.updateLibraryEntryProgress(
                        series.id,
                        progressVolume: value,
                      );
                    }
                  },
                ),
              ),
      ),
    );
  }

  void shareLink() {
    final l10n = LocalizationService();
    final String? link = series.links
        .whereType<String>()
        .where((l) => l.contains('mangabaka'))
        .firstOrNull;

    if (link != null) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (context) {
          final colors = context.colors;
          return Container(
            key: const Key('series_share_sheet'),
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        key: const Key('series_share_handle'),
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      _buildShareOption(
                        context: context,
                        key: const Key('series_share_action'),
                        icon: Icons.share_rounded,
                        title: l10n.translate('share_series'),
                        onTap: () {
                          Navigator.pop(context);
                          final box =
                              this.context.findRenderObject() as RenderBox?;
                          SharePlus.instance.share(
                            ShareParams(
                              text: link,
                              sharePositionOrigin: box != null
                                  ? box.localToGlobal(Offset.zero) & box.size
                                  : null,
                            ),
                          );
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Divider(
                          height: 1,
                          thickness: 0.5,
                          color: colors.border,
                        ),
                      ),
                      _buildShareOption(
                        context: context,
                        key: const Key('series_copy_action'),
                        icon: Icons.copy_rounded,
                        title: l10n.translate('copy_link'),
                        onTap: () {
                          Navigator.pop(context);
                          copyToClipboard(link);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      AppSnackBar.show(context, l10n.translate('no_sharing_link'));
    }
  }

  Widget _buildShareOption({
    required BuildContext context,
    Key? key,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    final iconSurface = Color.alphaBlend(
      colors.accent.withValues(alpha: 0.1),
      colors.background,
    );
    return ListTile(
      key: key,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: colors.accentOn(iconSurface), size: 24),
      ),
      title: Text(
        title,
        style: AppTypography.sans(
          color: colors.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: MbPalette.ensureContrast(
          colors.textMuted,
          colors.background,
          minimum: 3.0,
        ),
      ),
    );
  }

  void showDeleteConfirmationDialog() {
    final auth = getIt<ProfileAuthService>();
    final lease = auth.libraryLease;
    if (lease == null) return;
    bool current() => identical(lease, auth.libraryLease);

    final l10n = LocalizationService();
    showDialog(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          if (!current()) return const SizedBox.shrink();
          final colors = context.colors;
          final errorSurface = Color.alphaBlend(
            colors.error.withValues(alpha: 0.1),
            colors.surface,
          );
          return AlertDialog(
            key: const Key('series_delete_dialog'),
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.largeRadius),
              side: BorderSide(color: colors.border, width: 1.5),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delete_sweep_rounded,
                    color: MbPalette.ensureContrast(
                      colors.error,
                      errorSurface,
                      minimum: 3.0,
                    ),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('delete_from_library').toUpperCase(),
                    style: AppTypography.display(
                      color: colors.text,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              l10n.translate('delete_confirmation'),
              style: AppTypography.sans(
                color: MbPalette.ensureContrast(
                  colors.textMuted,
                  colors.surface,
                  minimum: 4.5,
                ),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  l10n.translate('cancel'),
                  style: AppTypography.sans(
                    color: MbPalette.ensureContrast(
                      colors.textMuted,
                      colors.surface,
                      minimum: 4.5,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    if (!current()) return;
                    await libraryService.deleteEntry(series.id);
                    if (mounted && current()) Navigator.pop(this.context);
                  } catch (e) {
                    if (mounted && current()) {
                      AppSnackBar.show(
                        this.context,
                        LocalizationService().translate('failed_to_delete'),
                        isError: true,
                      );
                    }
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: MbPalette.readableOn(colors.error),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.pillRadius,
                    ),
                  ),
                ),
                child: Text(
                  l10n.translate('confirm'),
                  style: AppTypography.sans(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnackBar.show(
      context,
      LocalizationService()
          .translate('copied_to_clipboard')
          .replaceAll('{text}', text),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> addSeriesToLibrary() => _openLibraryEditor(edit: false);

  Future<void> editSeriesLibraryEntry() => _openLibraryEditor(edit: true);

  Future<void> _openLibraryEditor({required bool edit}) async {
    final auth = getIt<ProfileAuthService>();
    final lease = auth.libraryLease;
    if (lease == null || identical(_editorLease, lease)) return;
    final requestedSeries = series;
    final settings = SettingsManager();
    setState(() => _editorLease = lease);
    try {
      await LibraryEntryEditorSheet.show(
        context,
        library: libraryService,
        auth: auth,
        lease: lease,
        series: requestedSeries,
        title: requestedSeries.getDisplayTitle(settings.defaultTitleLanguage),
        defaultState: settings.addLibraryDefaultTab,
        edit: edit,
      );
    } finally {
      if (mounted && identical(_editorLease, lease)) {
        setState(() => _editorLease = null);
      }
    }
  }
}
