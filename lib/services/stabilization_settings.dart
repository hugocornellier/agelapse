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

  const StabilizationSettings({
    required this.projectOrientation,
    required this.resolution,
    required this.aspectRatio,
    required this.aspectRatioDecimal,
    required this.stabilizationMode,
    required this.eyeOffsetX,
    required this.eyeOffsetY,
    required this.projectType,
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
    ]);

    final aspectRatio = results[2] as String;
    final projectType = results[6];
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
    );
  }
}
