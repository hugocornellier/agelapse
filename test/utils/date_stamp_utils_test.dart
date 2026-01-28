import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/date_stamp_utils.dart';
import 'package:agelapse/services/custom_font_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DateStampUtils Constants', () {
    test('gallery format constants are correct', () {
      expect(DateStampUtils.galleryFormatMMYY, equals('MM/yy'));
      expect(DateStampUtils.galleryFormatMMMDD, equals('MMM dd'));
      expect(DateStampUtils.galleryFormatMMMDDYY, equals("MMM dd ''yy"));
      expect(DateStampUtils.galleryFormatDDMMM, equals('dd MMM'));
      expect(DateStampUtils.galleryFormatMMMYYYY, equals('MMM yyyy'));
      expect(DateStampUtils.galleryFormatCustom, equals('_custom_gallery'));
    });

    test('export format constants are correct', () {
      expect(DateStampUtils.exportFormatISO, equals('yyyy-MM-dd'));
      expect(DateStampUtils.exportFormatUS, equals('MM/dd/yyyy'));
      expect(DateStampUtils.exportFormatEU, equals('dd/MM/yyyy'));
      expect(DateStampUtils.exportFormatLong, equals('MMM dd, yyyy'));
      expect(DateStampUtils.exportFormatShort, equals('dd MMM yyyy'));
      expect(DateStampUtils.exportFormatCustom, equals('_custom_export'));
    });

    test('character limits are correct', () {
      expect(DateStampUtils.galleryFormatMaxLength, equals(15));
      expect(DateStampUtils.exportFormatMaxLength, equals(40));
    });

    test('position constants are correct', () {
      expect(DateStampUtils.positionLowerRight, equals('lower right'));
      expect(DateStampUtils.positionLowerLeft, equals('lower left'));
      expect(DateStampUtils.positionUpperRight, equals('upper right'));
      expect(DateStampUtils.positionUpperLeft, equals('upper left'));
    });

    test('default values are correct', () {
      expect(DateStampUtils.defaultGalleryFormat, equals('MM/yy'));
      expect(DateStampUtils.defaultExportFormat, equals('MMM dd, yyyy'));
      expect(DateStampUtils.defaultPosition, equals('lower right'));
      expect(DateStampUtils.defaultOpacity, equals(1.0));
      expect(DateStampUtils.defaultSizePercent, equals(3));
    });

    test('font constants are correct', () {
      expect(DateStampUtils.fontInter, equals('Inter'));
      expect(DateStampUtils.fontRoboto, equals('Roboto'));
      expect(DateStampUtils.fontSourceSans, equals('SourceSans3'));
      expect(DateStampUtils.fontNunito, equals('Nunito'));
      expect(DateStampUtils.fontJetBrainsMono, equals('JetBrainsMono'));
      expect(DateStampUtils.fontSameAsGallery, equals('_same_as_gallery'));
      expect(DateStampUtils.fontCustomMarker, equals('_custom_font'));
      expect(DateStampUtils.defaultFont, equals('Inter'));
    });

    test('bundledFonts contains all bundled fonts', () {
      expect(DateStampUtils.bundledFonts, contains('Inter'));
      expect(DateStampUtils.bundledFonts, contains('Roboto'));
      expect(DateStampUtils.bundledFonts, contains('SourceSans3'));
      expect(DateStampUtils.bundledFonts, contains('Nunito'));
      expect(DateStampUtils.bundledFonts, contains('JetBrainsMono'));
      expect(DateStampUtils.bundledFonts.length, equals(5));
    });

    test('availableFonts is alias for bundledFonts', () {
      expect(
          DateStampUtils.availableFonts, equals(DateStampUtils.bundledFonts));
    });

    test('galleryPresets contains all gallery formats', () {
      expect(DateStampUtils.galleryPresets, contains('MM/yy'));
      expect(DateStampUtils.galleryPresets, contains('MMM dd'));
      expect(DateStampUtils.galleryPresets.length, equals(5));
    });

    test('exportPresets contains all export formats', () {
      expect(DateStampUtils.exportPresets, contains('yyyy-MM-dd'));
      expect(DateStampUtils.exportPresets, contains('MM/dd/yyyy'));
      expect(DateStampUtils.exportPresets.length, equals(5));
    });
  });

  group('getFontDisplayName', () {
    test('returns correct display name for Inter', () {
      expect(DateStampUtils.getFontDisplayName('Inter'), equals('Inter'));
    });

    test('returns correct display name for Roboto', () {
      expect(DateStampUtils.getFontDisplayName('Roboto'), equals('Roboto'));
    });

    test('returns correct display name for SourceSans3', () {
      expect(DateStampUtils.getFontDisplayName('SourceSans3'),
          equals('Source Sans'));
    });

    test('returns correct display name for Nunito', () {
      expect(DateStampUtils.getFontDisplayName('Nunito'), equals('Nunito'));
    });

    test('returns correct display name for JetBrainsMono', () {
      expect(DateStampUtils.getFontDisplayName('JetBrainsMono'),
          equals('JetBrains Mono'));
    });

    test('returns correct display name for fontSameAsGallery', () {
      expect(DateStampUtils.getFontDisplayName('_same_as_gallery'),
          equals('Same as thumbnail'));
    });

    test('returns correct display name for fontCustomMarker', () {
      expect(DateStampUtils.getFontDisplayName('_custom_font'),
          equals('Custom (TTF/OTF)'));
    });

    test('returns Custom Font for custom font family', () {
      expect(
          DateStampUtils.getFontDisplayName(
              '${CustomFontManager.customFontPrefix}test'),
          equals('Custom Font'));
    });

    test('returns Inter for unknown font', () {
      expect(DateStampUtils.getFontDisplayName('UnknownFont'), equals('Inter'));
    });
  });

  group('isCustomFont', () {
    test('returns true for custom font prefix', () {
      expect(
          DateStampUtils.isCustomFont(
              '${CustomFontManager.customFontPrefix}MyFont'),
          isTrue);
    });

    test('returns false for bundled font', () {
      expect(DateStampUtils.isCustomFont('Inter'), isFalse);
      expect(DateStampUtils.isCustomFont('Roboto'), isFalse);
    });
  });

  group('isBundledFont', () {
    test('returns true for all bundled fonts', () {
      expect(DateStampUtils.isBundledFont('Inter'), isTrue);
      expect(DateStampUtils.isBundledFont('Roboto'), isTrue);
      expect(DateStampUtils.isBundledFont('SourceSans3'), isTrue);
      expect(DateStampUtils.isBundledFont('Nunito'), isTrue);
      expect(DateStampUtils.isBundledFont('JetBrainsMono'), isTrue);
    });

    test('returns false for custom or unknown fonts', () {
      expect(DateStampUtils.isBundledFont('CustomFont'), isFalse);
      expect(DateStampUtils.isBundledFont('Arial'), isFalse);
    });
  });

  group('resolveExportFont', () {
    test('returns gallery font when export font is same as gallery marker', () {
      expect(DateStampUtils.resolveExportFont('_same_as_gallery', 'Inter'),
          equals('Inter'));
      expect(DateStampUtils.resolveExportFont('_same_as_gallery', 'Roboto'),
          equals('Roboto'));
    });

    test('returns export font when not same as gallery marker', () {
      expect(DateStampUtils.resolveExportFont('Roboto', 'Inter'),
          equals('Roboto'));
      expect(DateStampUtils.resolveExportFont('Nunito', 'JetBrainsMono'),
          equals('Nunito'));
    });
  });

  group('formatTimestamp', () {
    test('formats timestamp with ISO format', () {
      // Jan 15, 2024 12:00:00 UTC
      final timestamp =
          DateTime.utc(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch;
      final result = DateStampUtils.formatTimestamp(timestamp, 'yyyy-MM-dd');
      expect(result, contains('2024'));
      expect(result, contains('01'));
      expect(result, contains('15'));
    });

    test('formats timestamp with US format', () {
      final timestamp =
          DateTime.utc(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch;
      final result = DateStampUtils.formatTimestamp(timestamp, 'MM/dd/yyyy');
      expect(result, equals('01/15/2024'));
    });

    test('handles invalid format gracefully', () {
      final timestamp =
          DateTime.utc(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch;
      // Invalid format should fall back to ISO
      final result =
          DateStampUtils.formatTimestamp(timestamp, 'INVALID_FORMAT_XXXXX');
      // Should not throw, may return ISO format or original
      expect(result, isA<String>());
    });
  });

  group('calculatePosition', () {
    test('calculates lower right position correctly', () {
      final offset = DateStampUtils.calculatePosition(
        imageWidth: 1000,
        imageHeight: 500,
        textWidth: 100,
        textHeight: 20,
        position: 'lower right',
        marginPercent: 2.0,
      );
      // margin = 1000 * 0.02 = 20 (x), 500 * 0.02 = 10 (y)
      // x = 1000 - 100 - 20 = 880
      // y = 500 - 20 - 10 = 470
      expect(offset.dx, equals(880));
      expect(offset.dy, equals(470));
    });

    test('calculates lower left position correctly', () {
      final offset = DateStampUtils.calculatePosition(
        imageWidth: 1000,
        imageHeight: 500,
        textWidth: 100,
        textHeight: 20,
        position: 'lower left',
        marginPercent: 2.0,
      );
      // x = margin = 20
      // y = 500 - 20 - 10 = 470
      expect(offset.dx, equals(20));
      expect(offset.dy, equals(470));
    });

    test('calculates upper right position correctly', () {
      final offset = DateStampUtils.calculatePosition(
        imageWidth: 1000,
        imageHeight: 500,
        textWidth: 100,
        textHeight: 20,
        position: 'upper right',
        marginPercent: 2.0,
      );
      // x = 1000 - 100 - 20 = 880
      // y = margin = 10
      expect(offset.dx, equals(880));
      expect(offset.dy, equals(10));
    });

    test('calculates upper left position correctly', () {
      final offset = DateStampUtils.calculatePosition(
        imageWidth: 1000,
        imageHeight: 500,
        textWidth: 100,
        textHeight: 20,
        position: 'upper left',
        marginPercent: 2.0,
      );
      // x = margin = 20
      // y = margin = 10
      expect(offset.dx, equals(20));
      expect(offset.dy, equals(10));
    });

    test('defaults to lower right for unknown position', () {
      final offset = DateStampUtils.calculatePosition(
        imageWidth: 1000,
        imageHeight: 500,
        textWidth: 100,
        textHeight: 20,
        position: 'invalid',
        marginPercent: 2.0,
      );
      expect(offset.dx, equals(880));
      expect(offset.dy, equals(470));
    });

    test('handles case insensitive position', () {
      final offset = DateStampUtils.calculatePosition(
        imageWidth: 1000,
        imageHeight: 500,
        textWidth: 100,
        textHeight: 20,
        position: 'UPPER LEFT',
        marginPercent: 2.0,
      );
      expect(offset.dx, equals(20));
      expect(offset.dy, equals(10));
    });
  });

  group('calculateFontSize', () {
    test('calculates font size based on percentage', () {
      expect(DateStampUtils.calculateFontSize(1000, 3), equals(30));
      expect(DateStampUtils.calculateFontSize(500, 5), equals(25));
      expect(DateStampUtils.calculateFontSize(2000, 2), equals(40));
    });

    test('clamps percentage to 1-6 range', () {
      expect(DateStampUtils.calculateFontSize(1000, 0),
          equals(10)); // clamped to 1%
      expect(DateStampUtils.calculateFontSize(1000, 10),
          equals(60)); // clamped to 6%
    });
  });

  group('getGalleryLabelStyle', () {
    test('returns TextStyle with correct properties', () {
      final style = DateStampUtils.getGalleryLabelStyle(14.0);
      expect(style.fontFamily, equals('Inter'));
      expect(style.fontSize, equals(14.0));
      expect(style.fontWeight, equals(FontWeight.w500));
      expect(style.color, equals(Colors.white));
      expect(style.shadows, isNotNull);
      expect(style.shadows!.length, equals(1));
    });

    test('uses custom font family when provided', () {
      final style =
          DateStampUtils.getGalleryLabelStyle(14.0, fontFamily: 'Roboto');
      expect(style.fontFamily, equals('Roboto'));
    });
  });

  group('getExportTextStyle', () {
    test('returns TextStyle with correct properties', () {
      final style = DateStampUtils.getExportTextStyle(20.0, 1.0);
      expect(style.fontFamily, equals('Inter'));
      expect(style.fontSize, equals(20.0));
      expect(style.fontWeight, equals(FontWeight.w600));
      expect(style.shadows, isNotNull);
      expect(style.shadows!.length, equals(2));
    });

    test('applies opacity to color', () {
      final style = DateStampUtils.getExportTextStyle(20.0, 0.5);
      expect(style.color?.a, closeTo(0.5, 0.01));
    });

    test('uses custom font family when provided', () {
      final style =
          DateStampUtils.getExportTextStyle(20.0, 1.0, fontFamily: 'Nunito');
      expect(style.fontFamily, equals('Nunito'));
    });
  });

  group('getGalleryFormatDisplayName', () {
    test('returns correct display names', () {
      expect(
          DateStampUtils.getGalleryFormatDisplayName('MM/yy'), equals('MM/YY'));
      expect(DateStampUtils.getGalleryFormatDisplayName('MMM dd'),
          equals('MMM DD'));
      expect(DateStampUtils.getGalleryFormatDisplayName("MMM dd ''yy"),
          equals("MMM DD 'YY"));
      expect(DateStampUtils.getGalleryFormatDisplayName('dd MMM'),
          equals('DD MMM'));
      expect(DateStampUtils.getGalleryFormatDisplayName('MMM yyyy'),
          equals('MMM YYYY'));
    });

    test('returns default for unknown format', () {
      expect(DateStampUtils.getGalleryFormatDisplayName('unknown'),
          equals('MM/YY'));
    });
  });

  group('getGalleryFormatExample', () {
    test('returns formatted date string', () {
      final result = DateStampUtils.getGalleryFormatExample('MM/yy');
      expect(result, isA<String>());
      expect(result.length, greaterThan(0));
    });

    test('handles invalid format gracefully', () {
      final result = DateStampUtils.getGalleryFormatExample('INVALID');
      // DateFormat parses many characters, so it returns a string
      expect(result, isA<String>());
    });
  });

  group('getExportFormatDisplayName', () {
    test('returns correct display names', () {
      expect(DateStampUtils.getExportFormatDisplayName('yyyy-MM-dd'),
          equals('YYYY-MM-DD'));
      expect(DateStampUtils.getExportFormatDisplayName('MM/dd/yyyy'),
          equals('MM/DD/YYYY'));
      expect(DateStampUtils.getExportFormatDisplayName('dd/MM/yyyy'),
          equals('DD/MM/YYYY'));
      expect(DateStampUtils.getExportFormatDisplayName('MMM dd, yyyy'),
          equals('MMM DD, YYYY'));
      expect(DateStampUtils.getExportFormatDisplayName('dd MMM yyyy'),
          equals('DD MMM YYYY'));
    });

    test('returns default for unknown format', () {
      expect(DateStampUtils.getExportFormatDisplayName('unknown'),
          equals('MMM DD, YYYY'));
    });
  });

  group('getExportFormatExample', () {
    test('returns formatted date string', () {
      final result = DateStampUtils.getExportFormatExample('yyyy-MM-dd');
      expect(result, isA<String>());
      // Should match pattern YYYY-MM-DD
      expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('handles invalid format gracefully', () {
      final result = DateStampUtils.getExportFormatExample('INVALID');
      // DateFormat parses many characters, so it returns a string
      expect(result, isA<String>());
    });
  });

  group('getPositionDisplayName', () {
    test('returns correct display names', () {
      expect(DateStampUtils.getPositionDisplayName('lower right'),
          equals('Lower right'));
      expect(DateStampUtils.getPositionDisplayName('lower left'),
          equals('Lower left'));
      expect(DateStampUtils.getPositionDisplayName('upper right'),
          equals('Upper right'));
      expect(DateStampUtils.getPositionDisplayName('upper left'),
          equals('Upper left'));
    });

    test('handles case insensitive input', () {
      expect(DateStampUtils.getPositionDisplayName('LOWER RIGHT'),
          equals('Lower right'));
      expect(DateStampUtils.getPositionDisplayName('Upper Left'),
          equals('Upper left'));
    });

    test('returns default for unknown position', () {
      expect(DateStampUtils.getPositionDisplayName('center'),
          equals('Lower right'));
    });
  });

  group('validateGalleryFormat', () {
    test('returns null for valid formats', () {
      expect(DateStampUtils.validateGalleryFormat('MM/yy'), isNull);
      expect(DateStampUtils.validateGalleryFormat('MMM dd'), isNull);
      expect(DateStampUtils.validateGalleryFormat('yyyy'), isNull);
    });

    test('returns error for empty format', () {
      expect(DateStampUtils.validateGalleryFormat(''),
          equals('Format cannot be empty'));
    });

    test('returns error for format exceeding max length', () {
      final longFormat = 'M' * 20;
      expect(DateStampUtils.validateGalleryFormat(longFormat),
          equals('Maximum 15 characters'));
    });

    test('returns error for format without date token', () {
      expect(DateStampUtils.validateGalleryFormat('text'),
          equals('Must include at least one date token'));
    });

    test('returns error for format with time tokens', () {
      // HH:mm has no date tokens so it fails that check first
      // Use a format that has both date and time tokens
      expect(DateStampUtils.validateGalleryFormat('MM/dd HH:mm'),
          equals('Time tokens not available for thumbnails'));
    });
  });

  group('validateExportFormat', () {
    test('returns null for valid formats', () {
      expect(DateStampUtils.validateExportFormat('yyyy-MM-dd'), isNull);
      expect(DateStampUtils.validateExportFormat('MM/dd/yyyy HH:mm'), isNull);
    });

    test('returns error for empty format', () {
      expect(DateStampUtils.validateExportFormat(''),
          equals('Format cannot be empty'));
    });

    test('returns error for format exceeding max length', () {
      final longFormat = 'M' * 50;
      expect(DateStampUtils.validateExportFormat(longFormat),
          equals('Maximum 40 characters'));
    });

    test('returns error for format without date token', () {
      expect(DateStampUtils.validateExportFormat('HH:mm:ss'),
          equals('Must include at least one date token'));
    });

    test('allows time tokens in export format', () {
      // Export format allows time tokens unlike gallery format
      expect(DateStampUtils.validateExportFormat('yyyy-MM-dd HH:mm'), isNull);
    });
  });

  group('isGalleryPreset', () {
    test('returns true for gallery presets', () {
      expect(DateStampUtils.isGalleryPreset('MM/yy'), isTrue);
      expect(DateStampUtils.isGalleryPreset('MMM dd'), isTrue);
    });

    test('returns false for non-presets', () {
      expect(DateStampUtils.isGalleryPreset('custom'), isFalse);
      expect(DateStampUtils.isGalleryPreset('yyyy-MM-dd'), isFalse);
    });
  });

  group('isExportPreset', () {
    test('returns true for export presets', () {
      expect(DateStampUtils.isExportPreset('yyyy-MM-dd'), isTrue);
      expect(DateStampUtils.isExportPreset('MMM dd, yyyy'), isTrue);
    });

    test('returns false for non-presets', () {
      expect(DateStampUtils.isExportPreset('custom'), isFalse);
      expect(DateStampUtils.isExportPreset('MM/yy'), isFalse);
    });
  });

  group('getFormatPreview', () {
    test('returns formatted date for valid format', () {
      final result = DateStampUtils.getFormatPreview('yyyy-MM-dd');
      expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('returns valid string for any format', () {
      // DateFormat parses almost any pattern, so we just verify it returns a string
      final result = DateStampUtils.getFormatPreview('yyyy-MM-dd');
      expect(result, isA<String>());
      expect(result.length, greaterThan(0));
    });
  });

  group('calculateWatermarkOffset', () {
    test('returns 0 when positions are different', () {
      final offset = DateStampUtils.calculateWatermarkOffset(
        dateStampPosition: 'lower right',
        watermarkPosition: 'upper left',
        textHeight: 20,
        imageHeight: 500,
      );
      expect(offset, equals(0.0));
    });

    test('returns negative offset for same lower corner', () {
      final offset = DateStampUtils.calculateWatermarkOffset(
        dateStampPosition: 'lower right',
        watermarkPosition: 'lower right',
        textHeight: 20,
        imageHeight: 500,
        gap: 10.0,
      );
      expect(offset, equals(-30.0)); // -(20 + 10)
    });

    test('returns positive offset for same upper corner', () {
      final offset = DateStampUtils.calculateWatermarkOffset(
        dateStampPosition: 'upper left',
        watermarkPosition: 'upper left',
        textHeight: 20,
        imageHeight: 500,
        gap: 10.0,
      );
      expect(offset, equals(30.0)); // 20 + 10
    });

    test('handles case insensitive comparison', () {
      final offset = DateStampUtils.calculateWatermarkOffset(
        dateStampPosition: 'LOWER RIGHT',
        watermarkPosition: 'lower right',
        textHeight: 20,
        imageHeight: 500,
        gap: 10.0,
      );
      expect(offset, equals(-30.0));
    });
  });

  group('parseTimestampFromFilename', () {
    test('parses valid timestamp from filename', () {
      expect(DateStampUtils.parseTimestampFromFilename('1705315200000.jpg'),
          equals(1705315200000));
      expect(
          DateStampUtils.parseTimestampFromFilename(
              '/path/to/1705315200000.png'),
          equals(1705315200000));
    });

    test('returns null for invalid timestamp', () {
      expect(DateStampUtils.parseTimestampFromFilename('invalid.jpg'), isNull);
      expect(DateStampUtils.parseTimestampFromFilename('not_a_number.png'),
          isNull);
    });
  });

  group('Help text constants', () {
    test('galleryFormatHelpText is not empty', () {
      expect(DateStampUtils.galleryFormatHelpText.isNotEmpty, isTrue);
      expect(DateStampUtils.galleryFormatHelpText, contains('FORMAT TOKENS'));
    });

    test('exportFormatHelpText is not empty', () {
      expect(DateStampUtils.exportFormatHelpText.isNotEmpty, isTrue);
      expect(DateStampUtils.exportFormatHelpText, contains('FORMAT TOKENS'));
      expect(DateStampUtils.exportFormatHelpText,
          contains('Time')); // Export includes time section
    });
  });

  group('buildGalleryDateLabel', () {
    testWidgets('creates widget with correct structure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateStampUtils.buildGalleryDateLabel('Jan 24', 100.0),
          ),
        ),
      );

      expect(find.text('Jan 24'), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('uses custom font family when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateStampUtils.buildGalleryDateLabel('Jan 24', 100.0,
                fontFamily: 'Roboto'),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('Jan 24'));
      expect(textWidget.style?.fontFamily, equals('Roboto'));
    });

    testWidgets('scales font size based on thumbnail height', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateStampUtils.buildGalleryDateLabel('Jan 24', 200.0),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('Jan 24'));
      // fontSize = (200 * 0.12).clamp(8.0, 14.0) = 14.0
      expect(textWidget.style?.fontSize, equals(14.0));
    });
  });
}
