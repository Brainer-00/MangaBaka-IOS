import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';
import 'package:mangabaka_app/features/library/constants/library_screen_constants.dart';

class LibraryStatusDropdown extends StatelessWidget {
  const LibraryStatusDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String>? onChanged;

  static IconData _icon(String state) => switch (state) {
    'reading' => Icons.play_arrow_outlined,
    'rereading' => Icons.refresh,
    'completed' => Icons.check_circle_outline_outlined,
    'paused' => Icons.pause_circle_outline,
    'dropped' => Icons.delete_outline,
    'plan_to_read' => Icons.bookmark_border,
    'considering' => Icons.lightbulb_outline,
    _ => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    final t = LocalizationService().translate;
    final colors = context.colors;
    final fill = AppConstants.getColorForState(value);
    final ink = MbPalette.ensureContrast(
      AppConstants.getOnColorForState(value),
      fill,
      minimum: 4.5,
    );
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.top -
        media.padding.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        return MenuAnchor(
          consumeOutsideTap: true,
          crossAxisUnconstrained: false,
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(colors.surface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
            maximumSize: WidgetStatePropertyAll(
              Size(
                constraints.maxWidth,
                (availableHeight * .55).clamp(0, 320).toDouble(),
              ),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: colors.border),
              ),
            ),
          ),
          menuChildren: [
            for (final tab in LibraryScreenConstants.statusTabs)
              _item(context, tab.key, t(tab.key).toUpperCase()),
          ],
          builder: (context, controller, _) => Semantics(
            label: t('status'),
            child: OutlinedButton(
              onPressed: onChanged == null
                  ? null
                  : () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
              style: OutlinedButton.styleFrom(
                backgroundColor: fill,
                foregroundColor: ink,
                disabledBackgroundColor: colors.surfaceRaised,
                disabledForegroundColor: colors.textMuted,
                side: BorderSide(
                  color: MbPalette.ensureContrast(
                    fill,
                    colors.surface,
                    minimum: 3,
                  ),
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              child: Row(
                spacing: 8,
                children: [
                  Icon(_icon(value), size: 20),
                  Expanded(
                    child: Text(
                      t(value).toUpperCase(),
                      style: AppTypography.display(fontSize: 12.5),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _item(BuildContext context, String state, String label) {
    final colors = context.colors;
    final active = state == value;
    final statusColor = AppConstants.getColorForState(state);
    final selectedFill = Color.alphaBlend(
      statusColor.withValues(alpha: .14),
      colors.surface,
    );
    final surface = active ? selectedFill : colors.surface;
    final ink = MbPalette.ensureContrast(
      active && state != 'paused' ? statusColor : colors.text,
      surface,
      minimum: 4.5,
    );
    return Semantics(
      selected: active,
      child: MenuItemButton(
        onPressed: onChanged == null
            ? null
            : () {
                if (!active) onChanged!(state);
              },
        style: MenuItemButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: active ? selectedFill : null,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          spacing: 10,
          children: [
            SizedBox(
              width: 21,
              child: Center(
                child: state == 'paused'
                    ? SemanticYellowIcon(
                        surface: surface,
                        icon: _icon(state),
                        size: 17,
                      )
                    : Icon(
                        _icon(state),
                        size: 17,
                        color: MbPalette.ensureContrast(
                          statusColor,
                          surface,
                          minimum: 3,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: AppTypography.sans(
                  color: ink,
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (active) Icon(Icons.check_rounded, size: 16, color: ink),
          ],
        ),
      ),
    );
  }
}
