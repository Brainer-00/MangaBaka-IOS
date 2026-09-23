import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';
import 'package:mangabaka_app/core/widgets/app_snack_bar.dart';
import 'package:mangabaka_app/desktop/desktop_layout.dart';
import 'package:mangabaka_app/desktop/widgets/desktop_surfaces.dart';
import 'package:mangabaka_app/features/profile/widgets/settings/settings_components.dart';
import 'package:url_launcher/url_launcher.dart';

/// Privacy disclosures and legal resources for this independent client.
///
/// The content has no authentication dependency and is shared by the phone,
/// landscape-dialog, and desktop settings presentations.
class PrivacyLegalScreen extends StatelessWidget {
  const PrivacyLegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = LocalizationService();
    return Scaffold(
      backgroundColor: AppConstants.primaryBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          l10n.translate('privacy_and_legal').toUpperCase(),
          style: AppTypography.display(
            color: AppConstants.textColor,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: WidgetUtils.responsiveConstraint(
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.horizontalPadding,
            8,
            AppConstants.horizontalPadding,
            80,
          ),
          children: [PrivacyLegalContent(l10n: l10n)],
        ),
      ),
    );
  }
}

class PrivacyLegalContent extends StatelessWidget {
  final LocalizationService l10n;

  const PrivacyLegalContent({super.key, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _LegalAction(
        icon: Icons.privacy_tip_outlined,
        titleKey: 'privacy_policy',
        subtitleKey: 'project_document_subtitle',
        onTap: () => _openExternal(context, AppConstants.privacyPolicyUrl),
      ),
      _LegalAction(
        icon: Icons.gavel_outlined,
        titleKey: 'terms_of_use',
        subtitleKey: 'project_document_subtitle',
        onTap: () => _openExternal(context, AppConstants.termsUrl),
      ),
      _LegalAction(
        icon: Icons.fact_check_outlined,
        titleKey: 'attribution_and_data',
        subtitleKey: 'project_document_subtitle',
        onTap: () => _openExternal(context, AppConstants.attributionUrl),
      ),
      _LegalAction(
        icon: Icons.policy_outlined,
        titleKey: 'project_security_policy',
        subtitleKey: 'project_document_subtitle',
        onTap: () => _openExternal(context, AppConstants.securityPolicyUrl),
      ),
      _LegalAction(
        icon: Icons.balance_outlined,
        titleKey: 'open_source_licenses',
        subtitleKey: 'license_notice_subtitle',
        external: false,
        onTap: () => showLicensePage(
          context: context,
          applicationName: AppConstants.appName,
          applicationVersion: AppConstants.appVersion,
        ),
      ),
      _LegalAction(
        icon: Icons.open_in_browser_outlined,
        titleKey: 'mangabaka_privacy_policy',
        subtitleKey: 'service_policy_subtitle',
        onTap: () => _openExternal(context, AppConstants.mangaBakaPrivacyUrl),
      ),
      _LegalAction(
        icon: Icons.description_outlined,
        titleKey: 'mangabaka_terms',
        subtitleKey: 'service_policy_subtitle',
        onTap: () => _openExternal(context, AppConstants.mangaBakaTermsUrl),
      ),
      _LegalAction(
        icon: Icons.code_outlined,
        titleKey: 'project_github',
        subtitleKey: 'project_document_subtitle',
        onTap: () => _openExternal(context, AppConstants.githubRepoUrl),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrivacySummary(l10n: l10n),
        const SizedBox(height: 24),
        if (DesktopLayout.isActive(context))
          _DesktopLegalActions(l10n: l10n, actions: actions)
        else
          _MobileLegalActions(l10n: l10n, actions: actions),
      ],
    );
  }

  static Future<void> _openExternal(BuildContext context, String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (opened || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }

    AppSnackBar.show(
      context,
      LocalizationService().translate('external_link_failed'),
      isError: true,
    );
  }
}

class _PrivacySummary extends StatelessWidget {
  final LocalizationService l10n;

