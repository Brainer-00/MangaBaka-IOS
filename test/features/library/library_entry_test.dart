import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';

void main() {
  group('LibraryEntry', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': '123',
        'state': 'reading',
        'rating': 9,
        'progress_chapter': 10,
        'series': {
          'id': 'series1',
          'title': 'Test Series',
          'native_title': '',
          'romanized_title': '',
          'secondary_titles': {},
          'cover_url': 'url',
          'authors': [],
          'artists': [],
          'description': 'desc',
          'year': '2021',
          'status': 'ongoing',
          'is_licensed': true,
          'has_anime': false,
          'content_rating': 'safe',
          'type': 'manga',
          'rating': '90',
          'final_volume': '',
          'total_chapters': '100',
          'links': [],
          'publishers': [],
          'genres': [],
          'tags': [],
          'last_updated_at': '',
        }
      };

      final entry = LibraryEntry.fromJson(json);

      expect(entry.id, '123');
      expect(entry.state, 'reading');
      expect(entry.rating, 9);
      expect(entry.progressChapter, 10);
      expect(entry.series.title, 'Test Series');
    });

    test('fromJson throws FormatException when series is missing', () {
      final json = {
        'id': '123',
        'state': 'reading',
      };

      expect(() => LibraryEntry.fromJson(json), throwsA(isA<FormatException>()));
    });
  });
}
