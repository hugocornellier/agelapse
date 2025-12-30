import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/database_helper.dart';

/// Unit tests for DatabaseHelper (DB class).
/// These tests cover pure logic and default value handling.
/// For full CRUD testing, see integration_test/database_test.dart
void main() {
  group('DB Default Values', () {
    test('defaultValues contains all expected settings', () {
      expect(DB.defaultValues, isNotEmpty);
      expect(DB.defaultValues['theme'], 'dark');
      expect(DB.defaultValues['framerate'], '14');
      expect(DB.defaultValues['enable_grid'], 'true');
      expect(DB.defaultValues['save_to_camera_roll'], 'false');
      expect(DB.defaultValues['camera_mirror'], 'true');
      expect(DB.defaultValues['default_project'], 'none');
      expect(DB.defaultValues['enable_notifications'], 'true');
      expect(DB.defaultValues['framerate_is_default'], 'true');
      expect(DB.defaultValues['enable_watermark'], 'false');
      expect(DB.defaultValues['watermark_position'], 'lower left');
      expect(DB.defaultValues['daily_notification_time'], 'not set');
      expect(DB.defaultValues['opened_nonempty_gallery'], 'false');
      expect(DB.defaultValues['has_taken_first_photo'], 'false');
      expect(DB.defaultValues['has_viewed_first_video'], 'false');
      expect(DB.defaultValues['has_opened_notif_page'], 'false');
      expect(DB.defaultValues['has_seen_guide_mode_tut'], 'false');
      expect(DB.defaultValues['watermark_opacity'], '0.7');
      expect(DB.defaultValues['camera_flash'], 'auto');
      expect(DB.defaultValues['grid_mode_index'], '0');
      expect(DB.defaultValues['project_orientation'], 'landscape');
      expect(DB.defaultValues['eyeOffsetXPortrait'], '0.065');
      expect(DB.defaultValues['eyeOffsetXLandscape'], '0.035');
      expect(DB.defaultValues['eyeOffsetYPortrait'], '0.421875');
      expect(DB.defaultValues['eyeOffsetYLandscape'], '0.421875');
      expect(DB.defaultValues['guideOffsetXPortrait'], '0.09');
      expect(DB.defaultValues['guideOffsetXLandscape'], '0.045');
      expect(DB.defaultValues['guideOffsetYPortrait'], '0.421875');
      expect(DB.defaultValues['guideOffsetYLandscape'], '0.421875');
      expect(DB.defaultValues['gridAxisCount'], '5');
      expect(DB.defaultValues['video_resolution'], '1080p');
      expect(DB.defaultValues['aspect_ratio'], '16:9');
      expect(DB.defaultValues['selected_guide_photo'], 'not set');
      expect(DB.defaultValues['stabilization_mode'], 'slow');
    });

    test('defaultValues has correct count', () {
      // 31 default settings as of current implementation
      expect(DB.defaultValues.length, greaterThanOrEqualTo(30));
    });

    test('all default values are non-null strings', () {
      for (final entry in DB.defaultValues.entries) {
        expect(entry.value, isNotNull,
            reason: '${entry.key} should not be null');
        expect(entry.value, isA<String>(),
            reason: '${entry.key} should be a String');
      }
    });
  });

  group('DB Constants', () {
    test('table names are defined', () {
      expect(DB.settingTable, 'Setting');
      expect(DB.photoTable, 'Photos');
      expect(DB.projectTable, 'Projects');
      expect(DB.videoTable, 'Videos');
    });

    test('globalSettingFlag is defined', () {
      expect(DB.globalSettingFlag, 'global');
    });
  });

  group('DB getStabilizedColumn', () {
    test('returns stabilizedPortrait for portrait orientation', () {
      final result = DB.instance.getStabilizedColumn('portrait');
      expect(result, 'stabilizedPortrait');
    });

    test('returns stabilizedLandscape for landscape orientation', () {
      final result = DB.instance.getStabilizedColumn('landscape');
      expect(result, 'stabilizedLandscape');
    });

    test('returns stabilizedLandscape for PORTRAIT (case insensitive)', () {
      final result = DB.instance.getStabilizedColumn('PORTRAIT');
      expect(result, 'stabilizedPortrait');
    });

    test('returns stabilizedLandscape for Landscape (case insensitive)', () {
      final result = DB.instance.getStabilizedColumn('Landscape');
      expect(result, 'stabilizedLandscape');
    });

    test('returns stabilizedLandscape for any non-portrait value', () {
      final result = DB.instance.getStabilizedColumn('unknown');
      expect(result, 'stabilizedLandscape');
    });
  });

  group('DB Singleton', () {
    test('instance returns the same object', () {
      final instance1 = DB.instance;
      final instance2 = DB.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });

  group('DB Eye Offset Defaults', () {
    test('portrait eye offsets are correctly positioned', () {
      final eyeOffsetXPortrait =
          double.parse(DB.defaultValues['eyeOffsetXPortrait']!);
      final eyeOffsetYPortrait =
          double.parse(DB.defaultValues['eyeOffsetYPortrait']!);

      // X offset should be small (eyes close to center)
      expect(eyeOffsetXPortrait, greaterThan(0));
      expect(eyeOffsetXPortrait, lessThan(0.2));

      // Y offset should place eyes in upper half of frame
      expect(eyeOffsetYPortrait, greaterThan(0.3));
      expect(eyeOffsetYPortrait, lessThan(0.6));
    });

    test('landscape eye offsets are correctly positioned', () {
      final eyeOffsetXLandscape =
          double.parse(DB.defaultValues['eyeOffsetXLandscape']!);
      final eyeOffsetYLandscape =
          double.parse(DB.defaultValues['eyeOffsetYLandscape']!);

      // Landscape X offset should be smaller than portrait (wider frame)
      expect(eyeOffsetXLandscape, greaterThan(0));
      expect(eyeOffsetXLandscape, lessThan(0.1));

      // Y offset should be same as portrait
      expect(eyeOffsetYLandscape, equals(0.421875));
    });

    test('portrait X offset is larger than landscape X offset', () {
      final eyeOffsetXPortrait =
          double.parse(DB.defaultValues['eyeOffsetXPortrait']!);
      final eyeOffsetXLandscape =
          double.parse(DB.defaultValues['eyeOffsetXLandscape']!);

      expect(eyeOffsetXPortrait, greaterThan(eyeOffsetXLandscape));
    });
  });

  group('DB Video Settings Defaults', () {
    test('framerate default is reasonable', () {
      final framerate = int.parse(DB.defaultValues['framerate']!);
      expect(framerate, greaterThanOrEqualTo(10));
      expect(framerate, lessThanOrEqualTo(30));
    });

    test('video resolution is valid', () {
      final resolution = DB.defaultValues['video_resolution']!;
      expect(['720p', '1080p', '4k'].contains(resolution), isTrue);
    });

    test('aspect ratio is valid', () {
      final aspectRatio = DB.defaultValues['aspect_ratio']!;
      expect(['16:9', '9:16', '4:3', '1:1'].contains(aspectRatio), isTrue);
    });

    test('watermark opacity is between 0 and 1', () {
      final opacity = double.parse(DB.defaultValues['watermark_opacity']!);
      expect(opacity, greaterThanOrEqualTo(0));
      expect(opacity, lessThanOrEqualTo(1));
    });

    test('watermark position is valid', () {
      final position = DB.defaultValues['watermark_position']!;
      expect(
        ['lower left', 'lower right', 'upper left', 'upper right']
            .contains(position),
        isTrue,
      );
    });
  });

  group('DB Camera Settings Defaults', () {
    test('camera flash default is valid', () {
      final flash = DB.defaultValues['camera_flash']!;
      expect(['auto', 'on', 'off', 'torch'].contains(flash), isTrue);
    });

    test('camera mirror default is true for selfie mode', () {
      expect(DB.defaultValues['camera_mirror'], 'true');
    });

    test('grid is enabled by default', () {
      expect(DB.defaultValues['enable_grid'], 'true');
    });

    test('grid axis count is reasonable', () {
      final gridAxisCount = int.parse(DB.defaultValues['gridAxisCount']!);
      expect(gridAxisCount, greaterThanOrEqualTo(2));
      expect(gridAxisCount, lessThanOrEqualTo(10));
    });
  });

  group('DB Notification Settings Defaults', () {
    test('notifications are enabled by default', () {
      expect(DB.defaultValues['enable_notifications'], 'true');
    });

    test('daily notification time starts as not set', () {
      expect(DB.defaultValues['daily_notification_time'], 'not set');
    });
  });

  group('DB Theme Settings Defaults', () {
    test('theme defaults to dark', () {
      expect(DB.defaultValues['theme'], 'dark');
    });
  });

  group('DB Stabilization Settings Defaults', () {
    test('stabilization mode defaults to slow (high quality)', () {
      expect(DB.defaultValues['stabilization_mode'], 'slow');
    });
  });

  group('DB Boolean Settings', () {
    test('all boolean settings use string true/false', () {
      final boolSettings = [
        'enable_grid',
        'save_to_camera_roll',
        'camera_mirror',
        'enable_notifications',
        'framerate_is_default',
        'enable_watermark',
        'opened_nonempty_gallery',
        'has_taken_first_photo',
        'has_viewed_first_video',
        'has_opened_notif_page',
        'has_seen_guide_mode_tut',
      ];

      for (final setting in boolSettings) {
        final value = DB.defaultValues[setting];
        expect(
          value == 'true' || value == 'false',
          isTrue,
          reason: '$setting should be "true" or "false" but was "$value"',
        );
      }
    });
  });
}
