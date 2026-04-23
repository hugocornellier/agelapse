import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/stabilization_settings.dart';
import 'package:agelapse/utils/transform_cache_key.dart';

void main() {
  group('TransformCacheKey settings hash', () {
    test('canonical JSON sorts map keys', () {
      final a = TransformCacheKey.canonicalJsonForTesting({
        'z': 1,
        'a': {'b': 2, 'a': 1},
      });
      final b = TransformCacheKey.canonicalJsonForTesting({
        'a': {'a': 1, 'b': 2},
        'z': 1,
      });

      expect(a, b);
      expect(a, '{"a":{"a":1,"b":2},"z":1}');
    });

    test('same settings produce same hash', () {
      final a = _settingsHash(_settings());
      final b = _settingsHash(_settings());

      expect(a, b);
    });

    test('transform-affecting settings change the hash', () {
      final base = _settingsHash(_settings());

      expect(
        _settingsHash(_settings(projectOrientation: 'landscape')),
        isNot(base),
      );
      expect(_settingsHash(_settings(resolution: '4K')), isNot(base));
      expect(_settingsHash(_settings(aspectRatio: '4:3')), isNot(base));
      expect(_settingsHash(_settings(eyeOffsetX: 0.2)), isNot(base));
      expect(_settingsHash(_settings(eyeOffsetY: 0.42)), isNot(base));
      expect(
        _settingsHash(_settings(backgroundColorBGR: const [255, 255, 255])),
        isNot(base),
      );
      expect(_settingsHash(_settings(backgroundColorBGR: null)), isNot(base));
      expect(_settingsHash(_settings(lossless: true)), isNot(base));
      expect(_settingsHash(_settings(), canvasWidth: 1080), isNot(base));
      expect(_settingsHash(_settings(), canvasHeight: 1920), isNot(base));
    });
  });

  group('TransformCacheKey cache key', () {
    test('same identity payload produces same key', () {
      final a = _cacheKey();
      final b = _cacheKey();

      expect(a, b);
    });

    test('identity fields change the key', () {
      final base = _cacheKey();

      expect(_cacheKey(projectId: 2), isNot(base));
      expect(_cacheKey(fingerprint: '456:def'), isNot(base));
      expect(_cacheKey(projectType: 'cat'), isNot(base));
      expect(_cacheKey(modelVersion: 'face-model-v2'), isNot(base));
      expect(_cacheKey(settingsHash: 'settings-2'), isNot(base));
      expect(_cacheKey(algorithmVersion: 'transform-v2'), isNot(base));
      expect(_cacheKey(scope: 'manual'), isNot(base));
    });
  });
}

String _settingsHash(
  StabilizationSettings settings, {
  int canvasWidth = 1920,
  int canvasHeight = 1080,
}) {
  return TransformCacheKey.buildSettingsHash(
    settings: settings,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
  );
}

String _cacheKey({
  int projectId = 1,
  String fingerprint = '123:abc',
  String projectType = 'face',
  String modelVersion = 'face-model-v1',
  String settingsHash = 'settings-1',
  String algorithmVersion = 'transform-v1',
  String scope = 'auto',
}) {
  return TransformCacheKey.buildCacheKey(
    projectId: projectId,
    fingerprint: fingerprint,
    projectType: projectType,
    modelVersion: modelVersion,
    settingsHash: settingsHash,
    algorithmVersion: algorithmVersion,
    scope: scope,
  );
}

StabilizationSettings _settings({
  String projectOrientation = 'portrait',
  String resolution = '1080p',
  String aspectRatio = '16:9',
  double aspectRatioDecimal = 16 / 9,
  double eyeOffsetX = 0.16,
  double eyeOffsetY = 0.38,
  String projectType = 'face',
  List<int>? backgroundColorBGR = const [0, 0, 0],
  bool lossless = false,
}) {
  return StabilizationSettings(
    projectOrientation: projectOrientation,
    resolution: resolution,
    aspectRatio: aspectRatio,
    aspectRatioDecimal: aspectRatioDecimal,
    eyeOffsetX: eyeOffsetX,
    eyeOffsetY: eyeOffsetY,
    projectType: projectType,
    backgroundColorBGR: backgroundColorBGR,
    lossless: lossless,
  );
}
