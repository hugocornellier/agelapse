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
      );
      expect(config.fontFamily, 'Roboto');
    });

    test('stores captureOffsetMap correctly', () {
      final map = <String, int?>{'123': 60, '456': null};
      final config = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
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
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map, // Same reference
        fontFamily: 'Inter',
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
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: false,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
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
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: <String, int?>{}, // Different reference
        fontFamily: 'Inter',
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
      );
      final copy = original.copyWith(dateFormat: 'yyyy');
      expect(copy.stabilizedLabelsEnabled, isTrue);
      expect(copy.rawLabelsEnabled, isTrue);
      expect(copy.dateFormat, 'yyyy');
      expect(copy.fontFamily, 'Roboto');
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
      );
      final config2 = GalleryDateStampConfig(
        stabilizedLabelsEnabled: true,
        rawLabelsEnabled: false,
        dateFormat: 'MM/yy',
        captureOffsetMap: map,
        fontFamily: 'Inter',
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
