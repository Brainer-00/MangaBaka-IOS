import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/browse/models/browse_type.dart';

void main() {
  group('BrowseType', () {
    test('enum contains expected values', () {
      expect(BrowseType.values, [
        BrowseType.series,
        BrowseType.publishers,
        BrowseType.staff,
        BrowseType.characters,
      ]);
    });

    test('enum values have correct names', () {
      expect(BrowseType.series.name, 'series');
      expect(BrowseType.publishers.name, 'publishers');
      expect(BrowseType.staff.name, 'staff');
      expect(BrowseType.characters.name, 'characters');
    });
  });
}
