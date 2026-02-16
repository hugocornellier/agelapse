import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/gallery_page/gallery_widgets.dart';
import 'package:agelapse/services/thumbnail_service.dart';

/// Unit tests for gallery_widgets.dart.
/// Tests ThumbnailCheckResult, ThumbnailStatusHelper, and widget classes.
void main() {
  group('ThumbnailCheckResult', () {
    test('can be instantiated with success status', () {
      const result = ThumbnailCheckResult(
        status: ThumbnailStatus.success,
        thumbnailExists: true,
      );
      expect(result, isNotNull);
      expect(result.status, ThumbnailStatus.success);
      expect(result.thumbnailExists, isTrue);
    });

    test('can be instantiated with noFacesFound status and no thumbnail', () {
      const result = ThumbnailCheckResult(
        status: ThumbnailStatus.noFacesFound,
        thumbnailExists: false,
      );
      expect(result.status, ThumbnailStatus.noFacesFound);
      expect(result.thumbnailExists, isFalse);
    });

    test('can be instantiated with noFacesFound status', () {
      const result = ThumbnailCheckResult(
        status: ThumbnailStatus.noFacesFound,
        thumbnailExists: false,
      );
      expect(result.status, ThumbnailStatus.noFacesFound);
      expect(result.thumbnailExists, isFalse);
    });

    test('can be instantiated with stabFailed status', () {
      const result = ThumbnailCheckResult(
        status: ThumbnailStatus.stabFailed,
        thumbnailExists: false,
      );
      expect(result.status, ThumbnailStatus.stabFailed);
    });
  });

  group('ThumbnailStatusHelper', () {
    test('class can be referenced', () {
      expect(ThumbnailStatusHelper, isNotNull);
    });

    test('checkInitialStatus is a static method', () {
      expect(ThumbnailStatusHelper.checkInitialStatus, isA<Function>());
    });

    test('subscribeToStream is a static method', () {
      expect(ThumbnailStatusHelper.subscribeToStream, isA<Function>());
    });
  });

  group('FlashingBox', () {
    test('can be instantiated', () {
      const widget = FlashingBox();
      expect(widget, isA<FlashingBox>());
    });

    test('creates state', () {
      const widget = FlashingBox();
      expect(widget.createState(), isA<FlashingBoxState>());
    });
  });

  group('StabilizedThumbnail', () {
    test('can be instantiated with required parameters', () {
      const widget = StabilizedThumbnail(
        thumbnailPath: '/path/to/thumb.jpg',
        projectId: 1,
      );
      expect(widget, isA<StabilizedThumbnail>());
      expect(widget.thumbnailPath, '/path/to/thumb.jpg');
      expect(widget.projectId, 1);
    });

    test('creates state', () {
      const widget = StabilizedThumbnail(
        thumbnailPath: '/path/to/thumb.jpg',
        projectId: 1,
      );
      expect(widget.createState(), isA<StabilizedThumbnailState>());
    });
  });

  group('RawThumbnail', () {
    test('can be instantiated with required parameters', () {
      const widget = RawThumbnail(
        thumbnailPath: '/path/to/raw.jpg',
        projectId: 2,
      );
      expect(widget, isA<RawThumbnail>());
      expect(widget.thumbnailPath, '/path/to/raw.jpg');
      expect(widget.projectId, 2);
    });

    test('creates state', () {
      const widget = RawThumbnail(
        thumbnailPath: '/path/to/raw.jpg',
        projectId: 2,
      );
      expect(widget.createState(), isA<RawThumbnailState>());
    });
  });
}
