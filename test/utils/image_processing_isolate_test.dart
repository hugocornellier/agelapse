import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/image_processing_isolate.dart';

/// Unit tests for image_processing_isolate.dart.
/// Tests ImageProcessingInput, ImageProcessingOutput, and platform detection.
void main() {
  group('ImageProcessingInput', () {
    test('can be instantiated with required parameters', () {
      final input = ImageProcessingInput(
        bytes: Uint8List.fromList([1, 2, 3]),
        extension: '.jpg',
      );
      expect(input, isNotNull);
      expect(input, isA<ImageProcessingInput>());
    });

    test('stores bytes correctly', () {
      final bytes = Uint8List.fromList([10, 20, 30]);
      final input = ImageProcessingInput(bytes: bytes, extension: '.png');
      expect(input.bytes, equals(bytes));
    });

    test('stores extension correctly', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.png',
      );
      expect(input.extension, '.png');
    });

    test('has default rotation of null', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
      );
      expect(input.rotation, isNull);
    });

    test('has default applyMirroring of false', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
      );
      expect(input.applyMirroring, isFalse);
    });

    test('has default thumbnailWidth of 500', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
      );
      expect(input.thumbnailWidth, 500);
    });

    test('has default thumbnailQuality of 90', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
      );
      expect(input.thumbnailQuality, 90);
    });

    test('accepts custom rotation values', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
        rotation: 'Landscape Left',
      );
      expect(input.rotation, 'Landscape Left');
    });

    test('accepts Landscape Right rotation', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
        rotation: 'Landscape Right',
      );
      expect(input.rotation, 'Landscape Right');
    });

    test('accepts custom mirroring', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
        applyMirroring: true,
      );
      expect(input.applyMirroring, isTrue);
    });

    test('accepts custom thumbnail dimensions', () {
      final input = ImageProcessingInput(
        bytes: Uint8List(0),
        extension: '.jpg',
        thumbnailWidth: 200,
        thumbnailQuality: 75,
      );
      expect(input.thumbnailWidth, 200);
      expect(input.thumbnailQuality, 75);
    });
  });

  group('ImageProcessingOutput', () {
    test('can be instantiated with success', () {
      final output = ImageProcessingOutput(
        success: true,
        width: 1920,
        height: 1080,
      );
      expect(output.success, isTrue);
      expect(output.width, 1920);
      expect(output.height, 1080);
    });

    test('has default null processedBytes', () {
      final output = ImageProcessingOutput(success: true);
      expect(output.processedBytes, isNull);
    });

    test('has default null thumbnailBytes', () {
      final output = ImageProcessingOutput(success: true);
      expect(output.thumbnailBytes, isNull);
    });

    test('has default width and height of 0', () {
      final output = ImageProcessingOutput(success: true);
      expect(output.width, 0);
      expect(output.height, 0);
    });

    test('has default null error', () {
      final output = ImageProcessingOutput(success: true);
      expect(output.error, isNull);
    });

    test('stores processedBytes correctly', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final output = ImageProcessingOutput(
        success: true,
        processedBytes: bytes,
      );
      expect(output.processedBytes, equals(bytes));
    });

    test('stores thumbnailBytes correctly', () {
      final thumbBytes = Uint8List.fromList([4, 5, 6]);
      final output = ImageProcessingOutput(
        success: true,
        thumbnailBytes: thumbBytes,
      );
      expect(output.thumbnailBytes, equals(thumbBytes));
    });
  });

  group('ImageProcessingOutput.failure', () {
    test('creates failure output with error message', () {
      const output = ImageProcessingOutput.failure('test error');
      expect(output.success, isFalse);
      expect(output.error, 'test error');
    });

    test('failure output has null bytes', () {
      const output = ImageProcessingOutput.failure('error');
      expect(output.processedBytes, isNull);
      expect(output.thumbnailBytes, isNull);
    });

    test('failure output has zero dimensions', () {
      const output = ImageProcessingOutput.failure('error');
      expect(output.width, 0);
      expect(output.height, 0);
    });
  });

  group('supportsIsolateProcessing', () {
    test('returns a boolean', () {
      expect(supportsIsolateProcessing, isA<bool>());
    });

    test('returns true on desktop platforms (macOS/Windows/Linux)', () {
      // This test runs on macOS, so should be true
      expect(supportsIsolateProcessing, isTrue);
    });
  });
}
