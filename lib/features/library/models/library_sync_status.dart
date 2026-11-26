class LibrarySyncStatus {
  final bool isSyncing;
  final int currentEntries;
  final String? error;
  final bool isServerDown;
  final bool initialImportIncomplete;
  final bool pageLimitReached;

  const LibrarySyncStatus({
    this.isSyncing = false,
    this.currentEntries = 0,
    this.error,
    this.isServerDown = false,
    this.initialImportIncomplete = false,
    this.pageLimitReached = false,
  });

  LibrarySyncStatus copyWith({
    bool? isSyncing,
    int? currentEntries,
    String? error,
    bool? isServerDown,
    bool? initialImportIncomplete,
    bool? pageLimitReached,
    bool clearError = false,
    // Kept for backwards compatibility — no-op.
    String? infoMessage,
    bool clearInfo = false,
  }) {
    return LibrarySyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      currentEntries: currentEntries ?? this.currentEntries,
      error: clearError ? null : (error ?? this.error),
      isServerDown: clearError ? false : (isServerDown ?? this.isServerDown),
      initialImportIncomplete:
          initialImportIncomplete ?? this.initialImportIncomplete,
      pageLimitReached: pageLimitReached ?? this.pageLimitReached,
    );
  }

  @override
  String toString() =>
      'LibrarySyncStatus(isSyncing: $isSyncing, current: $currentEntries, error: $error)';
}
