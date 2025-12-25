import 'dart:math';
import 'log_service.dart';
import '../models/stabilization_mode.dart';

/// Accumulates stabilization metrics for benchmarking.
///
/// Usage:
/// ```dart
/// final benchmark = StabilizationBenchmark();
/// for (photo in photos) {
///   final result = await stabilizer.stabilize(photo);
///   benchmark.addResult(result);
/// }
/// benchmark.logSummary();
/// ```
class StabilizationBenchmark {
  final List<double> _scores = [];
  final List<double> _rotationErrors = []; // |eyeDeltaY| in pixels
  final List<double> _scaleErrors = []; // |eyeDistance - goalDistance| in pixels

  double? _goalEyeDistance;
  StabilizationMode? _mode;

  /// Add a stabilization result to the benchmark.
  void addResult({
    double? finalScore,
    double? finalEyeDeltaY,
    double? finalEyeDistance,
    double? goalEyeDistance,
    StabilizationMode? mode,
  }) {
    if (finalScore != null) {
      _scores.add(finalScore);
    }
    if (finalEyeDeltaY != null) {
      _rotationErrors.add(finalEyeDeltaY.abs());
    }
    if (finalEyeDistance != null && goalEyeDistance != null) {
      _scaleErrors.add((finalEyeDistance - goalEyeDistance).abs());
      _goalEyeDistance ??= goalEyeDistance;
    }
    _mode ??= mode;
  }

  /// Reset all accumulated metrics.
  void reset() {
    _scores.clear();
    _rotationErrors.clear();
    _scaleErrors.clear();
    _goalEyeDistance = null;
    _mode = null;
  }

  /// Number of results collected.
  int get count => _scores.length;

  /// Log a summary of all benchmark metrics.
  void logSummary() {
    if (_scores.isEmpty) {
      LogService.instance.log("=== STABILIZATION BENCHMARK ===");
      LogService.instance.log("No benchmark data collected");
      return;
    }

    final separator = "=" * 50;
    LogService.instance.log(separator);
    LogService.instance.log("       STABILIZATION BENCHMARK RESULTS");
    LogService.instance.log(separator);
    LogService.instance.log("Photos processed: ${_scores.length}");
    LogService.instance.log("Mode: ${_mode?.name ?? 'unknown'}");
    if (_goalEyeDistance != null) {
      LogService.instance.log("Goal eye distance: ${_goalEyeDistance!.toStringAsFixed(2)}px");
    }
    LogService.instance.log("");

    // Position Error (Stab Score)
    LogService.instance.log("POSITION ERROR (stab score, lower is better):");
    _logStats(_scores, "  ");
    LogService.instance.log("");

    // Rotation Error
    if (_rotationErrors.isNotEmpty) {
      LogService.instance.log("ROTATION ERROR (|eyeDeltaY| in px, lower is better):");
      _logStats(_rotationErrors, "  ");
      LogService.instance.log("");
    }

    // Scale Error
    if (_scaleErrors.isNotEmpty) {
      LogService.instance.log("SCALE ERROR (distance from goal in px, lower is better):");
      _logStats(_scaleErrors, "  ");
      LogService.instance.log("");
    }

    // Quality distribution
    _logQualityDistribution();

    LogService.instance.log(separator);
  }

  void _logStats(List<double> values, String prefix) {
    if (values.isEmpty) return;

    final sorted = List<double>.from(values)..sort();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final median = _percentile(sorted, 50);
    final stdDev = _standardDeviation(values, mean);
    final p95 = _percentile(sorted, 95);
    final minVal = sorted.first;
    final maxVal = sorted.last;

    LogService.instance.log("${prefix}Mean:   ${mean.toStringAsFixed(3)}");
    LogService.instance.log("${prefix}Median: ${median.toStringAsFixed(3)}");
    LogService.instance.log("${prefix}StdDev: ${stdDev.toStringAsFixed(3)}");
    LogService.instance.log("${prefix}95th:   ${p95.toStringAsFixed(3)}");
    LogService.instance.log("${prefix}Min:    ${minVal.toStringAsFixed(3)}");
    LogService.instance.log("${prefix}Max:    ${maxVal.toStringAsFixed(3)}");
  }

  void _logQualityDistribution() {
    if (_scores.isEmpty) return;

    int excellent = 0; // < 0.3
    int good = 0; // 0.3 - 0.6
    int acceptable = 0; // 0.6 - 1.0
    int poor = 0; // > 1.0

    for (final score in _scores) {
      if (score < 0.3) {
        excellent++;
      } else if (score < 0.6) {
        good++;
      } else if (score < 1.0) {
        acceptable++;
      } else {
        poor++;
      }
    }

    final total = _scores.length;
    LogService.instance.log("QUALITY DISTRIBUTION:");
    LogService.instance.log("  Excellent (< 0.3):   $excellent (${(excellent * 100 / total).toStringAsFixed(1)}%)");
    LogService.instance.log("  Good (0.3 - 0.6):    $good (${(good * 100 / total).toStringAsFixed(1)}%)");
    LogService.instance.log("  Acceptable (0.6-1):  $acceptable (${(acceptable * 100 / total).toStringAsFixed(1)}%)");
    LogService.instance.log("  Poor (> 1.0):        $poor (${(poor * 100 / total).toStringAsFixed(1)}%)");
  }

  double _percentile(List<double> sorted, int percentile) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted[0];

    final index = (percentile / 100 * (sorted.length - 1));
    final lower = index.floor();
    final upper = index.ceil();

    if (lower == upper) return sorted[lower];

    final fraction = index - lower;
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
  }

  double _standardDeviation(List<double> values, double mean) {
    if (values.length < 2) return 0;

    double sumSquaredDiff = 0;
    for (final value in values) {
      sumSquaredDiff += pow(value - mean, 2);
    }
    return sqrt(sumSquaredDiff / values.length);
  }

  /// Get benchmark data as a map (useful for saving/comparing).
  Map<String, dynamic> toMap() {
    if (_scores.isEmpty) {
      return {'count': 0};
    }

    final sortedScores = List<double>.from(_scores)..sort();
    final sortedRotation = List<double>.from(_rotationErrors)..sort();
    final sortedScale = List<double>.from(_scaleErrors)..sort();

    return {
      'count': _scores.length,
      'goalEyeDistance': _goalEyeDistance,
      'position': {
        'mean': _scores.reduce((a, b) => a + b) / _scores.length,
        'median': _percentile(sortedScores, 50),
        'stdDev': _standardDeviation(_scores, _scores.reduce((a, b) => a + b) / _scores.length),
        'p95': _percentile(sortedScores, 95),
        'min': sortedScores.first,
        'max': sortedScores.last,
      },
      'rotation': _rotationErrors.isNotEmpty ? {
        'mean': _rotationErrors.reduce((a, b) => a + b) / _rotationErrors.length,
        'median': _percentile(sortedRotation, 50),
        'stdDev': _standardDeviation(_rotationErrors, _rotationErrors.reduce((a, b) => a + b) / _rotationErrors.length),
        'p95': _percentile(sortedRotation, 95),
        'min': sortedRotation.first,
        'max': sortedRotation.last,
      } : null,
      'scale': _scaleErrors.isNotEmpty ? {
        'mean': _scaleErrors.reduce((a, b) => a + b) / _scaleErrors.length,
        'median': _percentile(sortedScale, 50),
        'stdDev': _standardDeviation(_scaleErrors, _scaleErrors.reduce((a, b) => a + b) / _scaleErrors.length),
        'p95': _percentile(sortedScale, 95),
        'min': sortedScale.first,
        'max': sortedScale.last,
      } : null,
    };
  }
}
