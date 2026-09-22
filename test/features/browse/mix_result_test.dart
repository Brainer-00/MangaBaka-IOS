import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/browse/models/mix_result.dart';

void main() {
  group('MixDnaTag', () {
    test('fromJson parses all fields', () {
      final tag = MixDnaTag.fromJson({
        'tag_id': 42,
        'name': 'romance',
        'weight': 0.75,
      });
      expect(tag.tagId, 42);
      expect(tag.name, 'romance');
      expect(tag.weight, 0.75);
    });

    test('fromJson coerces numeric tag_id and weight', () {
      final tag = MixDnaTag.fromJson({
        'tag_id': 7.0,
        'name': 'action',
        'weight': 1,
      });
      expect(tag.tagId, 7);
      expect(tag.weight, 1.0);
    });

    test('fromJson defaults missing fields', () {
      final tag = MixDnaTag.fromJson({});
      expect(tag.tagId, 0);
      expect(tag.name, '');
      expect(tag.weight, 0.0);
    });
  });

  group('MixResult', () {
    test('constructor stores series, dna and seedCount', () {
      const dnaTag = MixDnaTag(tagId: 1, name: 'isekai', weight: 0.5);
      const result = MixResult(series: [], dna: [dnaTag], seedCount: 3);
      expect(result.series, isEmpty);
      expect(result.dna, hasLength(1));
      expect(result.dna.first.name, 'isekai');
      expect(result.seedCount, 3);
    });
  });
}
