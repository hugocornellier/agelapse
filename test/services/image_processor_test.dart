import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/image_processor.dart';

/// Unit tests for ImageProcessor.
/// Tests initialization, disposal, and property handling.
void main() {
  group('ImageProcessor Initialization', () {
    test('creates instance with required parameters', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.jpg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, '/path/to/image.jpg');
      expect(processor.projectId, 1);
      expect(processor.activeProcessingDateNotifier, notifier);
      expect(processor.timestamp, isNull);

      processor.dispose();
      notifier.dispose();
    });

    test('creates instance with optional timestamp', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.png',
        projectId: 2,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
        timestamp: 1234567890,
      );

      expect(processor.timestamp, 1234567890);

      processor.dispose();
      notifier.dispose();
    });

    test('creates instance with increaseSuccessfulImportCount callback', () {
      final notifier = ValueNotifier<String>('');
      int importCount = 0;

      final processor = ImageProcessor(
        imagePath: '/path/to/image.heic',
        projectId: 3,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
        increaseSuccessfulImportCount: () {
          importCount++;
        },
      );

      expect(processor.increaseSuccessfulImportCount, isNotNull);

      // Call the callback
      processor.increaseSuccessfulImportCount!();
      expect(importCount, 1);

      processor.dispose();
      notifier.dispose();
    });
  });

  group('ImageProcessor Dispose', () {
    test('dispose clears all properties', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.jpg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
        timestamp: 123456,
        increaseSuccessfulImportCount: () {},
      );

      // Verify properties before dispose
      expect(processor.imagePath, isNotNull);
      expect(processor.projectId, isNotNull);
      expect(processor.activeProcessingDateNotifier, isNotNull);
      expect(processor.timestamp, isNotNull);
      expect(processor.increaseSuccessfulImportCount, isNotNull);

      // Dispose
      processor.dispose();

      // Verify properties after dispose
      expect(processor.imagePath, isNull);
      expect(processor.projectId, isNull);
      expect(processor.activeProcessingDateNotifier, isNull);
      expect(processor.onImagesLoaded, isNull);
      expect(processor.timestamp, isNull);
      expect(processor.increaseSuccessfulImportCount, isNull);

      notifier.dispose();
    });

    test('dispose is idempotent', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.jpg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      // Should not throw
      processor.dispose();
      processor.dispose();
      processor.dispose();

      notifier.dispose();
    });
  });

  group('ImageProcessor File Extension Handling', () {
    test('handles jpg extension', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.jpg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, endsWith('.jpg'));

      processor.dispose();
      notifier.dispose();
    });

    test('handles jpeg extension', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.jpeg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, endsWith('.jpeg'));

      processor.dispose();
      notifier.dispose();
    });

    test('handles png extension', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.png',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, endsWith('.png'));

      processor.dispose();
      notifier.dispose();
    });

    test('handles heic extension', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.heic',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, endsWith('.heic'));

      processor.dispose();
      notifier.dispose();
    });

    test('handles avif extension', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.avif',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, endsWith('.avif'));

      processor.dispose();
      notifier.dispose();
    });

    test('handles webp extension', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.webp',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, endsWith('.webp'));

      processor.dispose();
      notifier.dispose();
    });
  });

  group('ImageProcessor Path Handling', () {
    test('handles paths with spaces', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/with spaces/image file.jpg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, '/path/with spaces/image file.jpg');

      processor.dispose();
      notifier.dispose();
    });

    test('handles paths with special characters', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/with-dashes_and_underscores/image (1).jpg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, contains('with-dashes_and_underscores'));
      expect(processor.imagePath, contains('(1)'));

      processor.dispose();
      notifier.dispose();
    });

    test('handles long paths', () {
      final notifier = ValueNotifier<String>('');
      final longPath =
          '/very/long/path/that/goes/on/and/on/and/on/to/test/handling/of/deeply/nested/directories/image.jpg';

      final processor = ImageProcessor(
        imagePath: longPath,
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(processor.imagePath, longPath);

      processor.dispose();
      notifier.dispose();
    });
  });

  group('ImageProcessor ValueNotifier', () {
    test('notifier can be updated', () {
      final notifier = ValueNotifier<String>('');

      final processor = ImageProcessor(
        imagePath: '/path/to/image.jpg',
        projectId: 1,
        activeProcessingDateNotifier: notifier,
        onImagesLoaded: () {},
      );

      expect(notifier.value, '');

      notifier.value = '2024-01-15';
      expect(notifier.value, '2024-01-15');

      notifier.value = 'Processing...';
      expect(notifier.value, 'Processing...');

      processor.dispose();
      notifier.dispose();
    });
  });
}
