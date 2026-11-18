# EirenYu emblem

`EirenYu_Emblem_Layered.svg` is a vector-traced reconstruction of the approved
2D concept. Its `symbol` and `dot` are independent layers on a shared
1254 × 1254 canvas. The contours follow the supplied trace.

- `runtime/symbol_512.png` and `runtime/dot_512.png` are the supplied,
  aligned 512 px layers. Flutter tints the symbol to Crimson Moon
  (`#A82F4F`) by default, keeps the dot `#F7F8FC`, and backs both with
  Obsidian (`#0B0B10`). These two masks are the bundled Flutter assets.
- `app_icon_1024.png` is the supplied opaque iOS icon master. Its square
  Obsidian canvas extends to every edge so iOS can apply the icon shape.
- `launch_neutral_1254.png` retains the supplied neutral gray artwork and
  transparent canvas. The supplied white-dot region was cleared for the
  zero-progress frame. It is disjoint from the symbol.
- `launch_splash.png` is the generated transparent input for
  `flutter_native_splash`. The generator scales and centers the full
  shared canvas to approximately 223 logical points, leaving the emblem
  approximately 160 points tall. The native launch background is Obsidian.

To reproduce the checked-in iOS outputs, run the workflow commands from the
repository root in this order:

```sh
dart run flutter_launcher_icons
dart run tool/generate_splash_asset.dart
dart run flutter_native_splash:create
dart run tool/generate_splash_asset.dart --style-storyboard
```

For the future launch reveal, place both layers in the same centered
coordinate space. One upward-moving clip must reveal the symbol and then
the still-white dot as it passes through the dot's own bounds. Keep the
dot invisible at zero progress so the first Flutter frame can match the
native launch artwork.
