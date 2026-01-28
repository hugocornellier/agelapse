import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/custom_font_manager.dart';

void main() {
  group('FontValidationResult', () {
    group('constructor', () {
      test('creates instance with all properties', () {
        const result = FontValidationResult(
          isValid: true,
          errorMessage: 'error',
          suggestedName: 'suggested',
        );

        expect(result.isValid, isTrue);
        expect(result.errorMessage, equals('error'));
        expect(result.suggestedName, equals('suggested'));
      });

      test('creates instance with only required property', () {
        const result = FontValidationResult(isValid: false);

        expect(result.isValid, isFalse);
        expect(result.errorMessage, isNull);
        expect(result.suggestedName, isNull);
      });
    });

    group('factory valid', () {
      test('creates valid result with suggested name', () {
        final result = FontValidationResult.valid('MyFont');

        expect(result.isValid, isTrue);
        expect(result.suggestedName, equals('MyFont'));
        expect(result.errorMessage, isNull);
      });

      test('creates valid result with empty suggested name', () {
        final result = FontValidationResult.valid('');

        expect(result.isValid, isTrue);
        expect(result.suggestedName, equals(''));
      });
    });

    group('factory invalid', () {
      test('creates invalid result with error message', () {
        final result = FontValidationResult.invalid('File not found');

        expect(result.isValid, isFalse);
        expect(result.errorMessage, equals('File not found'));
        expect(result.suggestedName, isNull);
      });

      test('creates invalid result with detailed error', () {
        final result = FontValidationResult.invalid(
            'File too large (15 MB). Maximum is 10 MB.');

        expect(result.isValid, isFalse);
        expect(result.errorMessage, contains('15 MB'));
        expect(result.errorMessage, contains('Maximum'));
      });
    });
  });

  group('CustomFontManager constants', () {
    test('supportedExtensions contains ttf and otf', () {
      expect(CustomFontManager.supportedExtensions, contains('.ttf'));
      expect(CustomFontManager.supportedExtensions, contains('.otf'));
      expect(CustomFontManager.supportedExtensions.length, equals(2));
    });

    test('maxFileSizeBytes is 10 MB', () {
      expect(CustomFontManager.maxFileSizeBytes, equals(10 * 1024 * 1024));
    });

    test('customFontPrefix is correct', () {
      expect(CustomFontManager.customFontPrefix, equals('CustomFont_'));
    });

    test('customFontMarker is correct', () {
      expect(CustomFontManager.customFontMarker, equals('_custom_font'));
    });

    test('fontsDirName is correct', () {
      expect(CustomFontManager.fontsDirName, equals('custom_fonts'));
    });
  });

  group('CustomFontManager singleton', () {
    test('returns same instance', () {
      final instance1 = CustomFontManager.instance;
      final instance2 = CustomFontManager.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });

  group('CustomFontManager.isCustomFont', () {
    test('returns true for strings starting with prefix', () {
      expect(
        CustomFontManager.instance.isCustomFont('CustomFont_123456789'),
        isTrue,
      );
      expect(
        CustomFontManager.instance.isCustomFont('CustomFont_MyFont'),
        isTrue,
      );
    });

    test('returns false for bundled fonts', () {
      expect(CustomFontManager.instance.isCustomFont('Inter'), isFalse);
      expect(CustomFontManager.instance.isCustomFont('Roboto'), isFalse);
      expect(CustomFontManager.instance.isCustomFont('SourceSans3'), isFalse);
    });

    test('returns false for partial prefix', () {
      expect(CustomFontManager.instance.isCustomFont('Custom'), isFalse);
      expect(CustomFontManager.instance.isCustomFont('CustomFont'), isFalse);
    });

    test('returns false for empty string', () {
      expect(CustomFontManager.instance.isCustomFont(''), isFalse);
    });

    test('is case sensitive', () {
      expect(
        CustomFontManager.instance.isCustomFont('customfont_123456789'),
        isFalse,
      );
      expect(
        CustomFontManager.instance.isCustomFont('CUSTOMFONT_123456789'),
        isFalse,
      );
    });
  });

  group('CustomFontManager.getFallbackFont', () {
    test('returns Inter', () {
      expect(CustomFontManager.instance.getFallbackFont(), equals('Inter'));
    });
  });
}
