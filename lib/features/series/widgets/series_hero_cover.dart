import 'package:mangabaka_app/features/series/widgets/unblur_warning.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangabaka_app/features/series/models/series.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/features/series/screens/full_screen_image_screen.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

class SeriesHeroCover extends StatefulWidget {
  final Series series;
  final double height;
  final double width;
  final String? heroTagPrefix;

  const SeriesHeroCover({
    super.key,
    required this.series,
    required this.height,
    required this.width,
    this.heroTagPrefix,
  });

  @override
  State<SeriesHeroCover> createState() => _SeriesHeroCoverState();
}

class _SeriesHeroCoverState extends State<SeriesHeroCover> {
  bool _hovered = false;
  bool _focused = false;
  late final FocusNode _focusNode = FocusNode(debugLabel: 'Series cover');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final highlighted = _hovered || _focused;
    return Hero(
      tag: widget.heroTagPrefix != null
          ? '${widget.heroTagPrefix}_${widget.series.id}'
          : 'series_cover_${widget.series.id}',
      child: FocusableActionDetector(
        focusNode: _focusNode,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        onFocusChange: (focused) => setState(() => _focused = focused),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _openCover(context);
              return null;
            },
          ),
        },
        child: Semantics(
          button: true,
          label: widget.series.title,
          onTap: () => _openCover(context),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () => _openCover(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: highlighted
                      ? Border.all(
                          color: colors.accentOn(
                            colors.background,
                            minimum: 3.0,
                          ),
                          width: 2,
                        )
                      : Border.all(color: Colors.transparent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.primaryBackground.withValues(
                        alpha: highlighted ? 0.4 : 0.6,
                      ),
                      blurRadius: highlighted ? 28 : 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ListenableBuilder(
                    listenable: SettingsManager(),
                    builder: (context, _) {
                      final isBlurred = SettingsManager().blurredContentRatings
                          .contains(widget.series.contentRating.toLowerCase());
                      return WidgetUtils.networkImage(
                        url: widget.series.coverUrl,
                        height: widget.height,
                        width: widget.width,
                        fit: BoxFit.cover,
                        memCacheWidth: 400,
                        blurred: isBlurred,
                        placeholder: Container(color: colors.surfaceRaised),
                        errorWidget: Icon(
                          Icons.broken_image,
                          color: colors.textMuted,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCover(BuildContext context) async {
    final imageUrl = widget.series.rawCoverUrl.isNotEmpty
        ? widget.series.rawCoverUrl
        : widget.series.coverUrl;
    if (imageUrl.isNotEmpty) {
      if (WidgetUtils.isRatingBlurred(widget.series.contentRating) &&
          !await confirmUnblur(context)) {
        return;
      }
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenImageScreen(
            imageUrls: [imageUrl],
            heroTag: widget.heroTagPrefix != null
                ? '${widget.heroTagPrefix}_${widget.series.id}'
                : 'series_cover_${widget.series.id}',
          ),
        ),
      );
    }
  }
}
