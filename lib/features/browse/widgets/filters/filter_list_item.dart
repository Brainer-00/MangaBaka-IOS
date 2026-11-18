import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/browse/widgets/filters/tri_state_chip.dart';

class FilterListItem extends StatelessWidget {
  final String name;
  final TriState state;
  final VoidCallback onToggleInclude;
  final VoidCallback onToggleExclude;

  const FilterListItem({
    super.key,
    required this.name,
    required this.state,
    required this.onToggleInclude,
    required this.onToggleExclude,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggleInclude,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: AppTypography.sans(
                    color: state != TriState.off
                        ? colors.text
                        : MbPalette.ensureContrast(
                            colors.textMuted,
                            colors.background,
                            minimum: 4.5,
                          ),
                    fontSize: 16,
                    fontWeight: state != TriState.off
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
              _buildActionIcon(
                icon: Icons.check_circle,
                isActive: state == TriState.include,
                activeColor: colors.accentOn(colors.background),
                inactiveColor: colors.textMuted,
                backgroundColor: colors.background,
                onTap: onToggleInclude,
              ),
              const SizedBox(width: 8),
              _buildActionIcon(
                icon: Icons.cancel,
                isActive: state == TriState.exclude,
                activeColor: MbPalette.ensureContrast(
                  colors.error,
                  colors.background,
                  minimum: 4.5,
                ),
                inactiveColor: colors.textMuted,
                backgroundColor: colors.background,
                onTap: onToggleExclude,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    final selectedBackground = Color.alphaBlend(
      activeColor.withValues(alpha: 0.1),
      backgroundColor,
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isActive ? selectedBackground : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive
              ? MbPalette.ensureContrast(
                  activeColor,
                  selectedBackground,
                  minimum: 4.5,
                )
              : MbPalette.ensureContrast(
                  inactiveColor,
                  backgroundColor,
                  minimum: 3.0,
                ),
          size: 26,
        ),
      ),
    );
  }
}
