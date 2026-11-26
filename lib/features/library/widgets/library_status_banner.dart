import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';

class LibraryStatusBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  final Widget? action;
  final VoidCallback? onClose;

  const LibraryStatusBanner({
    super.key,
    required this.message,
    required this.icon,
    required this.color,
    this.action,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final background = Color.alphaBlend(
      color.withValues(alpha: 0.12),
      context.colors.background,
    );
    final foreground = MbPalette.ensureContrast(
      color,
      background,
      minimum: 4.5,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: background),
      child: Row(
        children: [
          if (icon == Icons.warning_amber_rounded)
            SemanticYellowIcon(icon: icon, size: 18)
          else
            Icon(icon, color: foreground, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.sans(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ?action,
          if (onClose != null)
            IconButton(
              icon: Icon(Icons.close, color: foreground, size: 16),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}
