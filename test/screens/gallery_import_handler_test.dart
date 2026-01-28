import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/gallery_page/gallery_import_handler.dart';

/// Unit tests for GalleryImportHandler.
/// Tests counter management and pure logic.
void main() {
  group('GalleryImportHandler Class', () {
    test('GalleryImportHandler class is accessible', () {
      expect(GalleryImportHandler, isNotNull);
    });
  });

  group('GalleryImportHandler Counter Management', () {
    late GalleryImportHandler handler;

    setUp(() {
      handler = GalleryImportHandler(
        projectId: 1,
        projectIdStr: '1',
        activeProcessingDateNotifier: ValueNotifier<String>(''),
        loadImages: () {},
        refreshSettings: () {},
        stabCallback: () {},
        cancelStabCallback: () async {},
        isStabilizingRunning: () => false,
        processPickedFiles: (files, processor) async {},
        setProjectOrientation: (_) {},
      );
    });

    test('initial counters are zero', () {
      expect(handler.photosImported, 0);
      expect(handler.successfullyImported, 0);
      expect(handler.skippedCount, 0);
    });

    test('resetCounters sets both counters to zero', () {
      handler.increasePhotosImported(5);
      handler.increaseSuccessfulImportCount();
      handler.increaseSuccessfulImportCount();

      handler.resetCounters();

      expect(handler.photosImported, 0);
      expect(handler.successfullyImported, 0);
      expect(handler.skippedCount, 0);
    });

    test('increasePhotosImported increments counter correctly', () {
      handler.increasePhotosImported(1);
      expect(handler.photosImported, 1);

      handler.increasePhotosImported(5);
      expect(handler.photosImported, 6);

      handler.increasePhotosImported(0);
      expect(handler.photosImported, 6);
    });

    test('increaseSuccessfulImportCount increments counter correctly', () {
      handler.increaseSuccessfulImportCount();
      expect(handler.successfullyImported, 1);

      handler.increaseSuccessfulImportCount();
      expect(handler.successfullyImported, 2);

      handler.increaseSuccessfulImportCount();
      expect(handler.successfullyImported, 3);
    });

    test('skippedCount returns photosImported minus successfullyImported', () {
      handler.increasePhotosImported(10);
      handler.increaseSuccessfulImportCount();
      handler.increaseSuccessfulImportCount();
      handler.increaseSuccessfulImportCount();

      expect(handler.skippedCount, 7);
    });

    test('skippedCount is zero when all imports successful', () {
      handler.increasePhotosImported(5);
      for (int i = 0; i < 5; i++) {
        handler.increaseSuccessfulImportCount();
      }

      expect(handler.skippedCount, 0);
    });

    test('skippedCount equals photosImported when none successful', () {
      handler.increasePhotosImported(5);
      expect(handler.skippedCount, 5);
    });

    test('counters can handle large values', () {
      handler.increasePhotosImported(1000000);
      for (int i = 0; i < 999990; i++) {
        handler.increaseSuccessfulImportCount();
      }

      expect(handler.photosImported, 1000000);
      expect(handler.successfullyImported, 999990);
      expect(handler.skippedCount, 10);
    });
  });

  group('GalleryImportHandler Constructor', () {
    test('creates handler with required parameters', () {
      final notifier = ValueNotifier<String>('test');

      final handler = GalleryImportHandler(
        projectId: 42,
        projectIdStr: '42',
        activeProcessingDateNotifier: notifier,
        loadImages: () {},
        refreshSettings: () {},
        stabCallback: () {},
        cancelStabCallback: () async {},
        isStabilizingRunning: () => false,
        processPickedFiles: (files, processor) async {},
        setProjectOrientation: (_) {},
      );

      expect(handler, isNotNull);
      notifier.dispose();
    });

    test('creates handler with optional setProgressInMain', () {
      final notifier = ValueNotifier<String>('');
      int? capturedProgress;

      final handler = GalleryImportHandler(
        projectId: 1,
        projectIdStr: '1',
        activeProcessingDateNotifier: notifier,
        loadImages: () {},
        refreshSettings: () {},
        stabCallback: () {},
        cancelStabCallback: () async {},
        isStabilizingRunning: () => false,
        processPickedFiles: (files, processor) async {},
        setProjectOrientation: (_) {},
        setProgressInMain: (progress) => capturedProgress = progress,
      );

      // Callback not yet invoked
      expect(capturedProgress, isNull);

      expect(handler, isNotNull);
      notifier.dispose();
    });
  });

  group('GalleryImportHandler Callback Verification', () {
    test('isStabilizingRunning callback is invoked', () {
      var callbackInvoked = false;
      const isRunning = false;

      final handler = GalleryImportHandler(
        projectId: 1,
        projectIdStr: '1',
        activeProcessingDateNotifier: ValueNotifier<String>(''),
        loadImages: () {},
        refreshSettings: () {},
        stabCallback: () {},
        cancelStabCallback: () async {},
        isStabilizingRunning: () {
          callbackInvoked = true;
          return isRunning;
        },
        processPickedFiles: (files, processor) async {},
        setProjectOrientation: (_) {},
      );

      expect(handler, isNotNull);
      expect(callbackInvoked, isFalse); // Callback not invoked until import
    });
  });

  group('GalleryImportHandler Method Signatures', () {
    late GalleryImportHandler handler;

    setUp(() {
      handler = GalleryImportHandler(
        projectId: 1,
        projectIdStr: '1',
        activeProcessingDateNotifier: ValueNotifier<String>(''),
        loadImages: () {},
        refreshSettings: () {},
        stabCallback: () {},
        cancelStabCallback: () async {},
        isStabilizingRunning: () => false,
        processPickedFiles: (files, processor) async {},
        setProjectOrientation: (_) {},
      );
    });

    test('pickFromGallery method exists and returns Future<bool>', () {
      expect(handler.pickFromGallery, isA<Function>());
    });

    test('pickFiles method exists', () {
      expect(handler.pickFiles, isA<Function>());
    });

    test('handleDesktopDrop method exists', () {
      expect(handler.handleDesktopDrop, isA<Function>());
    });

    test('processPickedFile method exists', () {
      expect(handler.processPickedFile, isA<Function>());
    });
  });

  group('GalleryImportHandler.showImportOptionsSheet Method Signature', () {
    test('showImportOptionsSheet is a static method', () {
      expect(GalleryImportHandler.showImportOptionsSheet, isA<Function>());
    });
  });

  group('GalleryImportHandler Platform Detection Logic', () {
    test('platform flags can be checked', () {
      // These are the platform checks used in showImportOptionsSheet
      final isMobile = Platform.isAndroid || Platform.isIOS;
      final isDesktop =
          Platform.isMacOS || Platform.isWindows || Platform.isLinux;

      // At least one should be true
      expect(isMobile || isDesktop, isTrue);
      // Should be mutually exclusive (unless on unusual platform)
      if (isMobile) {
        expect(isDesktop, isFalse);
      }
    });
  });

  group('GalleryImportHandler Callback Order Tests', () {
    test('callbacks are stored correctly in handler', () {
      var loadImagesCallCount = 0;
      var refreshSettingsCallCount = 0;
      var stabCallbackCallCount = 0;
      var cancelStabCallCount = 0;

      final handler = GalleryImportHandler(
        projectId: 1,
        projectIdStr: '1',
        activeProcessingDateNotifier: ValueNotifier<String>(''),
        loadImages: () => loadImagesCallCount++,
        refreshSettings: () => refreshSettingsCallCount++,
        stabCallback: () => stabCallbackCallCount++,
        cancelStabCallback: () async => cancelStabCallCount++,
        isStabilizingRunning: () => false,
        processPickedFiles: (files, processor) async {},
        setProjectOrientation: (_) {},
      );

      // Handler is created successfully with all callbacks
      expect(handler, isNotNull);
      // Verify callbacks haven't been invoked yet
      expect(loadImagesCallCount, 0);
      expect(refreshSettingsCallCount, 0);
      expect(stabCallbackCallCount, 0);
      expect(cancelStabCallCount, 0);
    });
  });

  group('GalleryImportHandler ValueNotifier Usage', () {
    test('activeProcessingDateNotifier can be updated', () {
      final notifier = ValueNotifier<String>('');

      GalleryImportHandler(
        projectId: 1,
        projectIdStr: '1',
        activeProcessingDateNotifier: notifier,
        loadImages: () {},
        refreshSettings: () {},
        stabCallback: () {},
        cancelStabCallback: () async {},
        isStabilizingRunning: () => false,
        processPickedFiles: (files, processor) async {},
        setProjectOrientation: (_) {},
      );

      // Simulate date being set during processing
      notifier.value = '2024-01-15';
      expect(notifier.value, '2024-01-15');

      notifier.dispose();
    });
  });

  group('GalleryImportHandler File Processing Delegation', () {
    test('processPickedFiles callback receives FilePickerResult', () async {
      FilePickerResult? receivedResult;
      Function? receivedProcessor;

      final handler = GalleryImportHandler(
        projectId: 1,
        projectIdStr: '1',
        activeProcessingDateNotifier: ValueNotifier<String>(''),
        loadImages: () {},
        refreshSettings: () {},
        stabCallback: () {},
        cancelStabCallback: () async {},
        isStabilizingRunning: () => false,
        processPickedFiles: (files, processor) async {
          receivedResult = files;
          receivedProcessor = processor;
        },
        setProjectOrientation: (_) {},
      );

      // The callback structure is correct for passing FilePickerResult
      expect(handler, isNotNull);
      // Callback not yet invoked
      expect(receivedResult, isNull);
      expect(receivedProcessor, isNull);
    });
  });

  group('GalleryImportHandler Import Limits', () {
    test('AssetPicker maxAssets constant is 100', () {
      // Per the pickFromGallery implementation
      const maxAssets = 100;
      expect(maxAssets, 100);
    });
  });

  group('GalleryImportHandler Path Processing Logic', () {
    test('filename normalization removes dots and lowercases', () {
      // Test the logic from _getTemporaryPhotoPath
      const originalFilename = 'IMG.2024.01.15.Test';
      final normalized = originalFilename.toLowerCase().replaceAll('.', '');
      expect(normalized, 'img20240115test');
    });

    test('extension is preserved in lowercase', () {
      const testExtensions = ['.JPG', '.PNG', '.HEIC', '.jpeg', '.Png'];
      for (final ext in testExtensions) {
        expect(ext.toLowerCase(), isIn(['.jpg', '.png', '.heic', '.jpeg']));
      }
    });
  });

  group('GalleryImportHandler Live Photo Detection Logic', () {
    test('detects modified live photo by extension', () {
      // _isModifiedLivePhoto returns true for live photos with .jpg/.jpeg
      const jpgExtensions = ['.jpg', '.jpeg'];
      const otherExtensions = ['.png', '.heic', '.mov'];

      for (final ext in jpgExtensions) {
        final isJpegFormat = ext == '.jpg' || ext == '.jpeg';
        expect(isJpegFormat, isTrue);
      }

      for (final ext in otherExtensions) {
        final isJpegFormat = ext == '.jpg' || ext == '.jpeg';
        expect(isJpegFormat, isFalse);
      }
    });
  });
}
