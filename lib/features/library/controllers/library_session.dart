import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mangabaka_app/core/database/database.dart'
    show LibraryCacheLease;
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/exceptions/app_exceptions.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/library/models/library_entry.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';

/// Owns the library's connection to the signed-in account: the entries stream,
/// the initial sync, and tearing both down on sign-out.
///
/// The screen used to hold all of this inline, with the stream set up inside a
/// `setState` callback that also kicked off an async sync. Here the state
/// transitions are explicit and the screen just listens.
class LibrarySession extends ChangeNotifier {
  static final _logger = LoggingService.logger;

  final ProfileAuthService _auth;
  final LibraryService _library;

  /// Called with each new batch of entries, for whatever the screen needs to
  /// recompute — the stream itself is also exposed for widgets that want to
  /// build from it directly.
  final ValueChanged<List<LibraryEntry>> onEntries;

  LibrarySession({
    required this.onEntries,
    ProfileAuthService? auth,
    LibraryService? library,
  }) : _auth = auth ?? getIt<ProfileAuthService>(),
       _library = library ?? getIt<LibraryService>() {
    _auth.addListener(_onAuthStateChanged);
    _onAuthStateChanged();
  }

  LibraryCacheLease? _lease;

  bool _loggedIn = false;
  bool get isLoggedIn => _loggedIn;

  Stream<List<LibraryEntry>>? _entriesStream;
  Stream<List<LibraryEntry>>? get entriesStream => _entriesStream;

  StreamSubscription<List<LibraryEntry>>? _subscription;

  /// True when the local copy is known to be missing entries — the initial
  /// import hit its page limit and never finished.
  bool _isIncomplete = false;
  bool get isIncomplete => _isIncomplete;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthStateChanged);
    _subscription?.cancel();
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (_disposed) return;
    _loggedIn = _auth.isLoggedIn;
    final lease = _auth.libraryLease;
    if (!identical(_lease, lease)) {
      _lease = lease;
      unawaited(_subscription?.cancel());
      _subscription = null;
      _entriesStream = null;
      _isIncomplete = false;
      if (lease != null) {
        _entriesStream = _library.watchEntriesFromDb();
        _subscription = _entriesStream!.listen(
          (entries) {
            if (!_disposed && identical(_lease, lease)) onEntries(entries);
          },
          onError: (Object error) {
            _logger.warning('Library stream failed (${error.runtimeType})');
          },
        );
        unawaited(_runInitialSync(lease));
      }
    }
    _safeNotify();
  }

  Future<void> _runInitialSync(LibraryCacheLease lease) async {
    try {
      await _library.performInitialSyncIfNeeded();
    } catch (error) {
      _logger.warning('Initial Library sync failed (${error.runtimeType})');
    } finally {
      await _readIncomplete(lease);
    }
  }

  Future<void> _readIncomplete(LibraryCacheLease lease) async {
    if (_disposed || !identical(_lease, lease)) return;
    try {
      final incomplete = await _library.isLibraryIncomplete();
      if (_disposed || !identical(_lease, lease)) return;
      _isIncomplete = incomplete;
      _safeNotify();
    } catch (error) {
      _logger.warning(
        'Library cache status unavailable (${error.runtimeType})',
      );
    }
  }

  /// Signs in and opens the library.
  ///
  /// Returns null on success or when the user cancelled, and an error message
  /// key when the attempt genuinely failed — a cancelled login is a choice,
  /// not something to report back.
  Future<String?> login() async {
    _logger.info('User attempting login from library screen');
    try {
      await _auth.login();
    } on AuthCancelledException {
      _logger.info('Login cancelled by user in library screen');
      return null;
    } catch (e) {
      _logger.severe('Login failed in library screen (${e.runtimeType})');
      return 'login_failed_retry';
    }

    if (_disposed) return null;
    _logger.info('Login successful in library screen');
    _onAuthStateChanged();
    return null;
  }

  /// A manual refresh. Failures are reported through
  /// [LibraryService.syncStatus], which raises the banner, so nothing is
  /// thrown back to the caller.
  Future<void> refresh() async {
    final lease = _lease;
    if (lease == null) {
      if (_auth.isLoggedIn) {
        try {
          await _auth.fetchProfile(forceRefresh: true);
        } catch (_) {}
      }
      return;
    }
    try {
      await _library.reconcileLibrary(lease);
    } catch (e) {
      _logger.severe('Manual refresh failed (${e.runtimeType})');
    } finally {
      await _readIncomplete(lease);
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }
}
