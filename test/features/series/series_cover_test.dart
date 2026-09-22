import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/series/models/series_cover.dart';

void main() {
  group('SeriesCover', () {
    test('fromJson extracts urls from each size variant', () {
      final c = SeriesCover.fromJson({
        'type': 'cover',
        'language': 'jp',
        'index': '1',
        'image': {
          'raw': {'url': 'raw.png'},
          'x150': {'x1': '150.png'},
          'x250': {'x1': '250.png'},
          'x350': {'x1': '350.png'},
        },
      });
      expect(c.type, 'cover');
      expect(c.language, 'jp');
      expect(c.index, '1');
      expect(c.url, 'raw.png');
      expect(c.urlX150, '150.png');
      expect(c.urlX250, '250.png');
      expect(c.urlX350, '350.png');
    });

    test('fromJson returns nulls when image is missing', () {
      final c = SeriesCover.fromJson({'type': 'cover'});
      expect(c.url, isNull);
      expect(c.urlX150, isNull);
      expect(c.urlX250, isNull);
      expect(c.urlX350, isNull);
    });

    test('fromJson defaults string fields to empty', () {
      final c = SeriesCover.fromJson({});
      expect(c.type, '');
      expect(c.language, '');
      expect(c.index, '');
      expect(c.note, isNull);
    });
  });
}
