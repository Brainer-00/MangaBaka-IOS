import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mangabaka_app/core/constants/app_constants.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart'
    as api;
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

class _FakeAuth extends ProfileAuthService {
  @override
  LibraryCacheLease? libraryLease;
}

Series _series(String id) => Series(
  id: id,
  title: 'Series $id',
  state: 'active',
  nativeTitle: '',
  romanizedTitle: '',
  secondaryTitles: const [],
  coverUrl: '',
  rawCoverUrl: '',
  authors: const [],
  artists: const [],
  description: '',
  year: '',
  status: '',
  isLicensed: '',
  hasAnime: '',
  contentRating: 'safe',
  type: 'manga',
  rating: '0',
  finalVolume: '',
  totalChapters: '',
  links: const [],
  publishers: const [],
  genres: const [],
  tags: const [],
  lastUpdated: '',
);

api.LibraryEntry _entry(String id) =>
    api.LibraryEntry(id: id, state: 'reading', series: _series(id));

void main() {
  late AppDatabase db;
  late LibraryService service;

  setUpAll(() {
    if (!getIt.isRegistered<LoggingService>()) {
      getIt.registerSingleton<LoggingService>(LoggingService());
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt.registerSingleton<AppDatabase>(db);
    final auth = _FakeAuth()
      ..libraryLease = await db.ownedLibraryDao.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId('owner'),
      );
    service = LibraryService(auth: auth, database: db);
  });

  tearDown(() async {
    await db.close();
    await resetServiceLocator();
  });

  group('LibraryEntriesDao membership lookup', () {
    test(
      'returns only existing candidate IDs in one projection query',
      () async {
        await db.customStatement(
          "INSERT INTO series_table (id, title, cover_url, description) "
          "VALUES ('s1', 'Series s1', '', '')",
        );
        await db.customStatement(
          "INSERT INTO library_entries_table (id, series_id, state) "
          "VALUES ('e1', 's1', 'reading')",
        );

        expect(
          await db.libraryEntriesDao.getExistingSeriesIds(['s1', 'missing']),
          {'s1'},
        );
        expect(await db.libraryEntriesDao.getExistingSeriesIds([]), isEmpty);
      },
    );
  });

  // ─── LibrarySyncMixin ──────────────────────────────────────────────────────

  test('owned initialization ignores legacy sync preferences', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.lastSyncKey: '2026-01-01T00:00:00Z',
    });
    expect(await service.isLibraryIncomplete(), isTrue);
    await db.ownedLibraryDao.finishFullImport(
      service.currentLease!,
      completeSeriesIds: {},
      watermark: null,
    );
    expect(await service.isLibraryIncomplete(), isFalse);
  });

  group('LibraryService.saveEntries', () {
    test(
      'rolls back series rows when library-entry persistence fails',
      () async {
        await db.customStatement('''
        CREATE TRIGGER reject_library_entry
        BEFORE INSERT ON owned_library_entries
        BEGIN
          SELECT RAISE(ABORT, 'forced library-entry failure');
        END;
      ''');

        await expectLater(
          service.saveEntries([_entry('atomic')]),
          throwsException,
        );

        expect(await db.seriesDao.getLatestUpdatedSeries(), isNull);
        expect(
          await db.ownedLibraryDao.listEntries(service.currentLease!.owner),
          isEmpty,
        );
      },
    );
  });
}
