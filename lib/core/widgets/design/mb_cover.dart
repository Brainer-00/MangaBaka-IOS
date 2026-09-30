import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/core/utils/widget_utils.dart';

/// A series cover at the design system's corner radius, with a consistent
/// placeholder well behind it.
///
/// Wraps [WidgetUtils.networkImage] rather than re-implementing caching, so
/// asset URLs, blur and memory-cache sizing keep working unchanged.
class MbCover extends StatelessWidget {
  final String url;
  final double width;

  /// Defaults to the 2:3 cover ratio the API's images use.
  final double? height;
  final double radius;
  final BoxFit fit;
  final int? memCacheWidth;
  final String contentRating;

  const MbCover({
    super.key,
    required this.url,
    required this.width,
    this.height,
    this.radius = 14,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.contentRating = '',
  });

  @override
  Widget build(BuildContext context) {
    final h = height ?? width * 1.5;
    // CachedNetworkImage sizes decoded images in physical pixels. Most cover
    // callers know only their logical layout width, so derive a bounded decode
    // width from the active display when a surface has not supplied a more
    // specific override. Explicit values remain authoritative for surfaces
    // whose layout deliberately uses a different bound.
    final decodedWidth =
        memCacheWidth ??
        (width.isFinite
            ? (width * MediaQuery.devicePixelRatioOf(context)).round()
            : null);
    Widget cover(bool blurred) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width,
        height: h,
        color: AppConstants.tertiaryBackground,
        child: WidgetUtils.networkImage(
          url: url,
          width: width,
          height: h,
          fit: fit,
          memCacheWidth: decodedWidth,
          blurred: blurred,
        ),
      ),
    );

    if (contentRating.isEmpty) return cover(false);
    return ListenableBuilder(
      listenable: SettingsManager(),
      builder: (context, _) =>
          cover(WidgetUtils.isRatingBlurred(contentRating)),
    );
  }
}
