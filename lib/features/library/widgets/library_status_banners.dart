import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/network/backend_health_service.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';
import 'package:mangabaka_app/features/library/widgets/library_status_banner.dart';

/// Account-specific sync and import notices above the Library list.
class LibraryStatusBanners extends StatelessWidget {
  /// Status messages belong to an active account session. Once the session
  /// has ended, the sign-in prompt is the complete state and stale sync
  /// failures should not remain above it.
  final bool loggedIn;

  final LibrarySyncStatus status;

  final VoidCallback onRetrySync;
  final VoidCallback onDismissError;

  const LibraryStatusBanners({
    super.key,
    required this.loggedIn,
    required this.status,
    required this.onRetrySync,
    required this.onDismissError,
  });

  @override
  Widget build(BuildContext context) {
    if (!loggedIn) return const SizedBox.shrink();

    final l10n = LocalizationService();
    final colors = context.colors;
    final showInitialImport =
        status.initialImportIncomplete && !status.pageLimitReached;
    final showLocalOutage =
        status.isServerDown && !getIt.isRegistered<BackendHealthService>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLocalOutage)
          LibraryStatusBanner(
            message: l10n.translate('backend_unreachable'),
            icon: Icons.cloud_off_rounded,
            color: context.colors.error,
            action: _action(
              context: context,
              label: l10n.translate('retry'),
              color: context.colors.error,
              onPressed: onRetrySync,
            ),
          ),
        if (status.pageLimitReached)
          LibraryStatusBanner(
            message: l10n.translate('library_limit_warning'),
            icon: Icons.warning_amber_rounded,
            color: context.colors.warning,
            action: _action(
              context: context,
              label: l10n.translate('update'),
              color: context.colors.warning,
              onPressed: onRetrySync,
            ),
          ),
        if (!status.isSyncing &&
            (showInitialImport ||
                (!status.isServerDown && status.error != null)))
          LibraryStatusBanner(
            message: showInitialImport
                ? l10n.translate('library_initial_import_incomplete')
                : l10n
                      .translate('sync_failed')
                      .replaceAll('{message}', l10n.translate(status.error!)),
            icon: Icons.error_outline_rounded,
            color: colors.error,
            action: status.isServerDown
                ? null
                : _action(
                    context: context,
                    label: l10n.translate('retry'),
                    color: colors.error,
                    onPressed: onRetrySync,
                  ),
            onClose: showInitialImport ? null : onDismissError,
          ),
      ],
    );
  }

  Widget _action({
    required BuildContext context,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: AppTypography.sans(
          color: MbPalette.ensureContrast(
            color,
            Color.alphaBlend(
              color.withValues(alpha: 0.12),
              context.colors.background,
            ),
            minimum: 4.5,
          ),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
