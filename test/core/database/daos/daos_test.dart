import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:get_it/get_it.dart';
import 'package:mangabaka_app/features/series/models/series.dart' as api;
import 'package:mangabaka_app/features/library/models/library_entry.dart'
    as api;
import 'package:mangabaka_app/features/library/services/mappers/db_to_api_mapper.dart';

void main() {
  late AppDatabase db;

  api.Series createDummySeries(String id, String title) {
    return api.Series(
      id: id,
      state: 'published',
      title: title,
      nativeTitle: '',
      romanizedTitle: '',
      secondaryTitles: [],
      coverUrl: 'https://example.com/cover.jpg',
      rawCoverUrl: 'https://example.com/cover.jpg',
      authors: [],
      artists: [],
      description: 'Test description',
      year: '2024',
      status: 'ongoing',
      isLicensed: 'false',
      hasAnime: 'false',
      contentRating: 'safe',
      type: 'manga',
      rating: '0',
      finalVolume: '0',
      totalChapters: '0',
      links: [],
      publishers: [],
      genres: [],
      tags: [],
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }

  ft.setUp(() {
    if (!GetIt.I.isRegistered<LoggingService>()) {
      GetIt.I.registerSingleton<LoggingService>(LoggingService());
    }
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  ft.tearDown(() async {
    await db.close();
  });

  ft.group('SeriesDao', () {
    ft.test('upsertSeries and getLatestUpdatedSeries', () async {
      final series = createDummySeries('series_1', 'Manga One');

      await db.seriesDao.upsertSeries([series]);

      final latest = await db.seriesDao.getLatestUpdatedSeries();
      ft.expect(latest, ft.isNotNull);
      ft.expect(latest!.id, 'series_1');
      ft.expect(latest.title, 'Manga One');
    });
  });

  ft.group('LibraryEntriesDao', () {
    ft.test(
      'merges v1 fields without losing omitted values or list membership',
      () async {
        final series = createDummySeries('1', 'One');
        final other = createDummySeries('2', 'Two');
        await db.seriesDao.upsertSeries([series, other]);
        final dao = db.libraryEntriesDao;
        api.LibraryEntry fromPage(Map<String, Object?> fields) =>
            api.LibraryEntry.fromJson({
              'id': 10,
              'Series': {'id': 1, 'title': 'One'},
              ...fields,
            });
        Future<api.LibraryEntry> stored() async =>
            DbToApiMapper.libraryEntryFromDb(
              (await dao.getEntryBySeriesId('1'))!,
            );

        await dao.upsertLibraryEntries([
          fromPage({
            'state': 'reading',
            'priority': 25,
            'start_date': '2024-02-29T23:30:00-08:00',
            'finish_date': '2024-03-15',
            'progress_chapter': 12,
            'progress_volume': 3,
            'number_of_rereads': 2,
            'read_link': 'https://example.com/read?a=1',
            'is_private': true,
            'rating': 86,
            'note': 'First line\nSecond line 📝',
          }),
          api.LibraryEntry(id: '20', state: 'paused', series: other),
        ]);
        ft.expect((await stored()).listIds, ft.isNull);

        await dao.upsertLibraryEntries([
          api.LibraryEntry(
            id: '10',
            state: 'reading',
            series: series,
            listIds: [7],
          ),
          fromPage({'progress_chapter': 13}),
        ]);
        final merged = await stored();
        ft.expect(merged.id, '10');
        ft.expect(merged.state, 'reading');
        ft.expect(merged.priority, 25);
        ft.expect(merged.startDate, '2024-02-29');
        ft.expect(merged.finishDate, '2024-03-15');
        ft.expect(merged.progressChapter, 13);
        ft.expect(merged.progressVolume, 3);
        ft.expect(merged.numberOfRereads, 2);
        ft.expect(merged.readLink, 'https://example.com/read?a=1');
        ft.expect(merged.isPrivate, true);
        ft.expect(merged.rating, 86);
        ft.expect(merged.note, 'First line\nSecond line 📝');
        ft.expect(merged.listIds, [7]);

        await dao.upsertLibraryEntries([
          fromPage({
            'id': 10,
            'start_date': null,
            'finish_date': null,
            'progress_chapter': null,
            'progress_volume': null,
            'number_of_rereads': null,
            'read_link': null,
            'rating': null,
            'note': null,
            'is_private': false,
          }),
          api.LibraryEntry(
            id: '10',
            state: 'reading',
            series: series,
            listIds: [],
          ),
        ]);
        final cleared = await stored();
        ft.expect([
          cleared.startDate,
          cleared.finishDate,
          cleared.progressChapter,
          cleared.progressVolume,
          cleared.numberOfRereads,
          cleared.readLink,
          cleared.rating,
          cleared.note,
        ], ft.everyElement(ft.isNull));
        ft.expect(cleared.listIds, ft.isEmpty);
        ft.expect(cleared.priority, 25);
        ft.expect(cleared.isPrivate, false);
        final joined = await dao.watchAllEntriesWithSeries().first;
        ft.expect(
          joined.map((row) => row.libraryEntry.id),
          ft.unorderedEquals(['10', '20']),
        );
        ft.expect((await dao.getEntryBySeriesId('2'))!.series.title, 'Two');
        await dao.upsertLibraryEntries([
          api.LibraryEntry(
            id: '10',
            state: 'reading',
            series: series,
            isPrivate: true,
            listIds: [7],
            note: 'private',
          ),
          api.LibraryEntry(id: '11', state: 'paused', series: series),
        ]);
        final replacement = await stored();
        ft.expect(replacement.id, '11');
        ft.expect(replacement.isPrivate, ft.isNull);
        ft.expect(replacement.note, ft.isNull);
        ft.expect(replacement.listIds, ft.isNull);
        await ft.expectLater(
          dao.upsertLibraryEntries([
            api.LibraryEntry(
              id: '11',
              state: 'reading',
              series: series,
              note: 'rollback',
            ),
            api.LibraryEntry(id: '11', state: 'reading', series: other),
          ]),
          ft.throwsA(ft.anything),
        );
        ft.expect((await stored()).note, ft.isNull);
      },
    );

    ft.test(
      'malformed membership remains unknown in the watched stream',
      () async {
        final series = createDummySeries('1', 'One');
        await db.seriesDao.upsertSeries([series]);
        await db.libraryEntriesDao.upsertLibraryEntries([
          api.LibraryEntry(id: '1', state: 'reading', series: series),
        ]);
        for (final value in [
          'broken',
          '{}',
          '[1, "2"]',
          '[null]',
          '[-1]',
          'null',
        ]) {
          await db
              .update(db.libraryEntriesTable)
              .write(LibraryEntriesTableCompanion(listIdsJson: Value(value)));
          final row =
              (await db.libraryEntriesDao.watchAllEntriesWithSeries().first)
                  .single;
          ft.expect(DbToApiMapper.libraryEntryFromDb(row).listIds, ft.isNull);
        }
      },
    );

    ft.test(
      'imports and updates a large library without losing rows',
      () async {
        final series = List.generate(
          2000,
          (i) => createDummySeries('$i', 'Series $i'),
        );
        await db.seriesDao.upsertSeries(series);
        final entries = [
          for (final item in series)
            api.LibraryEntry(id: item.id, state: 'reading', series: item),
        ];
        await db.libraryEntriesDao.upsertLibraryEntries(entries);
        await db.libraryEntriesDao.upsertLibraryEntries(entries);
        final rows = await db.libraryEntriesDao
            .watchAllEntriesWithSeries()
            .first;
        ft.expect(rows.length, 2000);
        ft.expect(rows.map((row) => row.libraryEntry.id).toSet().length, 2000);
      },
    );

    ft.test('upsertLibraryEntries and watchEntryWithSeries', () async {
      // Must have series first for foreign key
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: 's1',
              title: 'Series One',
              coverUrl: 'url',
              description: 'desc',
            ),
          );

      final entry = api.LibraryEntry(
        id: 'e1',
        state: 'reading',
        series: createDummySeries('s1', 'Series One'),
      );

      await db.libraryEntriesDao.upsertLibraryEntries([entry]);

      final result = await db.libraryEntriesDao
          .watchEntryWithSeries('s1')
          .first;
      ft.expect(result, ft.isNotNull);
      ft.expect(result!.libraryEntry.id, 'e1');
      ft.expect(result.series.id, 's1');
    });

    ft.test('updateEntryState updates correct entry', () async {
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: 's1',
              title: 'Series One',
              coverUrl: 'url',
              description: 'desc',
            ),
          );
      await db
          .into(db.libraryEntriesTable)
          .insert(
            LibraryEntriesTableCompanion.insert(
              id: 'e1',
              seriesId: 's1',
              state: 'reading',
            ),
          );

      await db.libraryEntriesDao.updateEntryState('s1', 'completed');

      final entry = await (db.select(
        db.libraryEntriesTable,
      )..where((t) => t.seriesId.equals('s1'))).getSingle();
      ft.expect(entry.state, 'completed');
    });

    ft.test('deleteEntry removes entry', () async {
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: 's1',
              title: 'Series One',
              coverUrl: 'url',
              description: 'desc',
            ),
          );
      await db
          .into(db.libraryEntriesTable)
          .insert(
            LibraryEntriesTableCompanion.insert(
              id: 'e1',
              seriesId: 's1',
              state: 'reading',
            ),
          );

      await db.libraryEntriesDao.deleteEntry('s1');

      final entry = await (db.select(
        db.libraryEntriesTable,
      )..where((t) => t.seriesId.equals('s1'))).getSingleOrNull();
      ft.expect(entry, ft.isNull);
    });
  });
}
