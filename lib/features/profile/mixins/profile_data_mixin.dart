import 'package:flutter/material.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/profile/services/snapshot_service.dart';
import 'package:mangabaka_app/features/profile/services/statistics_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/models/mb_profile.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/settings/settings_manager.dart';

mixin ProfileDataMixin<T extends StatefulWidget> on State<T> {
  ProfileAuthService get auth;
  LibraryService get libraryService;
  StatisticsService get statisticsService;
  SnapshotService get snapshotService;

  bool loading = true;
  String? error;
  MbProfile? profile;

  int totalSeries = 0;
  int chaptersRead = 0;
  int volumesRead = 0;
  double meanScore = 0.0;

  final List<LibraryEntry> recentlyChanged = [];
  final List<LibraryEntry> recentlyAdded = [];

  bool isLoadingChanged = false;
  bool isLoadingAdded = false;
  bool hasMoreChanged = true;
  bool hasMoreAdded = true;
  int pageChanged = 1;
  int pageAdded = 1;
  int _changedRequestGeneration = 0;
  int _addedRequestGeneration = 0;

  void clearPrivateProfileData() {
    _changedRequestGeneration++;
    _addedRequestGeneration++;
    recentlyChanged.clear();
    recentlyAdded.clear();
    pageChanged = 1;
    pageAdded = 1;
    hasMoreChanged = true;
    hasMoreAdded = true;
    isLoadingChanged = false;
    isLoadingAdded = false;
    totalSeries = 0;
    chaptersRead = 0;
    volumesRead = 0;
    meanScore = 0;
  }

  /// Fetches the four summary statistics shown on the profile card.
  /// Runs queries in parallel for performance.
  Future<void> fetchStatistics() async {
    final session = auth.sessionGeneration;
    final contentPrefs = SettingsManager().contentPreferences;
    final results = await Future.wait([
      statisticsService.getTotalSeries(contentPreferences: contentPrefs), // [0]
      statisticsService.getChaptersRead(
        contentPreferences: contentPrefs,
      ), // [1]
      statisticsService.getVolumesRead(contentPreferences: contentPrefs), // [2]
      statisticsService.getMeanScore(contentPreferences: contentPrefs), // [3]
    ]);
    if (!mounted || session != auth.sessionGeneration) return;
    setState(() {
      totalSeries = results[0] as int;
      chaptersRead = results[1] as int;
      volumesRead = results[2] as int;
      meanScore = results[3] as double;
    });
  }

  Future<void> fetchRecentlyChanged({bool initial = false}) async {
    final session = auth.sessionGeneration;
    if (!initial && (isLoadingChanged || !hasMoreChanged)) return;

    final generation = initial
        ? ++_changedRequestGeneration
        : _changedRequestGeneration;
    final requestedPage = initial ? 1 : pageChanged;
    setState(() => isLoadingChanged = true);

    try {
      final entries = await snapshotService.fetchSnapshot(
        sortBy: 'updated_at_desc',
        page: requestedPage,
      );
      if (!mounted ||
          session != auth.sessionGeneration ||
          generation != _changedRequestGeneration) {
        return;
      }
      setState(() {
        if (initial) {
          recentlyChanged
            ..clear()
            ..addAll(entries);
        } else {
          recentlyChanged.addAll(entries);
        }
        pageChanged = requestedPage + 1;
        hasMoreChanged = entries.isNotEmpty;
        isLoadingChanged = false;
      });
    } catch (e) {
      if (!mounted ||
          session != auth.sessionGeneration ||
          generation != _changedRequestGeneration) {
        return;
      }
      setState(() => isLoadingChanged = false);
    }
  }

  Future<void> fetchRecentlyAdded({bool initial = false}) async {
    final session = auth.sessionGeneration;
    if (!initial && (isLoadingAdded || !hasMoreAdded)) return;

    final generation = initial
        ? ++_addedRequestGeneration
        : _addedRequestGeneration;
    final requestedPage = initial ? 1 : pageAdded;
    setState(() => isLoadingAdded = true);

    try {
      final entries = await snapshotService.fetchSnapshot(
        sortBy: 'created_at_desc',
        page: requestedPage,
      );
      if (!mounted ||
          session != auth.sessionGeneration ||
          generation != _addedRequestGeneration) {
        return;
      }
      setState(() {
        if (initial) {
          recentlyAdded
            ..clear()
            ..addAll(entries);
        } else {
          recentlyAdded.addAll(entries);
        }
        pageAdded = requestedPage + 1;
        hasMoreAdded = entries.isNotEmpty;
        isLoadingAdded = false;
      });
    } catch (e) {
      if (!mounted ||
          session != auth.sessionGeneration ||
          generation != _addedRequestGeneration) {
        return;
      }
      setState(() => isLoadingAdded = false);
    }
  }

  Future<void> bootstrap() async {
    final session = auth.sessionGeneration;
    final hadUsableProfile = profile != null;
    setState(() {
      loading = !hadUsableProfile;
      error = null;
    });

    try {
      final fetchedProfile = await auth.fetchProfile(forceRefresh: true);
      if (!mounted || session != auth.sessionGeneration) return;
      setState(() => profile = fetchedProfile);

      await libraryService.performInitialSyncIfNeeded();
      if (!mounted || session != auth.sessionGeneration) return;

      await Future.wait([
        fetchStatistics(),
        fetchRecentlyChanged(initial: true),
        fetchRecentlyAdded(initial: true),
      ]);

      if (mounted && session == auth.sessionGeneration) {
        setState(() => loading = false);
      }
    } catch (e) {
      if (mounted && session == auth.sessionGeneration) {
        setState(() {
          if (!auth.isLoggedIn || e is SessionExpiredException) {
            profile = null;
            error = null;
          } else if (hadUsableProfile) {
            error = null;
          } else {
            error = 'Failed to load profile';
          }
          loading = false;
        });
      }
    }
  }

  Future<void> login() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      await auth.login();
      if (mounted && auth.cachedProfile != null) await bootstrap();
    } catch (e) {
      if (!mounted || (e is AuthException && e.code == 'SESSION_CHANGED')) {
        return;
      }
      if (e is AuthCancelledException) {
        setState(() => loading = false);
        return;
      }
      setState(() {
        error = 'Login failed: $e';
        loading = false;
      });
    }
  }
}
