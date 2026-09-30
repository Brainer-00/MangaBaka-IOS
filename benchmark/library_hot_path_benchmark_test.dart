import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/browse/models/search_filters.dart';
import 'package:mangabaka_app/features/library/constants/library_screen_constants.dart';
import 'package:mangabaka_app/features/library/helpers/library_filter_helper.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/services/library_autocomplete_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/library/services/mappers/db_to_api_mapper.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

void main() {
  setUpAll(() {
    if (!GetIt.I.isRegistered<LoggingService>()) {
      GetIt.I.registerSingleton<LoggingService>(LoggingService());
    }
  });

  for (final size in const [100, 1000, 5000]) {
    test('library hot paths with $size entries', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final entries = List.generate(size, _entry);

      await db.seriesDao.upsertSeries(entries.map((e) => e.series).toList());
      await db.libraryEntriesDao.upsertLibraryEntries(entries);

      final readWatch = Stopwatch()..start();
      final rows = await db.libraryEntriesDao.watchAllEntriesWithSeries().first;
      readWatch.stop();

      final mappingWatch = Stopwatch()..start();
      final mapped = rows.map(DbToApiMapper.libraryEntryFromDb).toList();
      mappingWatch.stop();

      final filterWatch = Stopwatch()..start();
      final filtered = LibraryFilterHelper(
        allEntries: mapped,
        query: 'series 1',
        contentPreferences: const ['safe', 'suggestive'],
        filters: SearchFilters(
          type: const ['manga'],
          genre: const ['Action'],
          sortBy: 'name_asc',
        ),
      ).getFilteredAndSorted();
      filterWatch.stop();

      final tabWatch = Stopwatch()..start();
      final tabHelper = LibraryFilterHelper(
        allEntries: mapped,
        query: '',
        contentPreferences: const ['safe', 'suggestive'],
      );
      final tabCounts = <String, int>{};
      for (final tab in LibraryScreenConstants.tabs) {
        tabCounts[tab.key] = tabHelper.getByTab(tab.key).length;
      }
      final directCounts = <String, int>{};
      for (final entry in tabHelper.getFilteredAndSorted()) {
        directCounts[entry.state] = (directCounts[entry.state] ?? 0) + 1;
      }
      tabWatch.stop();

      final autocomplete = LibraryAutocompleteService();
      final autocompleteWatch = Stopwatch()..start();
      final autocompleteCounts = <String, int>{};
      for (final query in const ['series 1', 'native 24', 'alias 4999']) {
        autocompleteCounts[query] = autocomplete.search(query, mapped).length;
      }
      autocompleteWatch.stop();

      expect(mapped, hasLength(size));
      expect(filtered.every((entry) => entry.series.type == 'manga'), isTrue);
      expect(tabCounts.values.fold<int>(0, (sum, count) => sum + count), size);
      expect(
        directCounts.values.fold<int>(0, (sum, count) => sum + count),
        size,
      );
      expect(autocompleteCounts.values.every((count) => count <= 6), isTrue);

      // Machine-dependent timings are measurements only, never pass/fail gates.
      // ignore: avoid_print
      print(
        'LIBRARY_BENCH size=$size '
        'db_read_us=${readWatch.elapsedMicroseconds} '
        'db_to_model_us=${mappingWatch.elapsedMicroseconds} '
        'filter_sort_us=${filterWatch.elapsedMicroseconds} '
        'tab_partition_count_us=${tabWatch.elapsedMicroseconds} '
        'autocomplete_3_queries_us=${autocompleteWatch.elapsedMicroseconds} '
        'filtered=${filtered.length} autocomplete=$autocompleteCounts',
      );
    });
  }

  test('watch emissions and mapping passes for representative writes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final client = http.Client();
    addTearDown(() async {
      client.close();
      await db.close();
    });

    final initial = List.generate(100, _entry);
    await db.seriesDao.upsertSeries(initial.map((e) => e.series).toList());
    await db.libraryEntriesDao.upsertLibraryEntries(initial);

    final service = LibraryService(
      auth: ProfileAuthService(),
      database: db,
      httpClient: client,
    );
    var emissions = 0;
    var mappingPasses = 0;
    final firstEmission = Completer<void>();
    final subscription = service.watchEntriesFromDb().listen((entries) {
      emissions++;
      mappingPasses++;
      if (!firstEmission.isCompleted) firstEmission.complete();
    });
    addTearDown(subscription.cancel);
    await firstEmission.future;

    final beforeProgress = emissions;
    await db.libraryEntriesDao.updateEntryProgress(
      'series-0',
      progressChapter: 2,
    );
    await _waitForQuiescence(() => emissions);
    final progressEmissions = emissions - beforeProgress;
    final progressed = await db.libraryEntriesDao
        .watchEntryWithSeries('series-0')
        .first;
    expect(progressed?.libraryEntry.progressChapter, 2);

    final beforeState = emissions;
    await db.libraryEntriesDao.updateEntryState('series-1', 'paused');
    await _waitForQuiescence(() => emissions);
    final stateEmissions = emissions - beforeState;
    final paused = await db.libraryEntriesDao
        .watchEntryWithSeries('series-1')
        .first;
    expect(paused?.libraryEntry.state, 'paused');

    final syncPage = List.generate(100, (index) {
      final old = initial[index];
      return LibraryEntry(
        id: old.id,
        state: old.state,
        progressChapter: (old.progressChapter ?? 0) + 1,
        series: old.series,
      );
    });
    final beforeBatch = emissions;
    await service.saveEntries(syncPage);
    await _waitForQuiescence(() => emissions);
    final batchEmissions = emissions - beforeBatch;

    expect(progressEmissions, greaterThanOrEqualTo(1));
    expect(stateEmissions, greaterThanOrEqualTo(1));
    expect(batchEmissions, greaterThanOrEqualTo(1));
    expect(mappingPasses, emissions);

    // ignore: avoid_print
    print(
      'LIBRARY_WATCH subscribers=1 '
      'progress_emissions=$progressEmissions progress_mapping_passes=$progressEmissions '
      'state_emissions=$stateEmissions state_mapping_passes=$stateEmissions '
      'sync_page_emissions=$batchEmissions sync_page_mapping_passes=$batchEmissions '
      'total_emissions=$emissions total_mapping_passes=$mappingPasses',
    );
  });
}

