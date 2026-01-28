import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/stabilization_settings.dart';

void main() {
  group('StabilizationSettings', () {
    group('constructor', () {
      test('creates instance with all required parameters', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 0],
        );

        expect(settings.projectOrientation, equals('portrait'));
        expect(settings.resolution, equals('1080p'));
        expect(settings.aspectRatio, equals('9:16'));
        expect(settings.aspectRatioDecimal, equals(0.5625));
        expect(settings.stabilizationMode, equals('face'));
        expect(settings.eyeOffsetX, equals(0.5));
        expect(settings.eyeOffsetY, equals(0.35));
        expect(settings.projectType, equals('face'));
        expect(settings.backgroundColorBGR, equals([0, 0, 0]));
      });

      test('stores landscape orientation', () {
        const settings = StabilizationSettings(
          projectOrientation: 'landscape',
          resolution: '4K',
          aspectRatio: '16:9',
          aspectRatioDecimal: 1.7778,
          stabilizationMode: 'object',
          eyeOffsetX: 0.0,
          eyeOffsetY: 0.0,
          projectType: 'object',
          backgroundColorBGR: [255, 255, 255],
        );

        expect(settings.projectOrientation, equals('landscape'));
        expect(settings.aspectRatio, equals('16:9'));
        expect(settings.projectType, equals('object'));
      });

      test('stores custom background color in BGR format', () {
        // Red in BGR = [0, 0, 255]
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '720p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 255],
        );

        expect(settings.backgroundColorBGR[0], equals(0)); // B
        expect(settings.backgroundColorBGR[1], equals(0)); // G
        expect(settings.backgroundColorBGR[2], equals(255)); // R
      });

      test('stores negative eye offsets', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: -0.1,
          eyeOffsetY: -0.05,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 0],
        );

        expect(settings.eyeOffsetX, equals(-0.1));
        expect(settings.eyeOffsetY, equals(-0.05));
      });
    });

    group('immutability', () {
      test('settings are constant and can be used as const', () {
        const settings1 = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 0],
        );

        const settings2 = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 0],
        );

        // Both should be valid const instances
        expect(settings1.resolution, equals(settings2.resolution));
      });
    });

    group('resolution options', () {
      test('supports various resolution strings', () {
        final resolutions = ['720p', '1080p', '4K', '8K', '1440'];

        for (final res in resolutions) {
          final settings = StabilizationSettings(
            projectOrientation: 'portrait',
            resolution: res,
            aspectRatio: '9:16',
            aspectRatioDecimal: 0.5625,
            stabilizationMode: 'face',
            eyeOffsetX: 0.5,
            eyeOffsetY: 0.35,
            projectType: 'face',
            backgroundColorBGR: [0, 0, 0],
          );
          expect(settings.resolution, equals(res));
        }
      });
    });

    group('aspect ratio options', () {
      test('supports common aspect ratios', () {
        final aspectRatios = {
          '9:16': 0.5625,
          '16:9': 1.7778,
          '4:3': 1.3333,
          '1:1': 1.0,
        };

        for (final entry in aspectRatios.entries) {
          final settings = StabilizationSettings(
            projectOrientation: 'portrait',
            resolution: '1080p',
            aspectRatio: entry.key,
            aspectRatioDecimal: entry.value,
            stabilizationMode: 'face',
            eyeOffsetX: 0.5,
            eyeOffsetY: 0.35,
            projectType: 'face',
            backgroundColorBGR: [0, 0, 0],
          );
          expect(settings.aspectRatio, equals(entry.key));
          expect(settings.aspectRatioDecimal, closeTo(entry.value, 0.001));
        }
      });
    });

    group('stabilization modes', () {
      test('supports face stabilization mode', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 0],
        );
        expect(settings.stabilizationMode, equals('face'));
      });

      test('supports object stabilization mode', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'object',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.5,
          projectType: 'object',
          backgroundColorBGR: [0, 0, 0],
        );
        expect(settings.stabilizationMode, equals('object'));
      });
    });

    group('background color BGR format', () {
      test('black is [0, 0, 0]', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 0],
        );
        expect(settings.backgroundColorBGR, equals([0, 0, 0]));
      });

      test('white is [255, 255, 255]', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [255, 255, 255],
        );
        expect(settings.backgroundColorBGR, equals([255, 255, 255]));
      });

      test('pure red in BGR is [0, 0, 255]', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [0, 0, 255], // BGR: B=0, G=0, R=255
        );
        expect(settings.backgroundColorBGR[2], equals(255)); // R channel
      });

      test('pure blue in BGR is [255, 0, 0]', () {
        const settings = StabilizationSettings(
          projectOrientation: 'portrait',
          resolution: '1080p',
          aspectRatio: '9:16',
          aspectRatioDecimal: 0.5625,
          stabilizationMode: 'face',
          eyeOffsetX: 0.5,
          eyeOffsetY: 0.35,
          projectType: 'face',
          backgroundColorBGR: [255, 0, 0], // BGR: B=255, G=0, R=0
        );
        expect(settings.backgroundColorBGR[0], equals(255)); // B channel
      });
    });
  });
}
