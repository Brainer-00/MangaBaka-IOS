import 'package:flutter/material.dart';
import 'package:mangabaka_app/core/database/database.dart';
import 'package:mangabaka_app/features/profile/services/statistics_service.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';

mixin StatisticsDataMixin<T extends StatefulWidget> on State<T> {
  late final StatisticsService statisticsService;
  final _auth = getIt<ProfileAuthService>();
  final _library = getIt<LibraryService>();
  LibraryCacheLease? _lease;
  bool _syncing = false;
  bool loading = true;

  int totalSeries = 0;
  int chaptersRead = 0;
  int volumesRead = 0;
  double completionRate = 0.0;
  int totalRereads = 0;
  double meanScore = 0.0;
  double finishRate = 0.0;
  OwnedEntryWithSeries? highestRated;
  OwnedEntryWithSeries? mostReread;

  void initStatistics() {
    statisticsService = StatisticsService(getIt<AppDatabase>(), _auth);
    _auth.addListener(_clearStatistics);
    _library.syncStatus.addListener(_onSync);
    _clearStatistics();
  }

  void _onSync() {
    final syncing = _library.syncStatus.value.isSyncing;
    if (_syncing && !syncing && _lease != null) fetchStatistics();
    _syncing = syncing;
  }

  void _clearStatistics() {
    final lease = _auth.libraryLease;
    if (identical(lease, _lease)) return;
    _lease = lease;
    setState(() {
      loading = true;
      totalSeries = chaptersRead = volumesRead = totalRereads = 0;
      completionRate = meanScore = finishRate = 0;
      highestRated = mostReread = null;
    });
    if (lease != null) fetchStatistics();
  }

  @override
  void dispose() {
    _auth.removeListener(_clearStatistics);
    _library.syncStatus.removeListener(_onSync);
    super.dispose();
  }

  Future<void> fetchStatistics() async {
    final lease = _auth.libraryLease;
    if (lease == null) return;
    final contentPrefs = SettingsManager().contentPreferences;
    final results = await Future.wait([
      statisticsService.getTotalSeries(contentPreferences: contentPrefs),
      statisticsService.getChaptersRead(contentPreferences: contentPrefs),
      statisticsService.getVolumesRead(contentPreferences: contentPrefs),
      statisticsService.getCompletionRate(contentPreferences: contentPrefs),
      statisticsService.getTotalRereads(contentPreferences: contentPrefs),
      statisticsService.getMeanScore(contentPreferences: contentPrefs),
      statisticsService.getFinishRate(contentPreferences: contentPrefs),
      statisticsService.getHighestRatedSeries(contentPreferences: contentPrefs),
      statisticsService.getMostRereadSeries(contentPreferences: contentPrefs),
    ]);

    if (!mounted || !identical(lease, _auth.libraryLease)) return;

    setState(() {
      totalSeries = results[0] as int;
      chaptersRead = results[1] as int;
      volumesRead = results[2] as int;
      completionRate = results[3] as double;
      totalRereads = results[4] as int;
      meanScore = results[5] as double;
      finishRate = results[6] as double;
      highestRated = results[7] as OwnedEntryWithSeries?;
      mostReread = results[8] as OwnedEntryWithSeries?;
      loading = false;
    });
  }
}
