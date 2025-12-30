import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/camera_utils.dart';

/// Unit tests for CameraUtils.
/// Tests method signatures and pure utility functions.
void main() {
  group('CameraUtils Class', () {
    test('CameraUtils class is accessible', () {
      expect(CameraUtils, isNotNull);
    });
  });

  group('CameraUtils Method Signatures', () {
    test('loadSaveToCameraRollSetting returns Future<bool>', () {
      final result = CameraUtils.loadSaveToCameraRollSetting();
      expect(result, isA<Future<bool>>());
    });

    test('readBytesInIsolate method exists', () {
      expect(CameraUtils.readBytesInIsolate, isA<Function>());
    });

    test('saveImageToFileSystemInIsolate method exists', () {
      expect(CameraUtils.saveImageToFileSystemInIsolate, isA<Function>());
    });

    test('saveImageToFileSystem method exists', () {
      expect(CameraUtils.saveImageToFileSystem, isA<Function>());
    });

    test('saveToGallery method exists', () {
      expect(CameraUtils.saveToGallery, isA<Function>());
    });

    test('saveImageToGallery method exists', () {
      expect(CameraUtils.saveImageToGallery, isA<Function>());
    });

    test('flashAndVibrate method exists', () {
      expect(CameraUtils.flashAndVibrate, isA<Function>());
    });

    test('savePhoto method exists', () {
      expect(CameraUtils.savePhoto, isA<Function>());
    });
  });

  group('CameraUtils Static Nature', () {
    test('all methods are static', () {
      // These should compile without needing an instance
      // ignore: unnecessary_type_check
      expect(CameraUtils.loadSaveToCameraRollSetting is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.readBytesInIsolate is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.saveImageToFileSystemInIsolate is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.saveImageToFileSystem is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.saveToGallery is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.saveImageToGallery is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.flashAndVibrate is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.savePhoto is Function, isTrue);
    });
  });
}
