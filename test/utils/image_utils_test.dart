import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/image_utils.dart';

/// Unit tests for ImageUtils.
/// Tests method signatures and class structure.
void main() {
  group('ImageUtils Class', () {
    test('ImageUtils class is accessible', () {
      expect(ImageUtils, isNotNull);
    });
  });

  group('ImageUtils Decode Methods', () {
    test('decode method exists', () {
      expect(ImageUtils.decode, isA<Function>());
    });

    test('decodeWithAlpha method exists', () {
      expect(ImageUtils.decodeWithAlpha, isA<Function>());
    });
  });

  group('ImageUtils Encode Methods', () {
    test('encodeJpg method exists', () {
      expect(ImageUtils.encodeJpg, isA<Function>());
    });

    test('encodePng method exists', () {
      expect(ImageUtils.encodePng, isA<Function>());
    });
  });

  group('ImageUtils Transform Methods', () {
    test('resize method exists', () {
      expect(ImageUtils.resize, isA<Function>());
    });

    test('resizeExact method exists', () {
      expect(ImageUtils.resizeExact, isA<Function>());
    });

    test('rotateClockwise method exists', () {
      expect(ImageUtils.rotateClockwise, isA<Function>());
    });

    test('rotateCounterClockwise method exists', () {
      expect(ImageUtils.rotateCounterClockwise, isA<Function>());
    });

    test('flipHorizontal method exists', () {
      expect(ImageUtils.flipHorizontal, isA<Function>());
    });

    test('flipVertical method exists', () {
      expect(ImageUtils.flipVertical, isA<Function>());
    });
  });

  group('ImageUtils Composite Methods', () {
    test('compositeOnBlackBackground method exists', () {
      expect(ImageUtils.compositeOnBlackBackground, isA<Function>());
    });

    test('compositeBlackPng method exists', () {
      expect(ImageUtils.compositeBlackPng, isA<Function>());
    });
  });

  group('ImageUtils Thumbnail Methods', () {
    test('createThumbnail method exists', () {
      expect(ImageUtils.createThumbnail, isA<Function>());
    });

    test('createThumbnailFromPng method exists', () {
      expect(ImageUtils.createThumbnailFromPng, isA<Function>());
    });
  });

  group('ImageUtils Dimension Methods', () {
    test('getImageDimensions method exists', () {
      expect(ImageUtils.getImageDimensions, isA<Function>());
    });

    test('getImageDimensionsInIsolate method exists', () {
      expect(ImageUtils.getImageDimensionsInIsolate, isA<Function>());
    });
  });

  group('ImageUtils Validation Methods', () {
    test('validateImageInIsolate method exists', () {
      expect(ImageUtils.validateImageInIsolate, isA<Function>());
    });

    test('validateImageBytesInIsolate method exists', () {
      expect(ImageUtils.validateImageBytesInIsolate, isA<Function>());
    });
  });

  group('ImageUtils Conversion Methods', () {
    test('convertToPngInIsolate method exists', () {
      expect(ImageUtils.convertToPngInIsolate, isA<Function>());
    });
  });

  group('ImageUtils Static Nature', () {
    test('all methods are static', () {
      // These should compile without needing an instance
      // ignore: unnecessary_type_check
      expect(ImageUtils.decode is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ImageUtils.decodeWithAlpha is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ImageUtils.encodeJpg is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ImageUtils.encodePng is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ImageUtils.resize is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ImageUtils.resizeExact is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ImageUtils.createThumbnail is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ImageUtils.getImageDimensions is Function, isTrue);
    });
  });

  group('ImageUtils Empty Input Handling', () {
    // Note: OpenCV's imdecode throws CvException for empty bytes
    // These tests verify the behavior with empty input
    test('decode throws for empty bytes', () {
      final emptyBytes = Uint8List(0);
      expect(() => ImageUtils.decode(emptyBytes), throwsException);
    });

    test('decodeWithAlpha throws for empty bytes', () {
      final emptyBytes = Uint8List(0);
      expect(() => ImageUtils.decodeWithAlpha(emptyBytes), throwsException);
    });

    test('createThumbnail throws for empty bytes', () {
      final emptyBytes = Uint8List(0);
      expect(() => ImageUtils.createThumbnail(emptyBytes), throwsException);
    });

    test('createThumbnailFromPng throws for empty bytes', () {
      final emptyBytes = Uint8List(0);
      expect(
          () => ImageUtils.createThumbnailFromPng(emptyBytes), throwsException);
    });

    test('compositeBlackPng throws for empty bytes', () {
      final emptyBytes = Uint8List(0);
      expect(() => ImageUtils.compositeBlackPng(emptyBytes), throwsException);
    });

    test('getImageDimensions throws for empty bytes', () {
      final emptyBytes = Uint8List(0);
      expect(() => ImageUtils.getImageDimensions(emptyBytes), throwsException);
    });
  });

  group('ImageUtils Invalid Input Handling', () {
    test('decode handles invalid image data', () {
      final invalidBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final result = ImageUtils.decode(invalidBytes);
      expect(result.isEmpty, isTrue);
      result.dispose();
    });

    test('createThumbnail returns null for invalid data', () {
      final invalidBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final result = ImageUtils.createThumbnail(invalidBytes);
      expect(result, isNull);
    });

    test('getImageDimensions returns null for invalid data', () {
      final invalidBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final result = ImageUtils.getImageDimensions(invalidBytes);
      expect(result, isNull);
    });
  });

  group('ImageUtils Async Methods', () {
    test('validateImageInIsolate returns Future<bool>', () {
      final result = ImageUtils.validateImageInIsolate('/nonexistent/path');
      expect(result, isA<Future<bool>>());
    });

    test('validateImageBytesInIsolate returns Future<bool>', () {
      final result = ImageUtils.validateImageBytesInIsolate(Uint8List(0));
      expect(result, isA<Future<bool>>());
    });

    test('convertToPngInIsolate returns Future<Uint8List?>', () {
      final result = ImageUtils.convertToPngInIsolate(Uint8List(0));
      expect(result, isA<Future<Uint8List?>>());
    });

    test('getImageDimensionsInIsolate returns Future', () {
      final result = ImageUtils.getImageDimensionsInIsolate(Uint8List(0));
      expect(result, isA<Future>());
    });
  });

  group('ImageUtils validateImageInIsolate', () {
    test('returns false for nonexistent file', () async {
      final result = await ImageUtils.validateImageInIsolate(
          '/nonexistent/path/image.jpg');
      expect(result, isFalse);
    });
  });

  group('ImageUtils validateImageBytesInIsolate', () {
    test('returns false for empty bytes', () async {
      final result = await ImageUtils.validateImageBytesInIsolate(Uint8List(0));
      expect(result, isFalse);
    });

    test('returns false for invalid bytes', () async {
      final result = await ImageUtils.validateImageBytesInIsolate(
        Uint8List.fromList([0, 1, 2, 3, 4, 5]),
      );
      expect(result, isFalse);
    });
  });

  group('ImageUtils convertToPngInIsolate', () {
    test('returns null for empty bytes', () async {
      final result = await ImageUtils.convertToPngInIsolate(Uint8List(0));
      expect(result, isNull);
    });

    test('returns null for invalid bytes', () async {
      final result = await ImageUtils.convertToPngInIsolate(
        Uint8List.fromList([0, 1, 2, 3, 4, 5]),
      );
      expect(result, isNull);
    });
  });

  group('ImageUtils getImageDimensionsInIsolate', () {
    test('returns null for empty bytes', () async {
      final result = await ImageUtils.getImageDimensionsInIsolate(Uint8List(0));
      expect(result, isNull);
    });

    test('returns null for invalid bytes', () async {
      final result = await ImageUtils.getImageDimensionsInIsolate(
        Uint8List.fromList([0, 1, 2, 3, 4, 5]),
      );
      expect(result, isNull);
    });
  });
}
