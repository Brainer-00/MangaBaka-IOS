import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/series/models/series_link.dart';

void main() {
  group('SeriesLink', () {
    test('fromJson parses all fields', () {
      final l = SeriesLink.fromJson({
        'id': 'x',
        'url': 'https://x',
        'name': 'site',
        'name_display': 'Site',
        'type': 'official',
        'language': 'en',
      });
      expect(l.id, 'x');
      expect(l.url, 'https://x');
      expect(l.name, 'site');
      expect(l.nameDisplay, 'Site');
      expect(l.type, 'official');
      expect(l.language, 'en');
    });

    test('fromJson defaults missing required strings to empty', () {
      final l = SeriesLink.fromJson({});
      expect(l.id, '');
      expect(l.url, '');
      expect(l.name, '');
      expect(l.nameDisplay, '');
      expect(l.type, '');
      expect(l.language, isNull);
    });
  });
}
