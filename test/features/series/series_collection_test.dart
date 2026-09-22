import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/series/models/series_collection.dart';

void main() {
  group('SeriesCollection', () {
    test('fromJson parses all fields', () {
      final c = SeriesCollection.fromJson({
        'id': 7,
        'title': 'Vol 1',
        'format': 'tank',
        'type': 'main',
        'status': 'completed',
        'medium': 'print',
        'publisher': {'name': 'Shueisha'},
        'edition': {'name': 'JP'},
        'count_main': 12,
      });
      expect(c.id, '7');
      expect(c.title, 'Vol 1');
      expect(c.format, 'tank');
      expect(c.type, 'main');
      expect(c.status, 'completed');
      expect(c.medium, 'print');
      expect(c.publisherName, 'Shueisha');
      expect(c.editionName, 'JP');
      expect(c.countMain, 12);
    });

    test('fromJson defaults nested fields to empty', () {
      final c = SeriesCollection.fromJson({'id': 1});
      expect(c.publisherName, '');
      expect(c.editionName, '');
      expect(c.countMain, 0);
    });
  });
}
