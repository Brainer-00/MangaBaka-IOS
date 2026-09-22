import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/browse/models/genre.dart';

void main() {
  group('Genre', () {
    test('fromJson parses label and value', () {
      final g = Genre.fromJson({'label': 'Action', 'value': 'action'});
      expect(g.label, 'Action');
      expect(g.value, 'action');
    });

    test('fromJson defaults missing fields to empty string', () {
      final g = Genre.fromJson({});
      expect(g.label, '');
      expect(g.value, '');
    });

    test('constructor stores provided values', () {
      final g = Genre(label: 'Drama', value: 'drama');
      expect(g.label, 'Drama');
      expect(g.value, 'drama');
    });
  });
}
