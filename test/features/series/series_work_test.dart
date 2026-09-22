import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/series/models/series_work.dart';

void main() {
  group('SeriesWork', () {
    test('fromJson parses base fields', () {
      final w = SeriesWork.fromJson({
        'id': 'w1',
        'sub_title': 'Vol 1',
        'count_type': 'volume',
        'release_date': '2020-01-01',
        'sequence_string': '1',
        'pages': 200,
      });
      expect(w.id, 'w1');
      expect(w.subTitle, 'Vol 1');
      expect(w.countType, 'volume');
      expect(w.releaseDate, '2020-01-01');
      expect(w.sequenceString, '1');
      expect(w.pages, 200);
      expect(w.imageUrl, isNull);
      expect(w.priceString, isNull);
    });

    test('fromJson prefers x250 image, falls back to x150 then raw', () {
      final x250 = SeriesWork.fromJson({
        'id': '1',
        'images': [{
          'image': {
            'x150': {'x1': '150.png'},
            'x250': {'x1': '250.png'},
            'raw': {'url': 'raw.png'},
          },
        }],
      });
      expect(x250.imageUrl, '250.png');

      final x150 = SeriesWork.fromJson({
        'id': '1',
        'images': [{'image': {'x150': {'x1': '150.png'}, 'raw': {'url': 'raw.png'}}}],
      });
      expect(x150.imageUrl, '150.png');

      final raw = SeriesWork.fromJson({
        'id': '1',
        'images': [{'image': {'raw': {'url': 'raw.png'}}}],
      });
      expect(raw.imageUrl, 'raw.png');
    });

    test('fromJson formats first price entry uppercased', () {
      final w = SeriesWork.fromJson({
        'id': '1',
        'price': [{'value': '9.99', 'iso_code': 'usd'}],
      });
      expect(w.priceString, '9.99 USD');
    });

    test('fromJson defaults pages to 0 when missing', () {
      final w = SeriesWork.fromJson({'id': '1'});
      expect(w.pages, 0);
    });
  });
}
