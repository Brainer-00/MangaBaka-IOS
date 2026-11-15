import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/theme_context.dart';

/// Cheap stand-in shown for the one frame before the real tags are built — a
/// couple of rows of pill outlines so the card doesn't pop in from nothing.
class TagsPlaceholder extends StatelessWidget {
  const TagsPlaceholder({super.key});

  /// Chip widths per row, picked to look like plausible tag names rather than
  /// a uniform grid.
  static const List<List<double>> _rows = [
    [90, 130, 70],
    [110, 80, 150],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in _rows) ...[
            _PlaceholderRow(
              widths: row,
              availableWidth: constraints.maxWidth,
              color: colors.surfaceRaised.withValues(alpha: 0.65),
            ),
            if (row != _rows.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({
    required this.widths,
    required this.availableWidth,
    required this.color,
  });

  static const _gap = 8.0;

  final List<double> widths;
  final double availableWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final intrinsicWidth =
        widths.fold<double>(0, (sum, width) => sum + width) +
        _gap * (widths.length - 1);
    final scale = availableWidth.isFinite && availableWidth < intrinsicWidth
        ? availableWidth / intrinsicWidth
        : 1.0;

    return Row(
      children: [
        for (var index = 0; index < widths.length; index++) ...[
          Container(
            width: widths[index] * scale,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            ),
          ),
          if (index != widths.length - 1) SizedBox(width: _gap * scale),
        ],
      ],
    );
  }
}
