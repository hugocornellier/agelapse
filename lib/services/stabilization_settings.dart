import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';
import 'database_helper.dart';

/// Immutable settings bundle for stabilization pipeline.
/// Loaded once per stabilization run, eliminating per-photo DB queries.
class StabilizationSettings {
  final String projectOrientation;
  final String resolution;
  final String aspectRatio;
  final double aspectRatioDecimal;
  final String stabilizationMode;
  final double eyeOffsetX;
  final double eyeOffsetY;
  final String projectType;
  final List<int> backgroundColorBGR; // [B, G, R] for OpenCV Scalar

  const StabilizationSettings({
    required this.projectOrientation,
    required this.resolution,
    required this.aspectRatio,
    required this.aspectRatioDecimal,
    required this.stabilizationMode,
    required this.eyeOffsetX,
    required this.eyeOffsetY,
    required this.projectType,
    required this.backgroundColorBGR,
  });

  /// Load all settings in parallel (single DB round-trip batch)
  static Future<StabilizationSettings> load(int projectId) async {
    final results = await Future.wait([
      SettingsUtil.loadProjectOrientation(projectId.toString()),
      SettingsUtil.loadVideoResolution(projectId.toString()),
      SettingsUtil.loadAspectRatio(projectId.toString()),
      SettingsUtil.loadStabilizationMode(),
      SettingsUtil.loadOffsetXCurrentOrientation(projectId.toString()),
      SettingsUtil.loadOffsetYCurrentOrientation(projectId.toString()),
      DB.instance.getProjectTypeByProjectId(projectId),
      SettingsUtil.loadBackgroundColor(projectId.toString()),
    ]);

    final aspectRatio = results[2] as String;
    final projectType = results[6];
    final bgColorHex = results[7] as String;

    return StabilizationSettings(
      projectOrientation: results[0] as String,
      resolution: results[1] as String,
      aspectRatio: aspectRatio,
      aspectRatioDecimal:
          StabUtils.getAspectRatioAsDecimal(aspectRatio) ?? (16 / 9),
      stabilizationMode: results[3] as String,
      eyeOffsetX: double.parse(results[4] as String),
      eyeOffsetY: double.parse(results[5] as String),
      projectType: projectType?.toLowerCase() ?? 'face',
      backgroundColorBGR: _hexToBGR(bgColorHex),
    );
  }

  /// Converts a hex string like '#FF0000' (red) to BGR list [0, 0, 255]
  static List<int> _hexToBGR(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) {
      final r = int.parse(hex.substring(0, 2), radix: 16);
      final g = int.parse(hex.substring(2, 4), radix: 16);
      final b = int.parse(hex.substring(4, 6), radix: 16);
      return [b, g, r]; // BGR order for OpenCV
    }
    return [0, 0, 0]; // Default to black
  }
}
