import 'package:mangabaka_app/features/series/widgets/rating_selection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'dart:async';
import 'package:mangabaka_app/core/theme/theme_context.dart';
import 'package:mangabaka_app/features/library/models/library_entry_edit.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';

class RatingIconButton extends StatelessWidget {
  final int? currentRating;
  final FutureOr<void> Function(int) onRatingChanged;

  const RatingIconButton({
    super.key,
    required this.currentRating,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasRating = currentRating != null;
    final colors = context.colors;

    return Container(
      height: 44,
      width: 54,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: IconButton(
        icon: RatingStar(
          icon: hasRating ? Icons.star : Icons.star_border,
          surface: colors.surface,
          size: 24,
        ),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            enableDrag: false,
            useSafeArea: true,
            constraints: const BoxConstraints(maxWidth: 540),
            builder: (ctx) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: RatingSelectionDialog(
                initialRating: currentRating,
                onRatingChanged: (rating) async {
                  await onRatingChanged(rating);
                  return LibrarySaveOutcome.saved;
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
