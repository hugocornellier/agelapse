import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';

void main() {
  group('FaceLike', () {
    test('creates instance with all properties', () {
      final face = FaceLike(
        boundingBox: const Rect.fromLTWH(10, 20, 100, 150),
        leftEye: const Point(50.0, 60.0),
        rightEye: const Point(80.0, 60.0),
      );

      expect(face.boundingBox, const Rect.fromLTWH(10, 20, 100, 150));
      expect(face.leftEye, const Point(50.0, 60.0));
      expect(face.rightEye, const Point(80.0, 60.0));
    });

    test('allows null eye positions', () {
      final face = FaceLike(
        boundingBox: const Rect.fromLTWH(0, 0, 50, 50),
        leftEye: null,
        rightEye: null,
      );

      expect(face.leftEye, isNull);
      expect(face.rightEye, isNull);
    });

    test('allows partial eye positions', () {
      final faceWithLeftOnly = FaceLike(
        boundingBox: const Rect.fromLTWH(0, 0, 50, 50),
        leftEye: const Point(25.0, 25.0),
        rightEye: null,
      );

      expect(faceWithLeftOnly.leftEye, isNotNull);
      expect(faceWithLeftOnly.rightEye, isNull);
    });
  });

  group('StabUtils', () {
    group('getShortSide()', () {
      test('returns 1080 for "1080p"', () {
        expect(StabUtils.getShortSide('1080p'), 1080);
      });

      test('returns 2304 for "4K"', () {
        expect(StabUtils.getShortSide('4K'), 2304);
      });

      test('returns 4320 for "8K"', () {
        expect(StabUtils.getShortSide('8K'), 4320);
      });

      test('returns 1152 for legacy "2K"', () {
        expect(StabUtils.getShortSide('2K'), 1152);
      });

      test('returns 1728 for legacy "3K"', () {
        expect(StabUtils.getShortSide('3K'), 1728);
      });

      test('parses custom numeric resolution strings', () {
        expect(StabUtils.getShortSide('1728'), 1728);
        expect(StabUtils.getShortSide('1440'), 1440);
        expect(StabUtils.getShortSide('2160'), 2160);
        expect(StabUtils.getShortSide('480'), 480);
        expect(StabUtils.getShortSide('5400'), 5400);
      });

      test('returns null for custom values outside valid range', () {
        expect(StabUtils.getShortSide('479'), isNull); // Below min
        expect(StabUtils.getShortSide('5401'), isNull); // Above max
        expect(StabUtils.getShortSide('100'), isNull); // Way below min
        expect(StabUtils.getShortSide('10000'), isNull); // Way above max
      });

      test('returns null for unknown resolution strings', () {
        expect(StabUtils.getShortSide('720p'), isNull);
        expect(StabUtils.getShortSide('unknown'), isNull);
        expect(StabUtils.getShortSide(''), isNull);
        expect(StabUtils.getShortSide('abc'), isNull);
      });

      test('is case sensitive for presets', () {
        expect(StabUtils.getShortSide('1080P'), isNull);
        expect(StabUtils.getShortSide('4k'), isNull);
        expect(StabUtils.getShortSide('8k'), isNull);
        expect(StabUtils.getShortSide('2k'), isNull);
        expect(StabUtils.getShortSide('3k'), isNull);
      });

      test('parses WIDTHxHEIGHT format and returns short side', () {
        expect(StabUtils.getShortSide('1920x1080'), 1080); // Landscape
        expect(StabUtils.getShortSide('1080x1920'), 1080); // Portrait
        expect(StabUtils.getShortSide('3840x2160'), 2160); // 4K landscape
        expect(StabUtils.getShortSide('2160x3840'), 2160); // 4K portrait
        expect(StabUtils.getShortSide('7680x4320'), 4320); // 8K
        expect(StabUtils.getShortSide('480x854'), 480); // Low res
      });

      test('returns null for invalid WIDTHxHEIGHT formats', () {
        expect(StabUtils.getShortSide('1920x'), isNull);
        expect(StabUtils.getShortSide('x1080'), isNull);
        expect(StabUtils.getShortSide('1920 x 1080'), isNull); // Spaces
        expect(StabUtils.getShortSide('1920X1080'), isNull); // Uppercase X
      });
    });

    group('getDimensions()', () {
      test('parses WIDTHxHEIGHT format correctly', () {
        expect(StabUtils.getDimensions('1920x1080'), (1920, 1080));
        expect(StabUtils.getDimensions('1080x1920'), (1080, 1920));
        expect(StabUtils.getDimensions('3840x2160'), (3840, 2160));
        expect(StabUtils.getDimensions('7680x4320'), (7680, 4320));
      });

      test('returns null for non-WIDTHxHEIGHT formats', () {
        expect(StabUtils.getDimensions('1080p'), isNull);
        expect(StabUtils.getDimensions('4K'), isNull);
        expect(StabUtils.getDimensions('1728'), isNull);
        expect(StabUtils.getDimensions(''), isNull);
        expect(StabUtils.getDimensions('invalid'), isNull);
      });
    });

    group('getOutputDimensions()', () {
      test('returns exact dimensions for custom WIDTHxHEIGHT format', () {
        // Custom square resolution - should return exact dimensions
        expect(
          StabUtils.getOutputDimensions('7000x7000', '16:9', 'landscape'),
          (7000, 7000),
        );
        expect(StabUtils.getOutputDimensions('7000x7000', '16:9', 'portrait'), (
          7000,
          7000,
        ));
        // Aspect ratio and orientation should be ignored for custom
        expect(StabUtils.getOutputDimensions('1920x1080', '4:3', 'portrait'), (
          1920,
          1080,
        ));
      });

      test(
        'calculates dimensions from preset + aspect ratio + orientation',
        () {
          // 1080p landscape 16:9 -> 1920x1080
          expect(StabUtils.getOutputDimensions('1080p', '16:9', 'landscape'), (
            1920,
            1080,
          ));
          // 1080p portrait 16:9 -> 1080x1920
          expect(StabUtils.getOutputDimensions('1080p', '16:9', 'portrait'), (
            1080,
            1920,
          ));
          // 4K landscape 16:9 -> 4096x2304
          expect(StabUtils.getOutputDimensions('4K', '16:9', 'landscape'), (
            4096,
            2304,
          ));
          // 1080p landscape 4:3 -> 1440x1080
          expect(StabUtils.getOutputDimensions('1080p', '4:3', 'landscape'), (
            1440,
            1080,
          ));
        },
      );

      test('handles case-insensitive orientation', () {
        expect(StabUtils.getOutputDimensions('1080p', '16:9', 'Landscape'), (
          1920,
          1080,
        ));
        expect(StabUtils.getOutputDimensions('1080p', '16:9', 'LANDSCAPE'), (
          1920,
          1080,
        ));
        expect(StabUtils.getOutputDimensions('1080p', '16:9', 'Portrait'), (
          1080,
          1920,
        ));
      });

      test('returns null for invalid resolution', () {
        expect(
          StabUtils.getOutputDimensions('invalid', '16:9', 'landscape'),
          isNull,
        );
        expect(StabUtils.getOutputDimensions('', '16:9', 'landscape'), isNull);
      });

      test('returns null for invalid aspect ratio', () {
        expect(
          StabUtils.getOutputDimensions('1080p', 'invalid', 'landscape'),
          isNull,
        );
      });
    });

    group('getAspectRatioAsDecimal()', () {
      test('parses "16:9" correctly', () {
        expect(
          StabUtils.getAspectRatioAsDecimal('16:9'),
          closeTo(1.778, 0.001),
        );
      });

      test('parses "4:3" correctly', () {
        expect(StabUtils.getAspectRatioAsDecimal('4:3'), closeTo(1.333, 0.001));
      });

      test('parses "1:1" correctly', () {
        expect(StabUtils.getAspectRatioAsDecimal('1:1'), 1.0);
      });

      test('parses "9:16" correctly (portrait)', () {
        expect(
          StabUtils.getAspectRatioAsDecimal('9:16'),
          closeTo(0.5625, 0.001),
        );
      });

      test('parses "21:9" ultrawide correctly', () {
        expect(
          StabUtils.getAspectRatioAsDecimal('21:9'),
          closeTo(2.333, 0.001),
        );
      });

      test('returns null for string without colon', () {
        expect(StabUtils.getAspectRatioAsDecimal('16x9'), isNull);
        expect(StabUtils.getAspectRatioAsDecimal('landscape'), isNull);
        expect(StabUtils.getAspectRatioAsDecimal(''), isNull);
      });

      test('returns null for invalid numbers', () {
        expect(StabUtils.getAspectRatioAsDecimal('abc:def'), isNull);
        expect(StabUtils.getAspectRatioAsDecimal(':9'), isNull);
        expect(StabUtils.getAspectRatioAsDecimal('16:'), isNull);
        expect(StabUtils.getAspectRatioAsDecimal(':'), isNull);
      });

      test('handles whitespace in numbers', () {
        // Implementation trims/handles whitespace
        expect(
          StabUtils.getAspectRatioAsDecimal(' 16:9'),
          closeTo(1.778, 0.001),
        );
        expect(
          StabUtils.getAspectRatioAsDecimal('16 :9'),
          closeTo(1.778, 0.001),
        );
      });
    });

    group('embeddingToBytes() and bytesToEmbedding()', () {
      test('roundtrip preserves data', () {
        final original = Float32List.fromList([1.0, 2.5, -3.7, 0.0, 100.123]);

        final bytes = StabUtils.embeddingToBytes(original);
        final restored = StabUtils.bytesToEmbedding(bytes);

        expect(restored.length, original.length);
        for (var i = 0; i < original.length; i++) {
          expect(restored[i], closeTo(original[i], 0.0001));
        }
      });

      test('embeddingToBytes returns correct byte length', () {
        final embedding = Float32List.fromList([1.0, 2.0, 3.0]);
        final bytes = StabUtils.embeddingToBytes(embedding);

        // Float32 is 4 bytes per element
        expect(bytes.length, 12);
      });

      test('handles empty embedding', () {
        final original = Float32List(0);
        final bytes = StabUtils.embeddingToBytes(original);
        final restored = StabUtils.bytesToEmbedding(bytes);

        expect(restored.length, 0);
      });

      test('handles typical 192-dim face embedding', () {
        // Typical face embedding size
        final embedding = Float32List(192);
        for (var i = 0; i < 192; i++) {
          embedding[i] = i * 0.01;
        }

        final bytes = StabUtils.embeddingToBytes(embedding);
        expect(bytes.length, 192 * 4);

        final restored = StabUtils.bytesToEmbedding(bytes);
        expect(restored.length, 192);
        expect(restored[100], closeTo(1.0, 0.0001));
      });

      test('preserves negative values', () {
        final original = Float32List.fromList([-1.0, -0.5, 0.0, 0.5, 1.0]);
        final bytes = StabUtils.embeddingToBytes(original);
        final restored = StabUtils.bytesToEmbedding(bytes);

        expect(restored[0], closeTo(-1.0, 0.0001));
        expect(restored[1], closeTo(-0.5, 0.0001));
        expect(restored[4], closeTo(1.0, 0.0001));
      });

      test('preserves very small values', () {
        final original = Float32List.fromList([0.0001, 0.00001, -0.0001]);
        final bytes = StabUtils.embeddingToBytes(original);
        final restored = StabUtils.bytesToEmbedding(bytes);

        expect(restored[0], closeTo(0.0001, 0.00001));
        expect(restored[1], closeTo(0.00001, 0.000001));
      });

      test('preserves large values', () {
        final original = Float32List.fromList([1000000.0, -1000000.0]);
        final bytes = StabUtils.embeddingToBytes(original);
        final restored = StabUtils.bytesToEmbedding(bytes);

        expect(restored[0], closeTo(1000000.0, 1.0));
        expect(restored[1], closeTo(-1000000.0, 1.0));
      });
    });
  });
}
