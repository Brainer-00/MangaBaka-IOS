import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:mangabaka_app/core/theme/ios_icon_variants.dart';

void main(List<String> args) {
  if (args.isNotEmpty && (args.length != 1 || args.single != '--verify')) {
    throw ArgumentError('Expected no arguments or --verify');
  }
  final verify = args.isNotEmpty;
  const catalog = 'ios/Runner/Assets.xcassets';
  const source = 'assets/branding/eirenyu/app_icon_1024.png';
  final original = image.decodePng(File(source).readAsBytesSync());
  if (original == null || original.width != 1024 || original.height != 1024) {
    throw StateError('Expected the canonical 1024px icon');
  }
  final contents =
      jsonDecode(
            File(
              '$catalog/AppIcon.appiconset/Contents.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final entries = (contents['images'] as List).cast<Map<String, dynamic>>();
  const background = [11, 11, 16];
  const crimson = [168, 47, 79];
  for (final (argb, name) in iosIconVariants) {
    if (name == null) continue;
    final output = image.Image(width: 1024, height: 1024, numChannels: 3);
    final target = [(argb >> 16) & 255, (argb >> 8) & 255, argb & 255];
    for (var y = 0; y < 1024; y++) {
      for (var x = 0; x < 1024; x++) {
        final pixel = original.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        // The canonical white dot occupies this isolated region. Preserve
        // its antialiased edge as well as its opaque center.
        if (x >= 660 && x <= 770 && y >= 390 && y <= 505) {
          output.setPixelRgb(x, y, r, g, b);
          continue;
        }
        final coverage = ((r - background[0]) / (crimson[0] - background[0]))
            .clamp(0.0, 1.0);
        output.setPixelRgb(
          x,
          y,
          (background[0] + (target[0] - background[0]) * coverage).round(),
          (background[1] + (target[1] - background[1]) * coverage).round(),
          (background[2] + (target[2] - background[2]) * coverage).round(),
        );
      }
    }
    final directory = Directory('$catalog/$name.appiconset');
    if (!verify) directory.createSync();
    for (final entry in entries) {
      final filename = entry['filename'] as String;
      final size = double.parse((entry['size'] as String).split('x').first);
      final scale = int.parse((entry['scale'] as String).replaceAll('x', ''));
      final width = (size * scale).round();
      final scaled = width == 1024
          ? output
          : image.copyResize(output, width: width);
      final file = File('${directory.path}/$filename');
      final bytes = image.encodePng(scaled, level: 9);
      if (verify) {
        if (!file.existsSync()) {
          throw StateError('Unexpected icon asset: ${file.path}');
        }
        final saved = file.readAsBytesSync();
        final decoded = image.decodePng(saved);
        if (saved[25] != 2 ||
            decoded == null ||
            decoded.width != width ||
            decoded.height != width ||
            decoded.numChannels != 3 ||
            !_sameBytes(saved, bytes)) {
          throw StateError('Invalid RGB icon asset: ${file.path}');
        }
      } else {
        file.writeAsBytesSync(bytes);
      }
    }
    final manifest = File('${directory.path}/Contents.json');
    if (verify) {
      if (!manifest.existsSync() ||
          manifest.readAsStringSync() != jsonEncode(contents)) {
        throw StateError('Unexpected icon manifest: ${manifest.path}');
      }
    } else {
      manifest.writeAsStringSync(jsonEncode(contents));
    }
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
