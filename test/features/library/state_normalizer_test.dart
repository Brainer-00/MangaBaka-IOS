import 'package:flutter_test/flutter_test.dart';
import 'package:mangabaka_app/features/library/services/state_normalizer.dart';

void main() {
  group('StateNormalizer', () {
    test('normalize trims and lowercases', () {
      expect(StateNormalizer.normalize('  READING  '), 'reading');
    });

    test('normalize replaces spaces and hyphens with underscores', () {
      expect(StateNormalizer.normalize('Plan To Read'), 'plan_to_read');
      expect(StateNormalizer.normalize('plan-to-read'), 'plan_to_read');
    });

    test('normalize maps specific states', () {
      expect(StateNormalizer.normalize('on_hold'), 'paused');
      expect(StateNormalizer.normalize('onhold'), 'paused');
      expect(StateNormalizer.normalize('complete'), 'completed');
      expect(StateNormalizer.normalize('planned'), 'plan_to_read');
      expect(StateNormalizer.normalize('planning'), 'plan_to_read');
      expect(StateNormalizer.normalize('to_read'), 'plan_to_read');
    });

    test('normalize returns original if no mapping exists', () {
      expect(StateNormalizer.normalize('reading'), 'reading');
      expect(StateNormalizer.normalize('dropped'), 'dropped');
    });
  });
}
