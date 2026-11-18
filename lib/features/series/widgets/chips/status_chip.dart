import 'package:flutter/material.dart';
import 'package:mangabaka_app/features/series/widgets/mini_badge.dart';
import 'package:mangabaka_app/core/localization/localization_service.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({required this.status, super.key});

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;

    final lower = status.toLowerCase();

    Color? color;
    IconData? icon;
    Color? bgColor;

    if (lower == 'releasing') {
      color = colors.success;
      icon = Icons.play_arrow_outlined;
      bgColor = Color.alphaBlend(
        color.withValues(alpha: 0.12),
        colors.surfaceRaised,
      );
    } else if (lower == 'completed') {
      color = colors.info;
      icon = Icons.check_circle_outline_outlined;
      bgColor = Color.alphaBlend(
        color.withValues(alpha: 0.12),
        colors.surfaceRaised,
      );
    } else if (lower == 'hiatus') {
      color = colors.warning;
      icon = Icons.pause_circle_outline;
      bgColor = Color.alphaBlend(
        color.withValues(alpha: 0.12),
        colors.surfaceRaised,
      );
    }

    return MiniBadge(
      text: status,
      icon: icon,
      color: color,
      backgroundColor: bgColor,
      ensureColorContrast: true,
      tooltip: LocalizationService().translate('status'),
    );
  }
}
