import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/library/models/library_sync_status.dart';

void main() {
  group('LibrarySyncStatus', () {
    test('default values are sensible', () {
      const s = LibrarySyncStatus();
      expect(s.isSyncing, isFalse);
      expect(s.currentEntries, 0);
      expect(s.error, isNull);
      expect(s.isServerDown, isFalse);
    });

    test('copyWith updates only provided fields', () {
      const s = LibrarySyncStatus(currentEntries: 5);
      final updated = s.copyWith(isSyncing: true, currentEntries: 10);
      expect(updated.isSyncing, isTrue);
      expect(updated.currentEntries, 10);
      expect(updated.error, isNull);
    });

    test('copyWith with clearError nulls error and resets isServerDown', () {
      const s = LibrarySyncStatus(error: 'boom', isServerDown: true);
      final cleared = s.copyWith(clearError: true);
      expect(cleared.error, isNull);
      expect(cleared.isServerDown, isFalse);
    });

    test('copyWith preserves error when not cleared', () {
      const s = LibrarySyncStatus(error: 'oops');
      final next = s.copyWith(isSyncing: true);
      expect(next.error, 'oops');
    });

    test('toString includes core fields', () {
      const s = LibrarySyncStatus(isSyncing: true, currentEntries: 4, error: 'x');
      expect(s.toString(), contains('isSyncing: true'));
      expect(s.toString(), contains('current: 4'));
      expect(s.toString(), contains('error: x'));
    });
  });
}
