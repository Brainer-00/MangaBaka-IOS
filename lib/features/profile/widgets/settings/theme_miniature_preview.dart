import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/theme/eirenyu_palette.dart';

/// A static app-shaped sample of the exact colors a preset will apply.
class ThemeMiniaturePreview extends StatelessWidget {
  const ThemeMiniaturePreview({super.key, required this.palette});

  final MbPalette palette;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        key: const Key('appearance_preview_background'),
        height: 164,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('appearance_preview_header'),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: palette.surface,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'EIRENYU',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const Key('appearance_preview_search'),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        color: palette.surfaceRaised,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: palette.border),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Search',
                        style: TextStyle(color: palette.textMuted, fontSize: 8),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      key: const Key('appearance_preview_accent'),
                      height: 17,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Explore',
                          style: TextStyle(
                            color: palette.onAccent,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Expanded(
                      child: Container(
                        key: const Key('appearance_preview_card'),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          children: [
                            for (var index = 0; index < 3; index++) ...[
                              if (index > 0) const SizedBox(width: 5),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: palette.surfaceRaised,
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Container(height: 3, color: palette.text),
                                    const SizedBox(height: 2),
                                    Container(
                                      height: 2,
                                      color: palette.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              key: const Key('appearance_preview_navigation'),
              height: 20,
              color: palette.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    width: 17,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  for (var index = 0; index < 2; index++)
                    Container(
                      width: 12,
                      height: 3,
                      decoration: BoxDecoration(
                        color: palette.textMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
