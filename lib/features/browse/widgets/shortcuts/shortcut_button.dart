import 'package:mangabaka_app/core/motion/app_motion.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';

class ShortcutButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const ShortcutButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MbTappable(
      onTap: onPressed,
      pressedScale: 0.97,
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.secondaryBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 18.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: AppTypography.display(
                  color: AppConstants.textColor,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppConstants.textMutedColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
