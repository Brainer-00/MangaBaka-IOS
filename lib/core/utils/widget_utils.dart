import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/utils/external_url_launcher.dart';
import 'package:mangabaka_app/features/series/widgets/chip.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';

class WidgetUtils {
  static Widget responsiveConstraint(Widget child, {double maxWidth = 800}) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  static Widget tooltip({required String message, required Widget child}) {
    return AppTooltip(message: message, child: child);
  }

  /// Whether covers of [contentRating] are blurred, per the user's content
  /// preferences. The one answer every cover should ask, so a rating the user
  /// blurs is blurred everywhere it shows.
  static bool isRatingBlurred(String contentRating) => SettingsManager()
      .blurredContentRatings
      .contains(contentRating.toLowerCase());

  static Widget networkImage({
    required String url,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
    int? memCacheWidth,
    int? memCacheHeight,
    bool blurred = false,
  }) {
    if (url.isEmpty) {
      final iconSize = (width != null && width.isFinite) ? width : 24.0;
      return errorWidget ?? _DefaultImageError(iconSize: iconSize);
    }

    final Widget image = url.startsWith('assets/')
        ? Image.asset(
            url,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) {
              final iconSize = (width != null && width.isFinite) ? width : 24.0;
              return errorWidget ?? _DefaultImageError(iconSize: iconSize);
            },
          )
        : CachedNetworkImage(
            imageUrl: url,
            httpHeaders: const {'User-Agent': AppConstants.userAgent},
            width: width,
            height: height,
            fit: fit,
            memCacheWidth: memCacheWidth,
            memCacheHeight: memCacheHeight,
            placeholder: (context, url) =>
                placeholder ?? const _DefaultImagePlaceholder(),
            errorWidget: (context, url, error) {
              final iconSize = (width != null && width.isFinite) ? width : 24.0;
              return _NetworkImageFailure(
                key: ValueKey('$url:${error.runtimeType}'),
                errorType: error.runtimeType,
                child: errorWidget ?? _DefaultImageError(iconSize: iconSize),
              );
            },
            fadeOutDuration: const Duration(milliseconds: 300),
            fadeInDuration: const Duration(milliseconds: 300),
          );

