import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/gallery_date_stamp_provider.dart';

/// Unit tests for GalleryDateStampConfig and GalleryDateStampProvider.
void main() {
  group('GalleryDateStampConfig', () {
    test('can be instantiated with required parameters', () {
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: const {},
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config, isNotNull);
      expect(config, isA<GalleryDateStampConfig>());
    });

    test('stores stabilizedLabelsEnabled correctly', () {
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: const {},
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config.stabilizedLabelsEnabled, isTrue);
    });

    test('stores rawLabelsEnabled correctly', () {
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: true,
        dateFormat: 'MM/yy',
        captureOffsetMap: const {},
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config.rawLabelsEnabled, isTrue);
    });

    test('stores dateFormat correctly', () {
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MMM dd',
        captureOffsetMap: const {},
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config.dateFormat, 'MMM dd');
    });

    test('stores fontFamily correctly', () {
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: const {},
        fontFamily: 'Roboto',
        sizeLevel: 4,
      );
      expect(config.fontFamily, 'Roboto');
    });

    test('stores sizeLevel correctly', () {
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: const {},
        fontFamily: 'Inter',
        sizeLevel: 2,
      );
      expect(config.sizeLevel, 2);
    });

    test('stores captureOffsetMap correctly', () {
      final map = <String, int?>{'123': 60, '456': null};
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config.captureOffsetMap, same(map));
    });
  });

  group('GalleryDateStampConfig.disabled', () {
    test('has stabilizedLabelsEnabled false', () {
      expect(
        GalleryDateStampConfig.disabled.stabilizedLabelsEnabled,
        isFalse,
      );
    });

    test('has rawLabelsEnabled false', () {
      expect(GalleryDateStampConfig.disabled.rawLabelsEnabled, isFalse);
    });

    test('has default dateFormat', () {
      expect(GalleryDateStampConfig.disabled.dateFormat, 'MM/yy');
    });

    test('has empty captureOffsetMap', () {
      expect(GalleryDateStampConfig.disabled.captureOffsetMap, isEmpty);
    });

    test('has default sizeLevel', () {
      expect(GalleryDateStampConfig.disabled.sizeLevel, 4);
    });
  });

  group('GalleryDateStampConfig equality', () {
    test('same config is equal', () {
      final map = <String, int?>{};
      final config1 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map, // Same reference
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config1, equals(config2));
    });

    test('different stabilizedLabelsEnabled is not equal', () {
      final map = <String, int?>{};
      final config1 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config1, isNot(equals(config2)));
    });

    test('different sizeLevel is not equal', () {
      final map = <String, int?>{};
      final config1 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 2,
      );
      expect(config1, isNot(equals(config2)));
    });

    test('different captureOffsetMap reference is not equal', () {
      final config1 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: <String, int?>{},
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: <String, int?>{}, // Different reference
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config1, isNot(equals(config2)));
    });
  });

  group('GalleryDateStampConfig.copyWith', () {
    test('returns new instance with updated field', () {
      final original = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: const {},
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      final copy = original.copyWith(stabilizedLabelsEnabled: true);
      expect(copy.stabilizedLabelsEnabled, isTrue);
      expect(copy.rawLabelsEnabled, isFalse);
      expect(copy.dateFormat, 'MM/yy');
    });

    test('preserves unchanged fields', () {
      final original = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: true,
        dateFormat: 'MMM dd',
        captureOffsetMap: const {},
        fontFamily: 'Roboto',
        sizeLevel: 4,
      );
      final copy = original.copyWith(dateFormat: 'yyyy');
      expect(copy.stabilizedLabelsEnabled, isTrue);
      expect(copy.rawLabelsEnabled, isTrue);
      expect(copy.dateFormat, 'yyyy');
      expect(copy.fontFamily, 'Roboto');
    });

    test('copyWith updates sizeLevel', () {
      final original = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: const {},
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      final copy = original.copyWith(sizeLevel: 6);
      expect(copy.sizeLevel, 6);
      expect(copy.fontFamily, 'Inter');
    });
  });

  group('GalleryDateStampConfig hashCode', () {
    test('same configs have same hashCode', () {
      final map = <String, int?>{};
      final config1 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
        sizeLevel: 4,
      );
      expect(config1.hashCode, equals(config2.hashCode));
    });
  });

  group('GalleryDateStampProvider', () {
    test('class can be referenced', () {
      expect(GalleryDateStampProvider, isNotNull);
    });
  });
}