  const _PrivacySummary({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final summary = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: AppConstants.accentColor,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.translate('privacy_summary_title').toUpperCase(),
                  style: AppTypography.display(
                    color: AppConstants.textColor,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.translate('privacy_summary_intro'),
            style: AppTypography.sans(
              color: AppConstants.textColor,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          for (final key in const [
            'privacy_summary_oauth',
            'privacy_summary_storage',
            'privacy_summary_requests',
            'privacy_summary_barcode',
            'privacy_summary_anilist',
            'privacy_summary_github',
            'privacy_summary_logs',
            'privacy_summary_sdks',
          ]) ...[
            _SummaryPoint(text: l10n.translate(key)),
            if (key != 'privacy_summary_sdks') const SizedBox(height: 10),
          ],
        ],
      ),
    );

    if (DesktopLayout.isActive(context)) {
      return DesktopCard(
        showBorder: false,
        padding: EdgeInsets.zero,
        child: summary,
      );
    }
    return SettingsGroup(children: [summary]);
  }
}

class _SummaryPoint extends StatelessWidget {
  final String text;

  const _SummaryPoint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.check_circle_outline,
            size: 17,
            color: AppConstants.textMutedColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.sans(
              color: AppConstants.textMutedColor,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileLegalActions extends StatelessWidget {
  final LocalizationService l10n;
  final List<_LegalAction> actions;

  const _MobileLegalActions({required this.l10n, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(title: l10n.translate('project_documents')),
        _group(actions.take(5).toList()),
        const SizedBox(height: 20),
        SettingsSectionHeader(title: l10n.translate('service_policies')),
        _group(actions.skip(5).toList()),
      ],
    );
  }

  Widget _group(List<_LegalAction> items) {
    return SettingsGroup(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SettingsDivider(),
          Semantics(
            button: true,
            link: items[index].external,
            child: SettingsItem(
              icon: items[index].icon,
              title: l10n.translate(items[index].titleKey),
              subtitle: l10n.translate(items[index].subtitleKey),
              onTap: items[index].onTap,
              trailing: Icon(
                items[index].external
                    ? Icons.open_in_new
                    : Icons.chevron_right_rounded,
                color: AppConstants.textMutedColor,
                size: 18,
              ),
              isFirst: index == 0,
              isLast: index == items.length - 1,
            ),
          ),
        ],
      ],
    );
  }
}

class _DesktopLegalActions extends StatelessWidget {
  final LocalizationService l10n;
  final List<_LegalAction> actions;

  const _DesktopLegalActions({required this.l10n, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopSectionTitle(title: l10n.translate('project_documents')),
        _card(actions.take(5).toList()),
        const SizedBox(height: 24),
        DesktopSectionTitle(title: l10n.translate('service_policies')),
        _card(actions.skip(5).toList()),
      ],
    );
  }

  Widget _card(List<_LegalAction> items) {
    return DesktopCard(
      showBorder: false,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 24),
            DesktopSettingRow(
              icon: items[index].icon,
              title: l10n.translate(items[index].titleKey),
              subtitle: l10n.translate(items[index].subtitleKey),
              control: _KeyboardAccessibleDesktopAction(
                label: l10n.translate(
                  items[index].external ? 'open' : 'view',
                ),
                icon: items[index].external
                    ? Icons.open_in_new_rounded
                    : Icons.arrow_forward_rounded,
                onPressed: items[index].onTap,
                link: items[index].external,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyboardAccessibleDesktopAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool link;

  const _KeyboardAccessibleDesktopAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.link,
  });

  @override
  State<_KeyboardAccessibleDesktopAction> createState() =>
      _KeyboardAccessibleDesktopActionState();
}

class _KeyboardAccessibleDesktopActionState
    extends State<_KeyboardAccessibleDesktopAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          border: _focused
              ? Border.all(color: AppConstants.accentColor, width: 2)
              : null,
        ),
        child: Semantics(
          button: true,
          link: widget.link,
          child: DesktopPillButton(
            label: widget.label,
            icon: widget.icon,
            onPressed: widget.onPressed,
          ),
        ),
      ),
    );
  }
}

class _LegalAction {
  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final VoidCallback onTap;
  final bool external;

  const _LegalAction({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.onTap,
    this.external = true,
  });
}
