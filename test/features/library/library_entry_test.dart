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
        },
      };

      final entry = LibraryEntry.fromJson(json);

      expect(entry.id, '123');
      expect(entry.state, 'reading');
      expect(entry.rating, 9);
      expect(entry.progressChapter, 10);
      expect(entry.series.title, 'Test Series');
      expect(entry.listIds, isNull);
      expect(entry.explicitlyClears('progress_volume'), isFalse);
    });

    test('parses a paginated v1 item without flattening nullable values', () {
      final entry = LibraryEntry.fromJson({
        'id': 123,
        'state': 'reading',
        'rating': null,
        'priority': 20,
        'start_date': '2024-02-29T00:00:00.000Z',
        'finish_date': '2024-03-01',
        'is_private': false,
        'read_link': 'https://example.com/read',
        'Series': {'id': 1, 'title': 'Test Series'},
      });
      expect(entry.id, '123');
      expect(entry.series.id, '1');
      expect(entry.startDate, '2024-02-29');
      expect(entry.finishDate, '2024-03-01');
      expect(entry.rating, isNull);
      expect(entry.explicitlyClears('rating'), isTrue);
      expect(entry.note, isNull);
      expect(entry.explicitlyClears('note'), isFalse);
      expect(entry.priority, 20);
      expect(entry.isPrivate, isFalse);
      expect(entry.readLink, 'https://example.com/read');
      expect(entry.listIds, isNull);
    });

    test('rejects dates that would otherwise roll into the next month', () {
      expect(
        () => LibraryEntry.fromJson({
          'start_date': '2023-02-29',
          'Series': {'id': 1, 'title': 'Test Series'},
        }),
        throwsFormatException,
      );
    });

    test('fromJson throws FormatException when series is missing', () {
      final json = {'id': '123', 'state': 'reading'};

      expect(
        () => LibraryEntry.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
