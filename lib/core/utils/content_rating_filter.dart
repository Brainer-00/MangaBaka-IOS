import 'package:mangabaka_app/core/settings/settings_manager.dart';

/// Turns the user's content-rating preference into request parameters.
///
/// [SettingsManager.contentPreferences] is an *allow-list*: the ratings the
/// user opted into. Most endpoints take that directly as `content_rating`.
/// Mix and hidden-gems also accept `not_content_rating`, the deny-list, which
/// says what the user has chosen *not* to see — so a rating the API adds later
/// is left to the server's default rather than silently ruled in or out by an
/// allow-list that predates it.
abstract final class ContentRatingFilter {
  /// Every rating, least to most explicit.
  static const List<String> all = [
    'safe',
    'suggestive',
    'erotica',
    'pornographic',
  ];

  /// The ratings the user has not opted into. Empty when no preference has
  /// been recorded (which permits everything) or when every rating is allowed.
  static List<String> excluded(Iterable<String> allowed) {
    final allow = allowed.where((r) => r.isNotEmpty).toSet();
    if (allow.isEmpty) return const [];
    return [
      for (final rating in all)
        if (!allow.contains(rating)) rating,
    ];
  }

  /// [excluded] for the current preference.
  static List<String> excludedByPreference() =>
      excluded(SettingsManager().contentPreferences);
}
