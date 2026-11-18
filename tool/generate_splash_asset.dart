import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

const _canvasSize = 1254;
const _nativeLogicalCanvasSize = 313;
const _targetVisibleArtworkSize = 160;

void main(List<String> args) {
  if (args.length == 1 && args.single == '--style-storyboard') {
    _styleLaunchStoryboard();
    return;
  }
  if (args.isNotEmpty) {
    throw ArgumentError('Expected no arguments or --style-storyboard.');
  }

  const sourcePath = 'assets/branding/eirenyu/launch_neutral_1254.png';
  const outputPath = 'assets/branding/eirenyu/launch_splash.png';

  final source = image.decodePng(File(sourcePath).readAsBytesSync());
  if (source == null) {
    throw StateError('Unable to decode $sourcePath');
  }
  if (source.width != _canvasSize || source.height != _canvasSize) {
    throw StateError(
      '$sourcePath must be $_canvasSize x $_canvasSize, got '
      '${source.width} x ${source.height}',
    );
  }

  final sourceBounds = _alphaBounds(source);
  final sourceMaxDimension = math.max(sourceBounds.width, sourceBounds.height);
  final targetSourceDimension =
      (_targetVisibleArtworkSize * _canvasSize / _nativeLogicalCanvasSize)
          .round();
  final scale = targetSourceDimension / sourceMaxDimension;
  final resizedCanvasSize = (_canvasSize * scale).round();

  // Center the shared canvas so Flutter can match the native launch geometry.
  final resized = image.copyResize(
    source,
    width: resizedCanvasSize,
    height: resizedCanvasSize,
    interpolation: image.Interpolation.cubic,
  );
  final canvas = image.Image(
    width: _canvasSize,
    height: _canvasSize,
    numChannels: 4,
  );
  image.compositeImage(canvas, resized, center: true);

  File(outputPath).writeAsBytesSync(image.encodePng(canvas, level: 9));

  final outputBounds = _alphaBounds(canvas);
  stdout
    ..writeln(
      'Source alpha bounds: '
      '${sourceBounds.left},${sourceBounds.top} '
      '${sourceBounds.width}x${sourceBounds.height}',
    )
    ..writeln(
      'Output alpha bounds: '
      '${outputBounds.left},${outputBounds.top} '
      '${outputBounds.width}x${outputBounds.height}',
    )
    ..writeln(
      'Expected native visible size: '
      '${outputBounds.width * _nativeLogicalCanvasSize / _canvasSize}x'
      '${outputBounds.height * _nativeLogicalCanvasSize / _canvasSize}',
    );
}

void _styleLaunchStoryboard() {
  // flutter_native_splash rewrites this fallback to white on every run.
  final file = File('ios/Runner/Base.lproj/LaunchScreen.storyboard');
  final source = file.readAsStringSync();
  final background = RegExp(
    r'<color key="backgroundColor"[^>]*/>',
  ).allMatches(source).single;
  const obsidian =
      '<color key="backgroundColor" red="0.043137254901960784" '
      'green="0.043137254901960784" blue="0.062745098039215686" '
      'alpha="1" colorSpace="custom" customColorSpace="sRGB"/>';
  if (background[0] == obsidian) return;
  file.writeAsStringSync(
    source.replaceRange(background.start, background.end, obsidian),
  );
}

_Bounds _alphaBounds(image.Image source) {
  var left = source.width;
  var top = source.height;
  var right = -1;
  var bottom = -1;

  for (final pixel in source) {
    if (pixel.a == 0) continue;
    final x = pixel.x.toInt();
    final y = pixel.y.toInt();
    left = math.min(left, x);
    top = math.min(top, y);
    right = math.max(right, x);
    bottom = math.max(bottom, y);
  }

  if (right < left || bottom < top) {
    throw StateError('Image contains no visible pixels');
  }

  return _Bounds(left, top, right - left + 1, bottom - top + 1);
}

class _Bounds {
  const _Bounds(this.left, this.top, this.width, this.height);

  final int left;
  final int top;
  final int width;
  final int height;
}
