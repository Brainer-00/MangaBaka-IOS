import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangabaka_app/features/library/import/import_parser.dart';
import 'package:mangabaka_app/features/library/import/import_sources.dart';

List<int> _varint(int v) {
  final out = <int>[];
  while (v > 0x7f) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> _lengthDelimited(int field, List<int> payload) => [
  ..._varint(field << 3 | 2),
  ..._varint(payload.length),
  ...payload,
];

/// A BackupManga with a source (varint), url and title, like Mihon writes.
List<int> _manga(String title) => [
  ..._varint(1 << 3),
  ..._varint(2499283573021220255 & 0xffffff),
  ..._lengthDelimited(2, utf8.encode('/manga/x')),
  ..._lengthDelimited(3, utf8.encode(title)),
];

Uint8List _backup(List<String> titles) => Uint8List.fromList([
  for (final t in titles) ..._lengthDelimited(1, _manga(t)),
  // A field a reader has never heard of, which must be skipped.
  ..._lengthDelimited(101, utf8.encode('categories')),
]);

Uint8List _gzipRepeatedByte(int byte, int count) {
  final compressed = BytesBuilder(copy: false);
  final encoder = gzip.encoder.startChunkedConversion(
    ByteConversionSink.withCallback(compressed.add),
  );
  final chunk = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, byte);
  var remaining = count;
  while (remaining > 0) {
    final length = remaining < chunk.length ? remaining : chunk.length;
    encoder.add(
      length == chunk.length ? chunk : Uint8List.sublistView(chunk, 0, length),
    );
    remaining -= length;
  }
  encoder.close();
  return compressed.takeBytes();
}

