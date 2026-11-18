import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _brand = 'assets/branding/eirenyu';
const _catalog = 'ios/Runner/Assets.xcassets';

img.Image _png(String path) => img.decodePng(File(path).readAsBytesSync())!;

List<num> _rgba(img.Pixel pixel) => [pixel.r, pixel.g, pixel.b, pixel.a];

Iterable<String> _catalogFiles(String path) sync* {
  final catalog = jsonDecode(File('$path/Contents.json').readAsStringSync());
  for (final entry in catalog['images'] as List) {
    if (entry['filename'] case final String name) yield '$path/$name';
  }
}

void main() {
  test('icon master and generated icons are opaque on Obsidian', () {
    final master = _png('$_brand/app_icon_1024.png');
    expect((master.width, master.height), (1024, 1024));
    expect(_rgba(master.getPixel(512, 512)), [168, 47, 79, 255]);
    expect(_rgba(master.getPixel(715, 446)), [247, 248, 252, 255]);
    expect(_rgba(master.getPixel(0, 0)), [11, 11, 16, 255]);
    expect(master.every((pixel) => pixel.a == 255), isTrue);

    final catalog = _catalogFiles('$_catalog/AppIcon.appiconset');
    expect(catalog, isNotEmpty);
    // The generator's average resize can round the blue channel down by one.
    final obsidian = orderedEquals([11, 11, closeTo(16, 1), 255]);
    for (final path in catalog) {
      final icon = _png(path);
      final spec = RegExp(
        r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$',
      ).firstMatch(path)!;
      final side = (double.parse(spec[1]!) * int.parse(spec[2]!)).round();
      expect((icon.width, icon.height), (side, side), reason: path);
      expect(icon.every((pixel) => pixel.a == 255), isTrue, reason: path);
      expect(_rgba(icon.getPixel(0, 0)), obsidian, reason: path);
      expect(
        _rgba(icon.getPixel(icon.width - 1, icon.height - 1)),
        obsidian,
        reason: path,
      );
    }
  });

  test('runtime layers share a transparent canvas with a fixed white dot', () {
    final symbol = _png('$_brand/runtime/symbol_512.png');
    final dot = _png('$_brand/runtime/dot_512.png');
    expect((symbol.width, symbol.height), (512, 512));
    expect((dot.width, dot.height), (512, 512));
    expect(symbol.getPixel(0, 0).a, 0);
    expect(symbol.getPixel(256, 256).a, 255);
    expect(symbol.getPixel(357, 223).a, 0);
    expect(dot.getPixel(256, 256).a, 0);
    expect(_rgba(dot.getPixel(357, 223)), [247, 248, 252, 255]);
  });

  test('launch assets have a gray symbol, transparent padding, and no dot', () {
    final native = _catalogFiles('$_catalog/LaunchImage.imageset').toList();
    expect(native, hasLength(3));
    final paths = [
      '$_brand/launch_neutral_1254.png',
      '$_brand/launch_splash.png',
      ...native,
    ];
    final expectedSizes = [1254, 1254, 313, 627, 940];
    for (final (index, path) in paths.indexed) {
      final logo = _png(path);
      expect(
        (logo.width, logo.height),
        (expectedSizes[index], expectedSizes[index]),
      );
      expect(logo.getPixel(0, 0).a, 0, reason: path);
      expect(_rgba(logo.getPixel(logo.width ~/ 2, logo.height ~/ 2)), [
        57,
        56,
        64,
        255,
      ], reason: path);
      expect(
        logo.where((pixel) => pixel.a != 0).every((pixel) => pixel.r < 128),
        isTrue,
        reason: path,
      );
    }
    final background = _catalogFiles('$_catalog/LaunchBackground.imageset');
    expect(_rgba(_png(background.single).getPixel(0, 0)), [11, 11, 16, 255]);
  });

  test(
    'Flutter and the CI generators reference only the active brand inputs',
    () {
      final launcher = File('flutter_launcher_icons.yaml').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final generator = File(
        'tool/generate_splash_asset.dart',
      ).readAsStringSync();
      final workflow = File(
        '.github/workflows/ios-sideload.yml',
      ).readAsStringSync();
      final launchStoryboard = File(
        'ios/Runner/Base.lproj/LaunchScreen.storyboard',
      ).readAsStringSync();

      expect(launcher, contains('image_path: "$_brand/app_icon_1024.png"'));
      expect(pubspec, contains('image: $_brand/launch_splash.png'));
      expect(pubspec, contains('    - $_brand/runtime/'));
      expect(
        generator,
        contains('sourcePath = \'$_brand/launch_neutral_1254.png\''),
      );
      expect(generator, contains('outputPath = \'$_brand/launch_splash.png\''));
      expect(workflow, contains('dart run tool/generate_splash_asset.dart'));
      expect(launchStoryboard, contains('image="LaunchBackground"'));
      expect(launchStoryboard, contains('image="LaunchImage"'));
      expect(
        launchStoryboard,
        contains('color key="backgroundColor" red="0.043'),
      );

      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final sourcesAndConfig = [
        ...sources.map((file) => file.readAsStringSync()),
        launcher,
        pubspec,
        generator,
      ].join('\n');
      expect(sourcesAndConfig, isNot(contains('assets/mangabaka512.png')));
      expect(sourcesAndConfig, isNot(contains('assets/mangabaka_splash.png')));
    },
  );
}
