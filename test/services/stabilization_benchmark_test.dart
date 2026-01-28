import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/stabilization_benchmark.dart';
import 'package:agelapse/models/stabilization_mode.dart';

void main() {
  group('StabilizationBenchmark', () {
    late StabilizationBenchmark benchmark;

    setUp(() {
      benchmark = StabilizationBenchmark();
    });

    group('initial state', () {
      test('count is 0 when empty', () {
        expect(benchmark.count, equals(0));
      });

      test('toMap returns count 0 when empty', () {
        final map = benchmark.toMap();
        expect(map['count'], equals(0));
        expect(map.length, equals(1));
      });
    });

    group('addResult', () {
      test('increments count when adding score', () {
        benchmark.addResult(finalScore: 0.5);
        expect(benchmark.count, equals(1));
      });

      test('increments count for each added score', () {
        benchmark.addResult(finalScore: 0.1);
        benchmark.addResult(finalScore: 0.2);
        benchmark.addResult(finalScore: 0.3);
        expect(benchmark.count, equals(3));
      });

      test('does not increment count when score is null', () {
        benchmark.addResult(finalEyeDeltaY: 5.0);
        expect(benchmark.count, equals(0));
      });

      test('stores mode on first result', () {
        benchmark.addResult(
          finalScore: 0.5,
          mode: StabilizationMode.fast,
        );
        final map = benchmark.toMap();
        expect(map['count'], equals(1));
      });

      test('stores goalEyeDistance when provided', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDistance: 100.0,
          goalEyeDistance: 95.0,
        );
        final map = benchmark.toMap();
        expect(map['goalEyeDistance'], equals(95.0));
      });

      test('only stores first goalEyeDistance', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDistance: 100.0,
          goalEyeDistance: 95.0,
        );
        benchmark.addResult(
          finalScore: 0.6,
          finalEyeDistance: 90.0,
          goalEyeDistance: 105.0,
        );
        final map = benchmark.toMap();
        expect(map['goalEyeDistance'], equals(95.0));
      });
    });

    group('reset', () {
      test('clears all accumulated data', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDeltaY: 2.0,
          finalEyeDistance: 100.0,
          goalEyeDistance: 95.0,
          mode: StabilizationMode.fast,
        );
        benchmark.addResult(finalScore: 0.3);

        expect(benchmark.count, equals(2));

        benchmark.reset();

        expect(benchmark.count, equals(0));
        final map = benchmark.toMap();
        expect(map['count'], equals(0));
        expect(map.length, equals(1));
      });
    });

    group('toMap statistics', () {
      test('calculates mean correctly', () {
        benchmark.addResult(finalScore: 1.0);
        benchmark.addResult(finalScore: 2.0);
        benchmark.addResult(finalScore: 3.0);

        final map = benchmark.toMap();
        expect(map['position']['mean'], equals(2.0));
      });

      test('calculates median correctly for odd count', () {
        benchmark.addResult(finalScore: 1.0);
        benchmark.addResult(finalScore: 5.0);
        benchmark.addResult(finalScore: 3.0);

        final map = benchmark.toMap();
        expect(map['position']['median'], equals(3.0));
      });

      test('calculates median correctly for even count', () {
        benchmark.addResult(finalScore: 1.0);
        benchmark.addResult(finalScore: 2.0);
        benchmark.addResult(finalScore: 3.0);
        benchmark.addResult(finalScore: 4.0);

        final map = benchmark.toMap();
        expect(map['position']['median'], equals(2.5));
      });

      test('calculates min and max correctly', () {
        benchmark.addResult(finalScore: 5.0);
        benchmark.addResult(finalScore: 1.0);
        benchmark.addResult(finalScore: 3.0);

        final map = benchmark.toMap();
        expect(map['position']['min'], equals(1.0));
        expect(map['position']['max'], equals(5.0));
      });

      test('calculates standard deviation correctly', () {
        // Values: 2, 4, 4, 4, 5, 5, 7, 9 (mean = 5)
        // Variance = ((2-5)^2 + (4-5)^2*3 + (5-5)^2*2 + (7-5)^2 + (9-5)^2) / 8
        //          = (9 + 3 + 0 + 4 + 16) / 8 = 32 / 8 = 4
        // StdDev = sqrt(4) = 2
        benchmark.addResult(finalScore: 2.0);
        benchmark.addResult(finalScore: 4.0);
        benchmark.addResult(finalScore: 4.0);
        benchmark.addResult(finalScore: 4.0);
        benchmark.addResult(finalScore: 5.0);
        benchmark.addResult(finalScore: 5.0);
        benchmark.addResult(finalScore: 7.0);
        benchmark.addResult(finalScore: 9.0);

        final map = benchmark.toMap();
        expect(map['position']['stdDev'], closeTo(2.0, 0.001));
      });

      test('calculates 95th percentile correctly', () {
        // Add 20 values from 1 to 20
        for (int i = 1; i <= 20; i++) {
          benchmark.addResult(finalScore: i.toDouble());
        }

        final map = benchmark.toMap();
        // 95th percentile of 1-20 should be close to 19
        expect(map['position']['p95'], closeTo(19.05, 0.1));
      });

      test('handles single value correctly', () {
        benchmark.addResult(finalScore: 5.0);

        final map = benchmark.toMap();
        expect(map['position']['mean'], equals(5.0));
        expect(map['position']['median'], equals(5.0));
        expect(map['position']['min'], equals(5.0));
        expect(map['position']['max'], equals(5.0));
        expect(map['position']['stdDev'], equals(0.0));
      });
    });

    group('rotation metrics', () {
      test('captures rotation error from finalEyeDeltaY', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDeltaY: -3.0, // Negative should become positive (abs)
        );
        benchmark.addResult(
          finalScore: 0.6,
          finalEyeDeltaY: 5.0,
        );

        final map = benchmark.toMap();
        expect(map['rotation'], isNotNull);
        expect(map['rotation']['mean'], equals(4.0)); // (3 + 5) / 2
      });

      test('rotation is null when no rotation errors added', () {
        benchmark.addResult(finalScore: 0.5);

        final map = benchmark.toMap();
        expect(map['rotation'], isNull);
      });

      test('takes absolute value of eye delta', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDeltaY: -10.0,
        );

        final map = benchmark.toMap();
        expect(map['rotation']['mean'], equals(10.0));
      });
    });

    group('scale metrics', () {
      test('captures scale error from eye distance difference', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDistance: 100.0,
          goalEyeDistance: 95.0,
        );
        benchmark.addResult(
          finalScore: 0.6,
          finalEyeDistance: 90.0,
          goalEyeDistance: 95.0,
        );

        final map = benchmark.toMap();
        expect(map['scale'], isNotNull);
        expect(map['scale']['mean'], equals(5.0)); // (5 + 5) / 2
      });

      test('scale is null when no scale errors added', () {
        benchmark.addResult(finalScore: 0.5);

        final map = benchmark.toMap();
        expect(map['scale'], isNull);
      });

      test('requires both finalEyeDistance and goalEyeDistance', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDistance: 100.0,
        );

        final map = benchmark.toMap();
        expect(map['scale'], isNull);
      });
    });

    group('logSummary', () {
      test('does not throw when empty', () {
        expect(() => benchmark.logSummary(), returnsNormally);
      });

      test('does not throw with data', () {
        benchmark.addResult(
          finalScore: 0.5,
          finalEyeDeltaY: 2.0,
          finalEyeDistance: 100.0,
          goalEyeDistance: 95.0,
          mode: StabilizationMode.fast,
        );
        expect(() => benchmark.logSummary(), returnsNormally);
      });

      test('does not throw with multiple results', () {
        for (int i = 0; i < 10; i++) {
          benchmark.addResult(
            finalScore: i * 0.1,
            finalEyeDeltaY: i * 0.5,
            finalEyeDistance: 90.0 + i,
            goalEyeDistance: 95.0,
          );
        }
        expect(() => benchmark.logSummary(), returnsNormally);
      });
    });

    group('edge cases', () {
      test('handles zero scores', () {
        benchmark.addResult(finalScore: 0.0);
        benchmark.addResult(finalScore: 0.0);

        final map = benchmark.toMap();
        expect(map['position']['mean'], equals(0.0));
        expect(map['position']['stdDev'], equals(0.0));
      });

      test('handles very large values', () {
        benchmark.addResult(finalScore: 1000000.0);
        benchmark.addResult(finalScore: 2000000.0);

        final map = benchmark.toMap();
        expect(map['position']['mean'], equals(1500000.0));
      });

      test('handles very small values', () {
        benchmark.addResult(finalScore: 0.000001);
        benchmark.addResult(finalScore: 0.000002);

        final map = benchmark.toMap();
        expect(map['position']['mean'], closeTo(0.0000015, 0.0000001));
      });
    });
  });
}