Future<void> _waitForQuiescence(int Function() readCount) async {
  var stableRounds = 0;
  var previous = readCount();
  while (stableRounds < 3) {
    await Future<void>.delayed(Duration.zero);
    final current = readCount();
    if (current == previous) {
      stableRounds++;
    } else {
      previous = current;
      stableRounds = 0;
    }
  }
}

LibraryEntry _entry(int index) {
  const states = ['reading', 'completed', 'plan_to_read', 'paused', 'dropped'];
  final id = 'series-$index';
  return LibraryEntry(
    id: 'entry-$index',
    state: states[index % states.length],
    progressChapter: index % 80,
    progressVolume: index % 10,
    rating: index % 101,
    series: Series(
      id: id,
      state: 'published',
      title: 'Series $index Adventure',
      nativeTitle: 'Native $index',
      romanizedTitle: 'Romanized $index',
      secondaryTitles: ['Alias $index', 'Alternative $index'],
      coverUrl: 'https://example.com/$id.jpg',
      rawCoverUrl: 'https://example.com/$id.jpg',
      authors: ['Author ${index % 50}'],
      artists: ['Artist ${index % 40}'],
      description: 'Synthetic benchmark series $index',
      year: '${2000 + (index % 25)}',
      published: const {'year': 2024},
      status: index.isEven ? 'ongoing' : 'completed',
      isLicensed: index.isEven ? 'yes' : 'no',
      hasAnime: index % 3 == 0 ? 'yes' : 'no',
      anime: const {'id': 1},
      contentRating: index % 4 == 0 ? 'suggestive' : 'safe',
      type: index % 5 == 0 ? 'novel' : 'manga',
      rating: '${60 + (index % 41)}',
      finalVolume: '',
      totalChapters: '${50 + (index % 100)}',
      links: const [
        {'name': 'official', 'url': 'https://example.com'},
      ],
      publishers: ['Publisher ${index % 20}'],
      genres: const ['Action', 'Adventure'],
      tags: const ['Journey', 'Friendship'],
      lastUpdated: '2026-09-${(index % 28 + 1).toString().padLeft(2, '0')}',
      relationships: const {'related': []},
      source: const {
        'source-a': {'rating_normalized': 80},
        'source-b': {'rating_normalized': 90},
      },
    ),
  );
}
