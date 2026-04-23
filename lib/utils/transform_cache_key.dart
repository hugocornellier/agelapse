import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../services/stabilization_settings.dart';

class TransformCacheKey {
  TransformCacheKey._();

  static const int schemaVersion = 1;
  static const String defaultScope = 'auto';
  static const String transformAlgorithmVersion =
      'face_stabilizer_transform_v1';

  static String buildCacheKey({
    required int projectId,
    required String fingerprint,
    required String projectType,
    required String modelVersion,
    required String settingsHash,
    String algorithmVersion = transformAlgorithmVersion,
    String scope = defaultScope,
  }) {
    return _sha256OfCanonicalJson({
      'schemaVersion': schemaVersion,
      'projectID': projectId,
      'fingerprint': fingerprint,
      'projectType': projectType,
      'modelVersion': modelVersion,
      'transformAlgorithmVersion': algorithmVersion,
      'settingsHash': settingsHash,
      'scope': scope,
    });
  }

  static String buildSettingsHash({
    required StabilizationSettings settings,
    required int canvasWidth,
    required int canvasHeight,
  }) {
    return _sha256OfCanonicalJson({
      'schemaVersion': schemaVersion,
      'projectType': settings.projectType,
      'projectOrientation': settings.projectOrientation,
      'resolution': settings.resolution,
      'aspectRatio': settings.aspectRatio,
      'canvasWidth': canvasWidth,
      'canvasHeight': canvasHeight,
      'eyeOffsetX': _canonicalDouble(settings.eyeOffsetX),
      'eyeOffsetY': _canonicalDouble(settings.eyeOffsetY),
      'backgroundColorBGR': settings.backgroundColorBGR,
      'transparentBackground': settings.backgroundColorBGR == null,
      'lossless': settings.lossless,
      'renderEngine': 'opencv_warpAffine_v1',
      'interpolation': 'INTER_CUBIC',
      'borderMode': 'BORDER_CONSTANT',
      'stabilizationMode': 'slow',
    });
  }

  static String canonicalJsonForTesting(Map<String, Object?> value) {
    return jsonEncode(_canonicalize(value));
  }

  static String _sha256OfCanonicalJson(Map<String, Object?> value) {
    final json = jsonEncode(_canonicalize(value));
    return sha256.convert(utf8.encode(json)).toString();
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        sorted[entry.key as String] = _canonicalize(entry.value);
      }
      return sorted;
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is double) {
      return _canonicalDouble(value);
    }
    return value;
  }

  static String _canonicalDouble(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    if (value == 0) return '0';

    var text = value.toStringAsFixed(12);
    while (text.contains('.') && text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
}