    if (!blurred) return image;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: image,
    );
  }

  static Widget chipWrap(
    String label,
    List<String> items, {
    Color? color,
    Function(String)? onChipTap,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            label.toUpperCase(),
            style: AppTypography.monoLabel(
              color: AppConstants.textMutedColor,
              fontSize: 11.5,
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (e) => ChipBase(
                  backgroundColor: color,
                  label: SelectableText(e),
                  onTap: onChipTap != null ? () => onChipTap(e) : null,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  static Widget linkList(List<dynamic> links) {
    if (links.isEmpty) return const SizedBox.shrink();
    return Builder(
      builder: (context) {
        final colors = context.colors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Links'.toUpperCase(),
                style: AppTypography.monoLabel(
                  color: MbPalette.ensureContrast(
                    colors.textMuted,
                    colors.surface,
                    minimum: 4.5,
                  ),
                  fontSize: 11.5,
                ),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: links.map<Widget>((l) {
                String url = '';
                String displayName = '';
                String? language;

                if (l is String) {
                  final uri = ExternalUrlLauncher.parseHttpsUrl(l);
                  if (uri != null) {
                    url = l;
                    final domain = uri.host.replaceFirst('www.', '');
                    displayName = domain.split('.').first;
                    displayName =
                        displayName[0].toUpperCase() + displayName.substring(1);

                    final langMatch = RegExp(
                      r'\/([a-z]{2})\/',
                    ).firstMatch(uri.path);
                    if (langMatch != null) {
                      language = langMatch.group(1)!.toUpperCase();
                    }
                  }
                } else if (l.runtimeType.toString() == 'SeriesLink') {
                  try {
                    url = l.url;
                    displayName = l.nameDisplay;
                    language = l.language?.toString().toUpperCase();
                  } catch (e) {
                    return const SizedBox.shrink();
                  }
                }

                if (url.isEmpty) return const SizedBox.shrink();
                final uri = ExternalUrlLauncher.parseHttpsUrl(url);
                if (uri == null) return const SizedBox.shrink();
                final domain = uri.host.replaceFirst('www.', '');
                final faviconUrl =
                    'https://www.google.com/s2/favicons?domain=$domain&sz=64';

                return _HoverableLinkChip(
                  uri: uri,
                  faviconUrl: faviconUrl,
                  displayName: displayName,
                  language: language,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

/// Reads theme colors during its own build so cached image state can recolor
/// without changing the image key or restarting the image request.
class _DefaultImagePlaceholder extends StatelessWidget {
  const _DefaultImagePlaceholder();

  @override
  Widget build(BuildContext context) =>
      Container(color: context.colors.surfaceRaised);
}

class _DefaultImageError extends StatelessWidget {
  const _DefaultImageError({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      color: colors.surfaceRaised,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Icon(
          Icons.broken_image,
          size: iconSize,
          color: MbPalette.ensureContrast(
            colors.textMuted,
            colors.surfaceRaised,
            minimum: 4.5,
          ),
        ),
      ),
    );
  }
}

/// Logs once when this URL enters its failed state. Keeping the error visual in
/// a child widget prevents a parent theme rebuild from repeating the log.
class _NetworkImageFailure extends StatefulWidget {
  const _NetworkImageFailure({
    super.key,
    required this.errorType,
    required this.child,
  });

  final Type errorType;
  final Widget child;

  @override
  State<_NetworkImageFailure> createState() => _NetworkImageFailureState();
}

class _NetworkImageFailureState extends State<_NetworkImageFailure> {
  @override
  void initState() {
    super.initState();
    // Surface the failing host + error so image outages (dead CDN, TLS
    // handshake, cleartext block, rate limit) remain diagnosable in app logs.
    LoggingService.logger.warning('Image load failed (${widget.errorType})');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A reactive tooltip that listens to [SettingsManager] to show or hide itself.
class AppTooltip extends StatelessWidget {
  final String message;
  final Widget child;

  const AppTooltip({super.key, required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsManager(),
      builder: (context, _) {
        if (!SettingsManager().showTooltips) return child;
        return Tooltip(message: message, child: child);
      },
    );
  }
}

/// A link chip that shows a subtle highlight on hover.
class _HoverableLinkChip extends StatelessWidget {
  final Uri uri;
  final String faviconUrl;
  final String displayName;
  final String? language;

  const _HoverableLinkChip({
    required this.uri,
    required this.faviconUrl,
    required this.displayName,
    this.language,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderRadius = BorderRadius.circular(AppConstants.cardRadius);
    return WidgetUtils.tooltip(
      message: LocalizationService()
          .translate('open_link')
          .replaceAll('{name}', displayName),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border, width: 1),
          borderRadius: borderRadius,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => ExternalUrlLauncher.launchUri(uri),
            borderRadius: borderRadius,
            hoverColor: colors.accent.withValues(alpha: 0.1),
            splashColor: colors.accent.withValues(alpha: 0.1),
            highlightColor: colors.accent.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: WidgetUtils.networkImage(
                      url: faviconUrl,
                      width: 18,
                      height: 18,
                      errorWidget: Icon(
                        Icons.link,
                        size: 18,
                        color: MbPalette.ensureContrast(
                          colors.textMuted,
                          colors.surface,
                          minimum: 4.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    displayName,
                    style: AppTypography.sans(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (language?.isNotEmpty ?? false) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceRaised,
                        border: Border.all(color: colors.border, width: 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        language!,
                        style: AppTypography.monoLabel(
                          color: MbPalette.ensureContrast(
                            colors.textMuted,
                            colors.surfaceRaised,
                            minimum: 4.5,
                          ),
                          fontSize: 10,
                        ),
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
  }
}
