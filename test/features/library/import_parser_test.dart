import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/library/import/import_parser.dart';

void main() {
  group('detect', () {
    test('a plain list stays plain, even with commas or brackets in titles', () {
      expect(ImportParser.detect('Frieren\nBerserk'), ImportFormat.plain);
      expect(
        ImportParser.detect('Oshi no Ko, Vol. 1\nBerserk'),
        ImportFormat.plain,
      );
      // A title that merely starts like JSON is still a title.
      expect(ImportParser.detect('[Oshi no Ko]\nBerserk'), ImportFormat.plain);
    });

    test('recognises each structured format', () {
      expect(
        ImportParser.detect('<myanimelist><manga></manga></myanimelist>'),
        ImportFormat.myAnimeList,
      );
      expect(ImportParser.detect('["A", "B"]'), ImportFormat.json);
      expect(ImportParser.detect('title,status\nA,Reading'), ImportFormat.csv);
    });
  });

  group('plain', () {
    test('strips list markers, blanks and repeats', () {
      final entries = ImportParser.parse(
        '1. Frieren\r\n- One Piece\n\n* Berserk\n2) frieren\n  Monster  \n',
      );
      expect(entries.map((e) => e.title), [
        'Frieren',
        'One Piece',
        'Berserk',
        'Monster',
      ]);
      expect(entries.every((e) => e.state == null), isTrue);
    });

    test('caps the list length', () {
      final text = List.generate(500, (i) => 'Title $i').join('\n');
      expect(ImportParser.parse(text), hasLength(ImportParser.maxTitles));
    });
  });

  group('csv', () {
    test('reads the title and status columns by header name', () {
      final entries = ImportParser.parse(
        'id,Title,Status\n'
        '1,"Berserk, Deluxe",Reading\n'
        '2,Frieren,Plan to Read\n'
        '3,Monster,Something Odd\n',
      );
      expect(entries, const [
        ImportEntry('Berserk, Deluxe', state: 'reading'),
        ImportEntry('Frieren', state: 'plan_to_read'),
        // An unknown status is no status: the row takes the chosen state.
        ImportEntry('Monster'),
      ]);
    });

    test('unescapes doubled quotes', () {
      final entries = ImportParser.parse(
        'title\n"He said ""hi"""\n',
        format: ImportFormat.csv,
      );
      expect(entries.single.title, 'He said "hi"');
    });

    test('with no header, the first column is the title', () {
      final entries = ImportParser.parse(
        'Frieren,x\nBerserk,y',
        format: ImportFormat.csv,
      );
      expect(entries.map((e) => e.title), ['Frieren', 'Berserk']);
    });
  });

  group('json', () {
    test('accepts an array of strings', () {
      expect(
        ImportParser.parse('["Frieren", "Berserk"]').map((e) => e.title),
        ['Frieren', 'Berserk'],
      );
    });

    test('accepts objects, and an object wrapping the array', () {
      final entries = ImportParser.parse(
        '{"list": [{"title": "Frieren", "status": "current"},'
        ' {"name": "Berserk", "status": "COMPLETED"}, {"nope": 1}]}',
      );
      expect(entries, const [
        ImportEntry('Frieren', state: 'reading'),
        ImportEntry('Berserk', state: 'completed'),
      ]);
    });

    test('broken JSON yields nothing rather than throwing', () {
      expect(ImportParser.parse('["A", ', format: ImportFormat.json), isEmpty);
    });
  });

  group('myAnimeList', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
  <myinfo><user_name>x</user_name></myinfo>
  <manga>
    <manga_mangadb_id>1</manga_mangadb_id>
    <manga_title><![CDATA[Berserk & Co]]></manga_title>
    <my_status>Reading</my_status>
  </manga>
  <manga>
    <manga_title>Frieren &amp; Friends</manga_title>
    <my_status>On-Hold</my_status>
  </manga>
  <manga>
    <manga_title>Monster</manga_title>
  </manga>
</myanimelist>''';

    test('reads titles and maps statuses', () {
      expect(ImportParser.parse(xml), const [
        ImportEntry('Berserk & Co', state: 'reading'),
        ImportEntry('Frieren & Friends', state: 'paused'),
        ImportEntry('Monster'),
      ]);
    });

    test('drops the statuses when they are not wanted', () {
      final entries = ImportParser.parse(xml, useStates: false);
      expect(entries.every((e) => e.state == null), isTrue);
      expect(entries, hasLength(3));
    });
  });

  group('mapStatus', () {
    test('accepts the spellings other trackers use', () {
      expect(ImportParser.mapStatus('Plan to Read'), 'plan_to_read');
      expect(ImportParser.mapStatus('plan-to-read'), 'plan_to_read');
      expect(ImportParser.mapStatus('PLANNING'), 'plan_to_read');
      expect(ImportParser.mapStatus('On Hold'), 'paused');
      expect(ImportParser.mapStatus('Dropped'), 'dropped');
      expect(ImportParser.mapStatus('Re-reading'), 'rereading');
      expect(ImportParser.mapStatus('gibberish'), isNull);
    });
  });

  group('detect extended', () {
    test('recognises MangaBaka and MangaUpdates formats', () {
      expect(
        ImportParser.detect(
          '{"schema_version": 2, "entries": []}',
        ),
        ImportFormat.mangaBaka,
      );
      expect(
        ImportParser.detect(
          '[{"entry": {"state": "reading"}, "titles": {"primary": "Berserk"}}]',
        ),
        ImportFormat.mangaBaka,
      );
      expect(
        ImportParser.detect(
          '[{"id": 123, "title": "Berserk", "volume": 1}]',
        ),
        ImportFormat.mangaUpdates,
      );
    });
  });

  group('mangaUpdates', () {
    const muJson =
        '[{"id": 101, "title": "Berserk", "volume": 41, "chapter": 364},'
        ' {"id": 102, "title": "Frieren", "rating": 10}]';

    test('parses titles and maps state from filename tag', () {
      final readingEntries = ImportParser.parse(
        muJson,
        fileName: 'export_id0_reading.json',
      );
      expect(readingEntries, const [
        ImportEntry('Berserk', state: 'reading'),
        ImportEntry('Frieren', state: 'reading'),
      ]);

      final completedEntries = ImportParser.parse(
        muJson,
        fileName: 'mangaupdates_id2_.json',
      );
      expect(completedEntries, const [
        ImportEntry('Berserk', state: 'completed'),
        ImportEntry('Frieren', state: 'completed'),
      ]);
    });

    test('ignores state if useStates is false or filename has no tag', () {
      final noTag = ImportParser.parse(muJson, fileName: 'export.json');
      expect(noTag.every((e) => e.state == null), isTrue);

      final noStates = ImportParser.parse(
        muJson,
        fileName: 'export_id0_.json',
        useStates: false,
      );
      expect(noStates.every((e) => e.state == null), isTrue);
    });
  });

  group('mangaBaka', () {
    test('parses v1 backup format', () {
      const v1Json = '''
[
  {
    "entry": {"state": "reading", "progress": 50},
    "titles": {"primary": "Berserk", "english": "Berserk"}
  },
  {
    "entry": {"state": "completed"},
    "titles": {"primary": "Monster"}
  }
]
''';
      final entries = ImportParser.parse(v1Json);
      expect(entries, const [
        ImportEntry('Berserk', state: 'reading'),
        ImportEntry('Monster', state: 'completed'),
      ]);
    });

    test('parses v2 backup format', () {
      const v2Json = '''
{
  "schema_version": 2,
  "entries": [
    {
      "entry": {"state": "plan_to_read"},
      "titles": {"primary": "Sousou no Frieren", "romaji": "Sousou no Frieren"}
    },
    {
      "entry": {"state": "dropped"},
      "title": "Chainsaw Man"
    }
  ]
}
''';
      final entries = ImportParser.parse(v2Json);
      expect(entries, const [
        ImportEntry('Sousou no Frieren', state: 'plan_to_read'),
        ImportEntry('Chainsaw Man', state: 'dropped'),
      ]);
    });

    test('disables states when useStates is false', () {
      const v2Json = '''
{
  "schema_version": 2,
  "entries": [
    {
      "entry": {"state": "plan_to_read"},
      "titles": {"primary": "Sousou no Frieren"}
    }
  ]
}
''';
      final entries = ImportParser.parse(v2Json, useStates: false);
      expect(entries, const [
        ImportEntry('Sousou no Frieren'),
      ]);
    });
  });
}
