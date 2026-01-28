import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/date_stamp_utils.dart';

/// Unit tests for SettingsUtil.
/// Tests settings loading methods.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsUtil Fallback Constants', () {
    test('fallbackWatermarkPosition is Lower left', () {
      expect(SettingsUtil.fallbackWatermarkPosition, equals('Lower left'));
    });

    test('fallbackFramerate is 14', () {
      expect(SettingsUtil.fallbackFramerate, equals(14));
    });

    test('fallbackWatermarkOpacity is 0.7', () {
      expect(SettingsUtil.fallbackWatermarkOpacity, equals('0.7'));
    });

    test('fallbackDateStampPosition is lower right', () {
      expect(
        SettingsUtil.fallbackDateStampPosition,
        equals(DateStampUtils.positionLowerRight),
      );
    });

    test('fallbackGalleryDateFormat matches DateStampUtils', () {
      expect(
        SettingsUtil.fallbackGalleryDateFormat,
        equals(DateStampUtils.galleryFormatMMYY),
      );
    });

    test('fallbackExportDateFormat matches DateStampUtils', () {
      expect(
        SettingsUtil.fallbackExportDateFormat,
        equals(DateStampUtils.exportFormatLong),
      );
    });

    test('fallbackDateStampSizePercent is 3', () {
      expect(SettingsUtil.fallbackDateStampSizePercent, equals(3));
    });

    test('fallbackDateStampOpacity is 1.0', () {
      expect(SettingsUtil.fallbackDateStampOpacity, equals('1.0'));
    });

    test('fallbackBackgroundColor is black', () {
      expect(SettingsUtil.fallbackBackgroundColor, equals('#000000'));
    });
  });

  group('DateStampSettings', () {
    group('constructor', () {
      test('creates instance with all required parameters', () {
        const settings = DateStampSettings(
          galleryLabelsEnabled: true,
          galleryRawLabelsEnabled: false,
          galleryFormat: 'MM/YY',
          exportEnabled: true,
          exportPosition: 'Lower right',
          exportFormat: 'MMMM d, yyyy',
          exportSizePercent: 5,
          exportOpacity: 0.8,
          galleryFont: 'Roboto Mono',
          exportFont: 'Custom Font',
        );

        expect(settings.galleryLabelsEnabled, isTrue);
        expect(settings.galleryRawLabelsEnabled, isFalse);
        expect(settings.galleryFormat, equals('MM/YY'));
        expect(settings.exportEnabled, isTrue);
        expect(settings.exportPosition, equals('Lower right'));
        expect(settings.exportFormat, equals('MMMM d, yyyy'));
        expect(settings.exportSizePercent, equals(5));
        expect(settings.exportOpacity, equals(0.8));
        expect(settings.galleryFont, equals('Roboto Mono'));
        expect(settings.exportFont, equals('Custom Font'));
      });
    });

    group('resolvedExportFont', () {
      test('returns export font when not same as gallery', () {
        const settings = DateStampSettings(
          galleryLabelsEnabled: false,
          galleryRawLabelsEnabled: false,
          galleryFormat: 'MM/YY',
          exportEnabled: false,
          exportPosition: 'Lower right',
          exportFormat: 'MMMM d, yyyy',
          exportSizePercent: 3,
          exportOpacity: 1.0,
          galleryFont: 'Roboto Mono',
          exportFont: 'Custom Export Font',
        );

        expect(settings.resolvedExportFont, equals('Custom Export Font'));
      });

      test('returns gallery font when export font is same as gallery', () {
        const settings = DateStampSettings(
          galleryLabelsEnabled: false,
          galleryRawLabelsEnabled: false,
          galleryFormat: 'MM/YY',
          exportEnabled: false,
          exportPosition: 'Lower right',
          exportFormat: 'MMMM d, yyyy',
          exportSizePercent: 3,
          exportOpacity: 1.0,
          galleryFont: 'Roboto Mono',
          exportFont: DateStampUtils.fontSameAsGallery,
        );

        expect(settings.resolvedExportFont, equals('Roboto Mono'));
      });
    });

    group('defaults', () {
      test('defaults has correct galleryLabelsEnabled', () {
        expect(DateStampSettings.defaults.galleryLabelsEnabled, isFalse);
      });

      test('defaults has correct galleryRawLabelsEnabled', () {
        expect(DateStampSettings.defaults.galleryRawLabelsEnabled, isFalse);
      });

      test('defaults has correct galleryFormat', () {
        expect(
          DateStampSettings.defaults.galleryFormat,
          equals(DateStampUtils.galleryFormatMMYY),
        );
      });

      test('defaults has correct exportEnabled', () {
        expect(DateStampSettings.defaults.exportEnabled, isFalse);
      });

      test('defaults has correct exportPosition', () {
        expect(
          DateStampSettings.defaults.exportPosition,
          equals(DateStampUtils.positionLowerRight),
        );
      });

      test('defaults has correct exportFormat', () {
        expect(
          DateStampSettings.defaults.exportFormat,
          equals(DateStampUtils.exportFormatLong),
        );
      });

      test('defaults has correct exportSizePercent', () {
        expect(DateStampSettings.defaults.exportSizePercent, equals(3));
      });

      test('defaults has correct exportOpacity', () {
        expect(DateStampSettings.defaults.exportOpacity, equals(1.0));
      });

      test('defaults has correct galleryFont', () {
        expect(
          DateStampSettings.defaults.galleryFont,
          equals(DateStampUtils.defaultFont),
        );
      });

      test('defaults has correct exportFont', () {
        expect(
          DateStampSettings.defaults.exportFont,
          equals(DateStampUtils.fontSameAsGallery),
        );
      });

      test('defaults resolvedExportFont returns gallery font', () {
        expect(
          DateStampSettings.defaults.resolvedExportFont,
          equals(DateStampUtils.defaultFont),
        );
      });
    });
  });

  group('SettingsUtil Loading Methods', () {
    test('loadEnableGrid returns Future<bool>', () {
      final result = SettingsUtil.loadEnableGrid();
      expect(result, isA<Future<bool>>());
    });

    test('loadSaveToCameraRoll returns Future<bool>', () {
      final result = SettingsUtil.loadSaveToCameraRoll();
      expect(result, isA<Future<bool>>());
    });

    test('loadCameraMirror returns Future<bool>', () async {
      final result = SettingsUtil.loadCameraMirror('1');
      expect(result, isA<Future<bool>>());
      // Await to handle async error (path_provider not available in tests)
      try {
        await result;
      } on MissingPluginException {
        // Expected in test environment without path_provider
      }
    });

    test('loadCameraTimer returns Future<int>', () async {
      final result = SettingsUtil.loadCameraTimer('1');
      expect(result, isA<Future<int>>());
      // Await to handle async error (path_provider not available in tests)
      try {
        await result;
      } on MissingPluginException {
        // Expected in test environment without path_provider
      }
    });

    test('loadNotificationSetting returns Future<bool>', () {
      final result = SettingsUtil.loadNotificationSetting();
      expect(result, isA<Future<bool>>());
    });

    test('loadProjectOrientation returns Future<String>', () async {
      final result = SettingsUtil.loadProjectOrientation('1');
      expect(result, isA<Future<String>>());
      // Await to handle async error (path_provider not available in tests)
      try {
        await result;
      } on MissingPluginException {
        // Expected in test environment without path_provider
      }
    });
  });

  group('SettingsUtil Method Signatures', () {
    test('loadEnableGrid accepts no parameters', () {
      // Should compile and return Future<bool>
      final result = SettingsUtil.loadEnableGrid();
      expect(result, isA<Future<bool>>());
    });

    test('loadProjectOrientation accepts project ID string', () async {
      // Should compile and return Future<String>
      final result1 = SettingsUtil.loadProjectOrientation('1');
      final result2 = SettingsUtil.loadProjectOrientation('999');
      final result3 = SettingsUtil.loadProjectOrientation('test');

      expect(result1, isA<Future<String>>());
      expect(result2, isA<Future<String>>());
      expect(result3, isA<Future<String>>());

      // Await to handle async errors (path_provider not available in tests)
      for (final future in [result1, result2, result3]) {
        try {
          await future;
        } on MissingPluginException {
          // Expected in test environment without path_provider
        }
      }
    });
  });
}
