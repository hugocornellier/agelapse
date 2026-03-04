import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/utils/dir_utils.dart';

/// Unit tests for DirUtils.
/// Tests directory naming constants and path logic.
void main() {
  group('DirUtils Constants', () {
    test('photosRawDirname is correct', () {
      expect(DirUtils.photosRawDirname, 'photos_raw');
    });

    test('stabilizedDirname is correct', () {
      expect(DirUtils.stabilizedDirname, 'stabilized');
    });

    test('stabilizedWIPDirname is correct', () {
      expect(DirUtils.stabilizedWIPDirname, 'stabilized_wip');
    });

    test('watermarkDirname is correct', () {
      expect(DirUtils.watermarkDirname, 'watermark');
    });

    test('thumbnailDirname is correct', () {
      expect(DirUtils.thumbnailDirname, 'thumbnails');
    });

    test('failureDirname is correct', () {
      expect(DirUtils.failureDirname, 'failure');
    });

    test('testDirname is correct', () {
      expect(DirUtils.testDirname, 'test');
    });

    test('all directory names are non-empty', () {
      expect(DirUtils.photosRawDirname.isNotEmpty, isTrue);
      expect(DirUtils.stabilizedDirname.isNotEmpty, isTrue);
      expect(DirUtils.stabilizedWIPDirname.isNotEmpty, isTrue);
      expect(DirUtils.watermarkDirname.isNotEmpty, isTrue);
      expect(DirUtils.thumbnailDirname.isNotEmpty, isTrue);
      expect(DirUtils.failureDirname.isNotEmpty, isTrue);
      expect(DirUtils.testDirname.isNotEmpty, isTrue);
    });

    test('directory names do not contain path separators', () {
      expect(DirUtils.photosRawDirname.contains('/'), isFalse);
      expect(DirUtils.stabilizedDirname.contains('/'), isFalse);
      expect(DirUtils.stabilizedWIPDirname.contains('/'), isFalse);
      expect(DirUtils.watermarkDirname.contains('/'), isFalse);
      expect(DirUtils.thumbnailDirname.contains('/'), isFalse);
      expect(DirUtils.failureDirname.contains('/'), isFalse);
      expect(DirUtils.testDirname.contains('/'), isFalse);
    });

    test('directory names are lowercase', () {
      expect(
        DirUtils.photosRawDirname,
        DirUtils.photosRawDirname.toLowerCase(),
      );
      expect(
        DirUtils.stabilizedDirname,
        DirUtils.stabilizedDirname.toLowerCase(),
      );
      expect(
        DirUtils.stabilizedWIPDirname,
        DirUtils.stabilizedWIPDirname.toLowerCase(),
      );
      expect(
        DirUtils.watermarkDirname,
        DirUtils.watermarkDirname.toLowerCase(),
      );
      expect(
        DirUtils.thumbnailDirname,
        DirUtils.thumbnailDirname.toLowerCase(),
      );
      expect(DirUtils.failureDirname, DirUtils.failureDirname.toLowerCase());
      expect(DirUtils.testDirname, DirUtils.testDirname.toLowerCase());
    });
  });

  group('getVideoExtension', () {
    test('returns .mp4 for non-transparent without codec', () {
      expect(DirUtils.getVideoExtension(isTransparent: false), '.mp4');
    });

    test('returns codec container extension when codec is provided', () {
      expect(DirUtils.getVideoExtension(codec: VideoCodec.h264), '.mp4');
      expect(DirUtils.getVideoExtension(codec: VideoCodec.hevc), '.mp4');
      expect(DirUtils.getVideoExtension(codec: VideoCodec.prores422), '.mov');
      expect(DirUtils.getVideoExtension(codec: VideoCodec.prores422hq), '.mov');
      expect(DirUtils.getVideoExtension(codec: VideoCodec.prores4444), '.mov');
      expect(DirUtils.getVideoExtension(codec: VideoCodec.vp9), '.webm');
    });

    test('codec parameter overrides isTransparent flag', () {
      // Even though isTransparent is true, codec takes precedence
      expect(
        DirUtils.getVideoExtension(isTransparent: true, codec: VideoCodec.h264),
        '.mp4',
      );
    });

    test('all extensions start with a dot', () {
      for (final codec in VideoCodec.values) {
        final ext = DirUtils.getVideoExtension(codec: codec);
        expect(ext, startsWith('.'));
      }
    });
  });

  group('DirUtils Method Signatures', () {
    // Note: These methods require Flutter bindings for path_provider
    // They are tested in integration tests instead.
    // Here we only verify the class structure is accessible.

    test('DirUtils class is accessible', () {
      expect(DirUtils, isNotNull);
    });

    test('all directory getters are static methods', () {
      // Verify static method access compiles (these won't be awaited)
      expect(DirUtils.getProjectDirPath, isNotNull);
      expect(DirUtils.getStabilizedDirPath, isNotNull);
      expect(DirUtils.getRawPhotoDirPath, isNotNull);
      expect(DirUtils.getFailureDirPath, isNotNull);
      expect(DirUtils.getWatermarkDirPath, isNotNull);
      expect(DirUtils.getThumbnailDirPath, isNotNull);
      expect(DirUtils.getTestDirPath, isNotNull);
      expect(DirUtils.getExportsDirPath, isNotNull);
    });
  });
}
