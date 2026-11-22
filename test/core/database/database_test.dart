import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:get_it/get_it.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    if (!GetIt.I.isRegistered<LoggingService>()) {
      GetIt.I.registerSingleton<LoggingService>(LoggingService());
    }

    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase', () {
    test('creates the complete v4 schema on a fresh database', () async {
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 4);
      final columns = await db
          .customSelect('PRAGMA table_info(library_entries_table)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        containsAll([
          'priority',
          'start_date',
          'finish_date',
          'read_link',
          'is_private',
          'list_ids_json',
        ]),
      );
    });

    test('upgrades a populated v3 library without losing rows', () async {
      // The series schema is shared by v3 and v4. Use the actual generated
      // schema for it and spell out the old library schema below.
      final seriesSchema = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'series_table'",
          )
          .getSingle();
      final raw = sqlite3.openInMemory();
      raw.execute(seriesSchema.read<String>('sql'));
      raw.execute('''
        CREATE TABLE library_entries_table (
          id TEXT NOT NULL PRIMARY KEY,
          state TEXT NOT NULL,
          note TEXT,
          progress_chapter INTEGER,
          progress_volume INTEGER,
          number_of_rereads INTEGER,
          rating INTEGER,
          series_id TEXT NOT NULL REFERENCES series_table(id)
        );
        INSERT INTO series_table (id, title, cover_url, description) VALUES
          ('1', 'One', 'cover1', 'first'), ('2', 'Two', 'cover2', 'second');
        INSERT INTO library_entries_table VALUES
          ('e1', 'reading', 'keep this note', 12, 3, 2, 86, '1'),
          ('e2', 'completed', NULL, NULL, 0, NULL, NULL, '2');
        PRAGMA user_version = 3;
      ''');
      final upgraded = AppDatabase.forTesting(NativeDatabase.opened(raw));
      addTearDown(upgraded.close);

      final joined = await upgraded.libraryEntriesDao
          .watchAllEntriesWithSeries()
          .first;
      final rows = {for (final row in joined) row.libraryEntry.id: row};
      expect(rows.keys, unorderedEquals(['e1', 'e2']));
      final first = rows['e1']!.libraryEntry;
      expect(rows['e1']!.series.title, 'One');
      expect(rows['e2']!.series.title, 'Two');
      expect(first.seriesId, '1');
      expect(first.state, 'reading');
      expect(first.note, 'keep this note');
      expect(first.progressChapter, 12);
      expect(first.progressVolume, 3);
      expect(first.numberOfRereads, 2);
      expect(first.rating, 86);
      expect(rows['e2']!.libraryEntry.progressVolume, 0);
      expect(rows['e2']!.libraryEntry.rating, isNull);
      expect([
        first.priority,
        first.startDate,
        first.finishDate,
        first.readLink,
        first.isPrivate,
        first.listIdsJson,
      ], everyElement(isNull));
      expect(
        await upgraded.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });

    test('can insert and retrieve a series via custom query', () async {
      // Using custom query to avoid complex api.Series object for basic DAO test
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: '1',
              title: 'Test Manga',
              state: const Value('reading'),
              coverUrl: 'https://example.com/cover.jpg',
              description: 'A test description',
              lastUpdated: Value(DateTime.now().toIso8601String()),
            ),
          );

      final retrieved = await (db.select(
        db.seriesTable,
      )..where((t) => t.id.equals('1'))).getSingleOrNull();
      expect(retrieved, isNotNull);
      expect(retrieved!.title, 'Test Manga');
    });

    test('can insert and retrieve a library entry', () async {
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: '1',
              title: 'Test Manga',
              state: const Value('reading'),
              coverUrl: 'https://example.com/cover.jpg',
              description: 'A test description',
              lastUpdated: Value(DateTime.now().toIso8601String()),
            ),
          );

      await db
          .into(db.libraryEntriesTable)
          .insert(
            LibraryEntriesTableCompanion.insert(
              id: 'entry_1',
              seriesId: '1',
              state: 'plan_to_read',
              progressChapter: const Value(1),
              progressVolume: const Value(0),
            ),
          );

      final retrieved = await (db.select(
        db.libraryEntriesTable,
      )..where((t) => t.seriesId.equals('1'))).getSingleOrNull();
      expect(retrieved, isNotNull);
      expect(retrieved!.state, 'plan_to_read');
    });

    test('self-healing migration ensures tables and indices exist', () async {
      final tableNames = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      final names = tableNames.map((row) => row.read<String>('name')).toList();

      expect(names, contains('series_table'));
      expect(names, contains('library_entries_table'));

      final indexNames = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
          .get();
      final indices = indexNames
          .map((row) => row.read<String>('name'))
          .toList();
      expect(indices, contains('series_title_idx'));
      expect(indices, contains('library_series_idx'));
      expect(indices, contains('library_state_idx'));
    });

    test(
      'robust migration preserves data and adds missing columns/indices when upgrading from v1',
      () async {
        final rawDb = sqlite3.openInMemory();

        // Create v1 schema
        rawDb.execute('''
        CREATE TABLE series_table (
          id TEXT PRIMARY KEY,
          title TEXT,
          cover_url TEXT,
          description TEXT
        );
      ''');
        rawDb.execute('''
        CREATE TABLE library_entries_table (
          id TEXT PRIMARY KEY,
          series_id TEXT,
          state TEXT
        );
      ''');

        // Insert mock data
        rawDb.execute('''
        INSERT INTO series_table (id, title, cover_url, description)
        VALUES ('1', 'Series 1', 'https://example.com/1.jpg', 'Desc 1');
      ''');
        rawDb.execute('''
        INSERT INTO library_entries_table (id, series_id, state)
        VALUES ('entry_1', '1', 'reading');
      ''');

        // Set user_version to 1 to simulate a v1 database
        rawDb.execute('PRAGMA user_version = 1;');

        // Wrap it in Drift NativeDatabase
        final upgradeDb = AppDatabase.forTesting(NativeDatabase.opened(rawDb));

        expect(upgradeDb.schemaVersion, 4);

        // Let's verify our v1 data is still there!
        final retrievedSeries = await (upgradeDb.select(
          upgradeDb.seriesTable,
        )..where((t) => t.id.equals('1'))).getSingle();
        expect(retrievedSeries.title, 'Series 1');
        expect(retrievedSeries.coverUrl, 'https://example.com/1.jpg');
        expect(retrievedSeries.description, 'Desc 1');

        // Verify new columns exist and have correct defaults/nullability
        expect(retrievedSeries.mergedWith, isNull);
        expect(retrievedSeries.secondaryTitles, '[]'); // default value

        final retrievedEntry = await (upgradeDb.select(
          upgradeDb.libraryEntriesTable,
        )..where((t) => t.id.equals('entry_1'))).getSingle();
        expect(retrievedEntry.state, 'reading');
        expect(
          retrievedEntry.progressChapter,
          isNull,
        ); // newly added column, should be null

        // Verify indices were created
        final indexNames = await upgradeDb
            .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
            .get();
        final indices = indexNames
            .map((row) => row.read<String>('name'))
            .toList();
        expect(indices, contains('series_title_idx'));
        expect(indices, contains('library_series_idx'));
        expect(indices, contains('library_state_idx'));

        await upgradeDb.close();
      },
    );
  });
}
