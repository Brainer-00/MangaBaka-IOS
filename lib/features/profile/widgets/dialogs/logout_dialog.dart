import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';

class LogoutDialog {
  static Future<bool?> showLogoutConfirmationDialog(BuildContext context) {
    final l10n = LocalizationService();
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        final warningBackground = Color.alphaBlend(
          colors.error.withValues(alpha: 0.05),
          colors.surface,
        );
        final warningForeground = MbPalette.ensureContrast(
          colors.error,
          warningBackground,
          minimum: 4.5,
        );
        return AlertDialog(
          scrollable: true,
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.largeRadius),
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
                  Icons.logout_rounded,
                  color: MbPalette.ensureContrast(
                    colors.error,
                    Color.alphaBlend(
                      colors.error.withValues(alpha: 0.1),
                      colors.surface,
                    ),
                    minimum: 3,
                  ),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  l10n.translate('logout').toUpperCase(),
                  style: AppTypography.display(
                    color: colors.text,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to log out?',
                style: AppTypography.sans(color: colors.text, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppConstants.denseRadius),
                  border: Border.all(
                    color: colors.error.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: MbPalette.ensureContrast(
                        colors.error,
                        warningBackground,
                        minimum: 3,
                      ),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your local library data will be cleared and must be reimported when you log back in.',
                        style: AppTypography.sans(
                          color: warningForeground,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
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
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: MbPalette.readableOn(colors.error),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                ),
              ),
              child: Text(
                l10n.translate('logout'),
                style: AppTypography.sans(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }
}
