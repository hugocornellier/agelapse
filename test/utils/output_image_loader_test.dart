import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/output_image_loader.dart';

/// Unit tests for OutputImageLoader.
/// Tests constructor, properties, and method signatures.
void main() {
  group('OutputImageLoader Construction', () {
    test('OutputImageLoader can be instantiated with projectId', () {
      final loader = OutputImageLoader(1);
      expect(loader, isNotNull);
      expect(loader, isA<OutputImageLoader>());
    });

    test('OutputImageLoader stores projectId correctly', () {
      final loader = OutputImageLoader(42);
      expect(loader.projectId, 42);
    });

    test('OutputImageLoader handles different projectIds', () {
      final loader1 = OutputImageLoader(1);
      final loader2 = OutputImageLoader(999);
      final loader3 = OutputImageLoader(0);

      expect(loader1.projectId, 1);
      expect(loader2.projectId, 999);
      expect(loader3.projectId, 0);
    });
  });

  group('OutputImageLoader Initial State', () {
    test('projectOrientation is null initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.projectOrientation, isNull);
    });

    test('aspectRatio is null initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.aspectRatio, isNull);
    });

    test('offsetX is 0.0 initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.offsetX, 0.0);
    });

    test('offsetY is 0.0 initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.offsetY, 0.0);
    });

    test('ghostImageOffsetX is null initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.ghostImageOffsetX, isNull);
    });

    test('ghostImageOffsetY is null initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.ghostImageOffsetY, isNull);
    });

    test('guideImage is null initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.guideImage, isNull);
    });

    test('hasRealGuideImage is false initially', () {
      final loader = OutputImageLoader(1);
      expect(loader.hasRealGuideImage, isFalse);
    });
  });

  group('OutputImageLoader Dispose', () {
    test('dispose method exists', () {
      final loader = OutputImageLoader(1);
      expect(loader.dispose, isA<Function>());
    });

    test('dispose does not throw when guideImage is null', () {
      final loader = OutputImageLoader(1);
      expect(() => loader.dispose(), returnsNormally);
    });

    test('dispose sets guideImage to null', () {
      final loader = OutputImageLoader(1);
      loader.dispose();
      expect(loader.guideImage, isNull);
    });
  });

  group('OutputImageLoader Method Signatures', () {
    test('initialize method exists', () {
      final loader = OutputImageLoader(1);
      expect(loader.initialize, isA<Function>());
    });

    test('resetToPlaceholder method exists', () {
      final loader = OutputImageLoader(1);
      expect(loader.resetToPlaceholder, isA<Function>());
    });

    test('tryLoadRealGuideImage method exists', () {
      final loader = OutputImageLoader(1);
      expect(loader.tryLoadRealGuideImage, isA<Function>());
    });
  });

  group('OutputImageLoader Property Mutability', () {
    test('projectOrientation can be modified', () {
      final loader = OutputImageLoader(1);
      loader.projectOrientation = 'portrait';
      expect(loader.projectOrientation, 'portrait');
    });

    test('aspectRatio can be modified', () {
      final loader = OutputImageLoader(1);
      loader.aspectRatio = '9:16';
      expect(loader.aspectRatio, '9:16');
    });

    test('offsetX can be modified', () {
      final loader = OutputImageLoader(1);
      loader.offsetX = 0.5;
      expect(loader.offsetX, 0.5);
    });

    test('offsetY can be modified', () {
      final loader = OutputImageLoader(1);
      loader.offsetY = 0.3;
      expect(loader.offsetY, 0.3);
    });

    test('ghostImageOffsetX can be modified', () {
      final loader = OutputImageLoader(1);
      loader.ghostImageOffsetX = 0.105;
      expect(loader.ghostImageOffsetX, 0.105);
    });

    test('ghostImageOffsetY can be modified', () {
      final loader = OutputImageLoader(1);
      loader.ghostImageOffsetY = 0.241;
      expect(loader.ghostImageOffsetY, 0.241);
    });

    test('hasRealGuideImage can be modified', () {
      final loader = OutputImageLoader(1);
      loader.hasRealGuideImage = true;
      expect(loader.hasRealGuideImage, isTrue);
    });
  });

  group('OutputImageLoader Edge Cases', () {
    test('handles negative projectId', () {
      final loader = OutputImageLoader(-1);
      expect(loader.projectId, -1);
    });

    test('handles large projectId', () {
      final loader = OutputImageLoader(999999999);
      expect(loader.projectId, 999999999);
    });

    test('handles negative offsets', () {
      final loader = OutputImageLoader(1);
      loader.offsetX = -0.5;
      loader.offsetY = -0.3;
      expect(loader.offsetX, -0.5);
      expect(loader.offsetY, -0.3);
    });

    test('handles offsets greater than 1', () {
      final loader = OutputImageLoader(1);
      loader.offsetX = 1.5;
      loader.offsetY = 2.0;
      expect(loader.offsetX, 1.5);
      expect(loader.offsetY, 2.0);
    });
  });

  group('OutputImageLoader Multiple Instances', () {
    test('multiple loaders are independent', () {
      final loader1 = OutputImageLoader(1);
      final loader2 = OutputImageLoader(2);

      loader1.offsetX = 0.5;
      loader2.offsetX = 0.8;

      expect(loader1.offsetX, 0.5);
      expect(loader2.offsetX, 0.8);
    });

    test('disposing one loader does not affect others', () {
      final loader1 = OutputImageLoader(1);
      final loader2 = OutputImageLoader(2);

      loader1.hasRealGuideImage = true;
      loader2.hasRealGuideImage = true;

      loader1.dispose();

      expect(loader1.guideImage, isNull);
      expect(loader2.hasRealGuideImage, isTrue);
    });
  });
}
