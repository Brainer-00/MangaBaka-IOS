import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/widgets/design/rating_star.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';

/// A static, scaled drawing of Home using the effective palette.
class ThemeMiniaturePreview extends StatelessWidget {
  const ThemeMiniaturePreview({super.key, required this.palette});

  final MbPalette palette;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AspectRatio(
      aspectRatio: 160 / 328,
      child: Container(
        key: const Key('appearance_preview_background'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: 160,
            height: 328,
            child: Column(
              children: [
                SizedBox(
                  key: const Key('appearance_preview_header'),
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Expanded(
                          child: Center(
                            child: Text(
                              'HOME',
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 12,
                          child: Icon(
                            Icons.settings_outlined,
                            size: 9,
                            color: palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _heading('FOR YOU'),
                const SizedBox(height: 9),
                _covers(first: true),
                const SizedBox(height: 17),
                _heading('TOP IN CULT', action: true),
                const SizedBox(height: 9),
                _covers(first: false),
                const Spacer(),
                Container(
                  key: const Key('appearance_preview_navigation'),
                  height: 30,
                  color: palette.background,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
                        key: const Key('appearance_preview_active_nav'),
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.home,
                          size: 12,
                          color: palette.onAccent,
                        ),
                      ),
                      for (final icon in [
                        Icons.bookmark_border,
                        Icons.explore_outlined,
                        Icons.newspaper_outlined,
                        Icons.person_outline,
                      ])
                        Icon(icon, size: 12, color: palette.textMuted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _heading(String title, {bool action = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 9),
    child: Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.text,
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        if (action) ...[
          const Spacer(),
          Icon(Icons.arrow_forward, size: 10, color: palette.textMuted),
        ],
      ],
    ),
  );

  Widget _covers({required bool first}) => SizedBox(
    height: first ? 108 : 74,
    child: ClipRect(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 9),
          for (var i = 0; i < 3; i++) ...[
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: first && i == 0
                        ? const Key('appearance_preview_cover')
                        : null,
                    width: 44,
                    height: 66,
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  if (first) ...[
                    const SizedBox(height: 5),
                    Container(
                      height: 3,
                      width: i == 1 ? 34 : 41,
                      color: palette.text,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        RatingStar(
                          surface: palette.background,
                          icon: Icons.star,
                          size: 7,
                        ),
                        const SizedBox(width: 2),
                        Container(
                          height: 2,
                          width: 11,
                          color: palette.textMuted,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 5),
          ],
        ],
      ),
    ),
  );
}
