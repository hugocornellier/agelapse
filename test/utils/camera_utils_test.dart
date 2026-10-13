import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/camera_utils.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

/// Unit tests for CameraUtils.
/// Tests method signatures and pure utility functions.
void main() {
  group('CameraUtils Class', () {
    test('CameraUtils class is accessible', () {
      expect(CameraUtils, isNotNull);
    });
  });

  group('CameraUtils Method Signatures', () {
    test('loadSaveToCameraRoll returns Future<bool>', () {
      final result = SettingsUtil.loadSaveToCameraRoll();
      expect(result, isA<Future<bool>>());
    });

    test('readBytesInIsolate method exists', () {
      expect(CameraUtils.readBytesInIsolate, isA<Function>());
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

    test('savePhoto method exists', () {
      expect(CameraUtils.savePhoto, isA<Function>());
    });
  });

  group('saveImageToFileSystem', () {
    // Issue #41: the raw file used to keep the picked file's extension case
    // (IMG_0001.HEIC became <timestamp>.HEIC) while the database recorded
    // .heic, which only a case-sensitive file system tells apart.
    test('saves the raw file with a lower-case extension', () async {
      const projectId = 987654321;
      test_config.isTestMode = true;
      final picked = await Directory.systemTemp.createTemp('camera_utils_');
      final projectDir = Directory(await DirUtils.getProjectDirPath(projectId));
      try {
        final source = File(p.join(picked.path, 'IMG_0001.HEIC'))
          ..writeAsBytesSync(const [1, 2, 3]);

        final saved = await CameraUtils.saveImageToFileSystem(
          XFile(source.path),
          '1700000000000',
          projectId,
        );

        expect(p.basename(saved), '1700000000000.heic');
        expect(p.dirname(saved), p.join(projectDir.path, 'photos_raw'));
        expect(File(saved).readAsBytesSync(), [1, 2, 3]);
      } finally {
        test_config.isTestMode = false;
        await picked.delete(recursive: true);
        if (await projectDir.exists()) {
          await projectDir.delete(recursive: true);
        }
      }
    });
  });

  group('CameraUtils Static Nature', () {
    test('all methods are static', () {
      // These should compile without needing an instance
      // ignore: unnecessary_type_check
      expect(SettingsUtil.loadSaveToCameraRoll is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.readBytesInIsolate is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.saveImageToFileSystem is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.saveToGallery is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.saveImageToGallery is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(CameraUtils.savePhoto is Function, isTrue);
    });
  });
}
