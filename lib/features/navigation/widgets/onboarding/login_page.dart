import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/navigation/widgets/onboarding/onboarding_hero_layout.dart';

class LoginPage extends StatelessWidget {
  final bool isLoggingIn;
  final bool isLoggedIn;
  final VoidCallback onLogin;

  const LoginPage({
    super.key,
    required this.isLoggingIn,
    required this.isLoggedIn,
    required this.onLogin,
  });

  Widget _buildConnectedBadge(
    BuildContext context,
    LocalizationService localization,
  ) {
    final colors = context.colors;
    final badgeBackground = Color.alphaBlend(
      colors.success.withValues(alpha: 0.1),
      colors.background,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: badgeBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MbPalette.ensureContrast(
            colors.success,
            badgeBackground,
            minimum: 3.0,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: MbPalette.ensureContrast(
              colors.success,
              badgeBackground,
              minimum: 3.0,
            ),
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            localization.translate('onboarding_connected'),
            style: AppTypography.sans(
              color: MbPalette.ensureContrast(
                colors.success,
                badgeBackground,
                minimum: 4.5,
              ),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(
    BuildContext context,
    LocalizationService localization,
    bool isShort,
  ) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: isLoggingIn ? null : onLogin,
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.accent,
          foregroundColor: context.colors.onAccent,
          disabledBackgroundColor: context.colors.accent,
          disabledForegroundColor: context.colors.onAccent,
          padding: EdgeInsets.symmetric(vertical: isShort ? 12 : 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoggingIn
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.colors.onAccent,
                  ),
                ),
              )
            : Text(localization.translate('onboarding_login_button')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocalizationService(),
      builder: (context, _) {
        final localization = LocalizationService();
        return LayoutBuilder(
          builder: (context, constraints) {
            final isShort = constraints.maxHeight < 500;
            return OnboardingHeroLayout(
              icon: Icons.account_circle_rounded,
              title: localization.translate('onboarding_login_title'),
              subtitle: localization.translate('onboarding_login_subtitle'),
              isShort: isShort,
              action: isLoggedIn
                  ? _buildConnectedBadge(context, localization)
                  : _buildLoginButton(context, localization, isShort),
            );
          },
        );
      },
    );
  }
}