void main() {
  group('ImportFileReader', () {
    test('plain text passes through', () {
      expect(
        ImportFileReader.readText(Uint8List.fromList(utf8.encode('A\nB'))),
        'A\nB',
      );
    });

    test('a gzipped MyAnimeList export is unwrapped', () {
      const xml =
          '<myanimelist><manga><manga_title>A</manga_title></manga></myanimelist>';
      final text = ImportFileReader.readText(
        Uint8List.fromList(gzip.encode(utf8.encode(xml))),
      );
      expect(text, xml);
      expect(ImportParser.parse(text).map((e) => e.title), ['A']);
    });

    test('a Mihon backup yields its titles, gzipped or not', () {
      final backup = _backup(['Frieren', 'Berserk 日本']);
      expect(ImportFileReader.readText(backup), 'Frieren\nBerserk 日本');
      expect(
        ImportFileReader.readText(Uint8List.fromList(gzip.encode(backup))),
        'Frieren\nBerserk 日本',
      );
    });

    test('unreadable binary is refused rather than imported as junk', () {
      expect(
        () => ImportFileReader.readText(
          Uint8List.fromList([0xff, 0xfe, 0x00, 0x01, 0x02]),
        ),
        throwsA(isA<ImportSourceException>()),
      );
    });

    test('rejects a source larger than the input limit', () {
      final oversized = Uint8List(ImportFileReader.maxSourceBytes + 1);

      expect(
        () => ImportFileReader.readText(oversized),
        throwsA(
          isA<ImportSourceException>().having(
            (e) => e.key,
            'key',
            'import_file_failed',
          ),
        ),
      );
    });

    test('rejects gzip output larger than the decompression limit', () {
      final compressed = _gzipRepeatedByte(
        0x41,
        ImportFileReader.maxDecompressedBytes + 1,
      );

      expect(compressed.length, lessThan(ImportFileReader.maxSourceBytes));
      expect(
        () => ImportFileReader.readText(compressed),
        throwsA(
          isA<ImportSourceException>().having(
            (e) => e.key,
            'key',
            'import_file_failed',
          ),
        ),
      );
    });

    test('rejects invalid or truncated gzip data', () {
      final valid = gzip.encode(utf8.encode('truncated'));
      for (final data in [
        Uint8List.fromList([0x1f, 0x8b, 0x08, 0x00]),
        Uint8List.fromList(valid.sublist(0, valid.length - 1)),
      ]) {
        expect(
          () => ImportFileReader.readText(data),
          throwsA(isA<ImportSourceException>()),
        );
      }
    });

    test('rejects gzip data with a corrupted CRC trailer', () {
      final corrupted = Uint8List.fromList(
        gzip.encode(utf8.encode('checksum protected')),
      );
      corrupted[corrupted.length - 8] ^= 0xff;

      expect(
        () => ImportFileReader.readText(corrupted),
        throwsA(
          isA<ImportSourceException>().having(
            (error) => error.key,
            'key',
            'import_file_failed',
          ),
        ),
      );
    });

    test('rejects gzip data with a corrupted ISIZE trailer', () {
      final corrupted = Uint8List.fromList(
        gzip.encode(utf8.encode('length protected')),
      );
      corrupted[corrupted.length - 4] ^= 0xff;

      expect(
        () => ImportFileReader.readText(corrupted),
        throwsA(
          isA<ImportSourceException>().having(
            (error) => error.key,
            'key',
            'import_file_failed',
          ),
        ),
      );
    });

    test('accepts concatenated gzip members', () {
      final first = gzip.encode(utf8.encode('first'));
      final second = gzip.encode(utf8.encode('second'));
      final concatenated = Uint8List.fromList([...first, ...second]);

      expect(ImportFileReader.readText(concatenated), 'firstsecond');
    });

    test('truncated fixed64 protobuf input fails safely', () {
      expect(
        () => ImportFileReader.readText(
          Uint8List.fromList([1 << 3 | 1, 0x00, 0x01]),
        ),
        throwsA(isA<ImportSourceException>()),
      );
    });

    test('truncated fixed32 protobuf input fails safely', () {
      expect(
        () => ImportFileReader.readText(
          Uint8List.fromList([1 << 3 | 5, 0x00, 0x01]),
        ),
        throwsA(isA<ImportSourceException>()),
      );
    });
  });

  group('AniListImporter', () {
    const body = '''
{"data": {"MediaListCollection": {"lists": [
  {"entries": [
    {"status": "CURRENT", "media": {"title": {"romaji": "Sousou no Frieren", "english": "Frieren"}}},
    {"status": "PLANNING", "media": {"title": {"romaji": null, "english": "Berserk"}}}
  ]},
  {"entries": [
    {"status": "PAUSED", "media": {"title": {"romaji": "Monster", "english": null}}}
  ]}
]}}}''';

    test('turns entries into importer JSON that the parser maps', () {
      final entries = ImportParser.parse(AniListImporter.entriesJson(body));
      expect(entries, const [
        ImportEntry('Sousou no Frieren', state: 'reading'),
        ImportEntry('Berserk', state: 'plan_to_read'),
        ImportEntry('Monster', state: 'paused'),
      ]);
    });

    test('an unknown user is reported as such', () {
      expect(
        () => AniListImporter.entriesJson('{"data": null, "errors": []}'),
        throwsA(
          isA<ImportSourceException>().having(
            (e) => e.key,
            'key',
            'import_user_not_found',
          ),
        ),
      );
    });

    test('fetch posts the username and returns the entries', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(body, 200);
      });
      final json = await AniListImporter(client: client).fetch('  someone ');
      expect((sent['variables'] as Map)['user'], 'someone');
      expect(ImportParser.parse(json), hasLength(3));
    });

    test('a missing user and a dead server are told apart', () async {
      Future<String> key(int status) async {
        final importer = AniListImporter(
          client: MockClient((_) async => http.Response('{}', status)),
        );
        try {
          await importer.fetch('x');
        } on ImportSourceException catch (e) {
          return e.key;
        }
        return '';
      }

      expect(await key(404), 'import_user_not_found');
      expect(await key(500), 'import_source_unreachable');
    });
  });
}
