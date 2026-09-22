import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/core/utils/date_utils.dart';

void main() {
  group('AppDateUtils', () {
    test('extractYear returns first 4 characters', () {
      expect(AppDateUtils.extractYear('2023-10-05'), '2023');
      expect(AppDateUtils.extractYear('2024'), '2024');
    });

    test('extractYear handles empty or short strings', () {
      expect(AppDateUtils.extractYear(''), '');
      expect(AppDateUtils.extractYear('23'), '23');
    });

    test('formatFullDate formats valid date', () {
      expect(AppDateUtils.formatFullDate('2023-10-05'), 'Oct 5, 2023');
    });

    test('formatFullDate handles invalid date', () {
      expect(AppDateUtils.formatFullDate('invalid-date'), 'invalid-date');
    });

    test('formatFullDate handles empty string', () {
      expect(AppDateUtils.formatFullDate(''), '');
    });
  });
}
