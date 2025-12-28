import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/stabilization_mode.dart';

void main() {
  group('StabilizationMode', () {
    test('has fast and slow values', () {
      expect(StabilizationMode.values, hasLength(2));
      expect(StabilizationMode.values, contains(StabilizationMode.fast));
      expect(StabilizationMode.values, contains(StabilizationMode.slow));
    });

    test('fast has name "fast"', () {
      expect(StabilizationMode.fast.name, 'fast');
    });

    test('slow has name "slow"', () {
      expect(StabilizationMode.slow.name, 'slow');
    });

    group('fromString()', () {
      test('returns fast for "fast"', () {
        expect(StabilizationMode.fromString('fast'), StabilizationMode.fast);
      });

      test('returns slow for "slow"', () {
        expect(StabilizationMode.fromString('slow'), StabilizationMode.slow);
      });

      test('is case insensitive - returns fast for "FAST"', () {
        expect(StabilizationMode.fromString('FAST'), StabilizationMode.fast);
      });

      test('is case insensitive - returns slow for "SLOW"', () {
        expect(StabilizationMode.fromString('SLOW'), StabilizationMode.slow);
      });

      test('is case insensitive - returns fast for "Fast"', () {
        expect(StabilizationMode.fromString('Fast'), StabilizationMode.fast);
      });

      test('is case insensitive - returns slow for "Slow"', () {
        expect(StabilizationMode.fromString('Slow'), StabilizationMode.slow);
      });

      test('returns fast for invalid value', () {
        expect(StabilizationMode.fromString('invalid'), StabilizationMode.fast);
      });

      test('returns fast for empty string', () {
        expect(StabilizationMode.fromString(''), StabilizationMode.fast);
      });

      test('returns fast for whitespace', () {
        expect(StabilizationMode.fromString('   '), StabilizationMode.fast);
      });

      test('returns fast for "medium" (not a valid mode)', () {
        expect(StabilizationMode.fromString('medium'), StabilizationMode.fast);
      });

      test('returns fast for "fastest"', () {
        expect(StabilizationMode.fromString('fastest'), StabilizationMode.fast);
      });

      test('returns fast for "slower"', () {
        expect(StabilizationMode.fromString('slower'), StabilizationMode.fast);
      });

      test('returns fast for numeric string', () {
        expect(StabilizationMode.fromString('123'), StabilizationMode.fast);
      });
    });

    group('usage scenarios', () {
      test('can be used in switch expressions', () {
        String getPassCount(StabilizationMode mode) {
          return switch (mode) {
            StabilizationMode.fast => '4 passes',
            StabilizationMode.slow => '10 passes',
          };
        }

        expect(getPassCount(StabilizationMode.fast), '4 passes');
        expect(getPassCount(StabilizationMode.slow), '10 passes');
      });

      test('can be compared', () {
        expect(StabilizationMode.fast == StabilizationMode.fast, isTrue);
        expect(StabilizationMode.fast == StabilizationMode.slow, isFalse);
        expect(StabilizationMode.slow == StabilizationMode.slow, isTrue);
      });

      test('can be stored and retrieved by name', () {
        // Simulate storing to database as string
        const mode = StabilizationMode.slow;
        final storedValue = mode.name;

        // Simulate retrieving from database
        final retrievedMode = StabilizationMode.fromString(storedValue);

        expect(retrievedMode, mode);
      });

      test('roundtrip through name works for both modes', () {
        for (final mode in StabilizationMode.values) {
          final name = mode.name;
          final restored = StabilizationMode.fromString(name);
          expect(restored, mode, reason: 'Failed for mode: $mode');
        }
      });
    });

    group('index values', () {
      test('fast has index 0', () {
        expect(StabilizationMode.fast.index, 0);
      });

      test('slow has index 1', () {
        expect(StabilizationMode.slow.index, 1);
      });

      test('can be accessed by index', () {
        expect(StabilizationMode.values[0], StabilizationMode.fast);
        expect(StabilizationMode.values[1], StabilizationMode.slow);
      });
    });
  });
}
