import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/theme/app_typography.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.0, top: 8.0, left: 4.0),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.monoLabel(
          color: AppConstants.textMutedColor,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
