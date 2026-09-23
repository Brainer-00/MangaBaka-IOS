import 'package:flutter/foundation.dart';
import 'package:mangabaka_app/core/di/service_locator.dart';
import 'package:mangabaka_app/core/logging/logging_service.dart';
import 'package:mangabaka_app/features/home/services/home_service.dart';
import 'package:mangabaka_app/features/library/services/library_service.dart';
import 'package:mangabaka_app/features/profile/services/profile_auth_service.dart';
import 'package:mangabaka_app/features/series/models/series.dart';

/// Manages an interactive Discovery Queue session.
///
/// Steps through personalised recommendations one-by-one, allowing the user to
/// add series to their library in a chosen state or skip to the next.
class DiscoveryQueueController extends ChangeNotifier {
  final HomeService _homeService;
  final LibraryService _libraryService;
  final ProfileAuthService _authService;

  final _logger = LoggingService.logger;

  List<Series> _queue = const [];
  int _currentIndex = 0;
  int _reviewedCount = 0;
  int _addedCount = 0;

  bool _isLoading = true;
  bool _isActionInProgress = false;
  bool _isReady = true;
  bool _isCompleted = false;
  String? _errorMessage;

  DiscoveryQueueController({
    HomeService? homeService,
    LibraryService? libraryService,
    ProfileAuthService? authService,
  })  : _homeService = homeService ?? HomeService(),
        _libraryService = libraryService ?? getIt<LibraryService>(),
        _authService = authService ?? getIt<ProfileAuthService>();

  List<Series> get queue => _queue;
  int get currentIndex => _currentIndex;
  int get reviewedCount => _reviewedCount;
  int get addedCount => _addedCount;

  bool get isLoading => _isLoading;
  bool get isActionInProgress => _isActionInProgress;
  bool get isReady => _isReady;
  bool get isCompleted => _isCompleted;
  String? get errorMessage => _errorMessage;

  Series? get currentSeries =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  int get totalCount => _queue.length;
  int get remainingCount =>
      (_queue.length - _currentIndex).clamp(0, _queue.length);

  double get progress =>
      _queue.isEmpty ? 0.0 : (_currentIndex / _queue.length).clamp(0.0, 1.0);

  bool get hasItems => _queue.isNotEmpty;

  /// Loads or reloads the discovery queue.
  Future<void> loadQueue({int limit = 20}) async {
    _isLoading = true;
    _errorMessage = null;
    _isCompleted = false;
    notifyListeners();

    if (!_authService.isLoggedIn) {
      _isLoading = false;
      _isReady = false;
      _errorMessage = 'import_login_required';
      notifyListeners();
      return;
    }

    try {
      final readiness = await _homeService.fetchForYouReadiness();
      if (readiness != null && !readiness.isReady) {
        _isReady = false;
        _isLoading = false;
        _queue = const [];
        notifyListeners();
        return;
      }

      _isReady = true;
      final items = await _homeService.fetchForYou(limit: limit);
      _queue = items;
      _currentIndex = 0;
      _reviewedCount = 0;
      _addedCount = 0;
      _isCompleted = false;
      _isLoading = false;
      _logger.info('DiscoveryQueue loaded ${items.length} series');
    } catch (e) {
      _logger.severe(
        'Failed to load discovery queue (${e.runtimeType})',
      );
      _errorMessage = e.toString();
      _isLoading = false;
    }

    notifyListeners();
  }

  /// Adds the current series to the library with [state], then moves to the next.
  Future<bool> addToLibrary(String state) async {
    final series = currentSeries;
    if (series == null || _isActionInProgress) return false;

    _isActionInProgress = true;
    notifyListeners();

    try {
      await _libraryService.createLibraryEntry(series.id, state);
      _addedCount++;
      _reviewedCount++;
      _currentIndex++;
      if (_currentIndex >= _queue.length) {
        _isCompleted = true;
      }
      return true;
    } catch (e) {
      _logger.severe(
        'Failed to add series to library (${e.runtimeType})',
      );
      rethrow;
    } finally {
      _isActionInProgress = false;
      notifyListeners();
    }
  }

  /// Skips the current series without adding it, moving to the next.
  void skip() {
    if (currentSeries == null || _isActionInProgress) return;
    _reviewedCount++;
    _currentIndex++;
    if (_currentIndex >= _queue.length) {
      _isCompleted = true;
    }
    notifyListeners();
  }

  /// Restarts the queue with a fresh batch of recommendations.
  void restart() {
    loadQueue();
  }

  @override
  void dispose() {
    _homeService.dispose();
    super.dispose();
  }
}
