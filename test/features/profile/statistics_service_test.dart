import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/profile/services/statistics_service.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:drift/native.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:drift/drift.dart' as drift;

class _Auth extends ProfileAuthService {
  @override
  LibraryCacheLease? libraryLease;
}

void main() {
  late AppDatabase db;
  late StatisticsService service;
  late _Auth auth;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await resetServiceLocator();
    getIt.registerSingleton<LoggingService>(LoggingService());
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = _Auth();
    auth.libraryLease = await db.ownedLibraryDao.activate(
      VerifiedLibraryOwner.fromVerifiedAccountId('stats'),
    );
    await db.ownedLibraryDao.finishFullImport(
      auth.libraryLease!,
      completeSeriesIds: {},
      watermark: null,
    );
    service = StatisticsService(db, auth);
  });

  tearDown(() async {
    await db.close();
    await resetServiceLocator();
  });

  group('StatisticsService', () {
    test('ignores quarantined and other-account tracking rows', () async {
      final dao = db.ownedLibraryDao;
      final a = auth.libraryLease!;
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: 'shared',
              title: 'Shared',
              coverUrl: '',
              description: '',
            ),
          );
      await db
          .into(db.libraryEntriesTable)
          .insert(
            LibraryEntriesTableCompanion.insert(
              id: 'legacy',
              seriesId: 'shared',
              state: 'reading',
              rating: const drift.Value(100),
            ),
          );
      await db
          .into(db.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              id: 'remote',
              ownerId: a.owner.id,
              seriesId: 'shared',
              state: 'reading',
              rating: const drift.Value(90),
            ),
          );
      expect(await service.getMeanScore(), 90);
      final b = await dao.activate(
        VerifiedLibraryOwner.fromVerifiedAccountId('other'),
      );
      auth.libraryLease = b;
      expect(await service.getTotalSeries(), 0);
      expect(await service.getHighestRatedSeries(), isNull);
      await dao.finishFullImport(b, completeSeriesIds: {}, watermark: null);
      await db
          .into(db.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              id: 'remote',
              ownerId: b.owner.id,
              seriesId: 'shared',
              state: 'reading',
              rating: const drift.Value(12),
            ),
          );
      expect(await service.getTotalSeries(), 1);
      expect((await service.getHighestRatedSeries())?.entry.rating, 12);
      auth.libraryLease = null;
      expect(await service.getHighestRatedSeries(), isNull);
    });
    test('getTotalSeries returns 0 initially', () async {
      final total = await service.getTotalSeries();
      expect(total, 0);
    });

    test('getTotalSeries respects contentPreferences', () async {
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: '1',
              title: 'SFW Series',
              coverUrl: '',
              description: '',
              status: const drift.Value(''),
              isLicensed: const drift.Value(''),
              hasAnime: const drift.Value(''),
              contentRating: const drift.Value('safe'),
              type: const drift.Value(''),
              lastUpdated: drift.Value(DateTime.now().toIso8601String()),
            ),
          );
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: '2',
              title: 'NSFW Series',
              coverUrl: '',
              description: '',
              status: const drift.Value(''),
              isLicensed: const drift.Value(''),
              hasAnime: const drift.Value(''),
              contentRating: const drift.Value('suggestive'),
              type: const drift.Value(''),
              lastUpdated: drift.Value(DateTime.now().toIso8601String()),
            ),
          );

      await db
          .into(db.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              ownerId: auth.libraryLease!.owner.id,
              id: 'e1',
              state: 'reading',
              seriesId: '1',
            ),
          );
      await db
          .into(db.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              ownerId: auth.libraryLease!.owner.id,
              id: 'e2',
              state: 'reading',
              seriesId: '2',
            ),
          );

      expect(await service.getTotalSeries(), 2);
      expect(await service.getTotalSeries(contentPreferences: ['safe']), 1);
      expect(
        await service.getTotalSeries(contentPreferences: ['suggestive']),
        1,
      );
      expect(
        await service.getTotalSeries(
          contentPreferences: ['safe', 'suggestive'],
        ),
        2,
      );
    });

    test('getChaptersRead respects contentPreferences', () async {
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: 's1',
              title: 'S1',
              coverUrl: '',
              description: '',
              status: const drift.Value(''),
              isLicensed: const drift.Value(''),
              hasAnime: const drift.Value(''),
              contentRating: const drift.Value('safe'),
              type: const drift.Value(''),
              lastUpdated: drift.Value(DateTime.now().toIso8601String()),
            ),
          );
      await db
          .into(db.seriesTable)
          .insert(
            SeriesTableCompanion.insert(
              id: 's2',
              title: 'S2',
              coverUrl: '',
              description: '',
              status: const drift.Value(''),
              isLicensed: const drift.Value(''),
              hasAnime: const drift.Value(''),
              contentRating: const drift.Value('suggestive'),
              type: const drift.Value(''),
              lastUpdated: drift.Value(DateTime.now().toIso8601String()),
            ),
          );

      await db
          .into(db.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              ownerId: auth.libraryLease!.owner.id,
              id: 'e1_prog',
              state: 'reading',
              seriesId: 's1',
              progressChapter: const drift.Value(10),
            ),
          );
      await db
          .into(db.ownedLibraryEntries)
          .insert(
            OwnedLibraryEntriesCompanion.insert(
              ownerId: auth.libraryLease!.owner.id,
              id: 'e2_prog',
              state: 'reading',
              seriesId: 's2',
              progressChapter: const drift.Value(20),
            ),
          );

      expect(await service.getChaptersRead(), 30);
      expect(await service.getChaptersRead(contentPreferences: ['safe']), 10);
    });
  });
}
