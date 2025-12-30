import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/project_utils.dart';

/// Unit tests for ProjectUtils.
/// Tests pure utility functions that don't require database/filesystem.
void main() {
  group('ProjectUtils Class', () {
    test('ProjectUtils class is accessible', () {
      expect(ProjectUtils, isNotNull);
    });
  });

  group('ProjectUtils.convertExtensionToPng', () {
    test('converts .jpg to .png', () {
      final result = ProjectUtils.convertExtensionToPng('/path/to/image.jpg');
      expect(result, '/path/to/image.png');
    });

    test('preserves path without .jpg extension', () {
      final result = ProjectUtils.convertExtensionToPng('/path/to/image.png');
      expect(result, '/path/to/image.png');
    });

    test('only replaces .jpg at end of path', () {
      final result = ProjectUtils.convertExtensionToPng('/path/jpg/image.jpg');
      expect(result, '/path/jpg/image.png');
    });

    test('handles path with no extension', () {
      final result = ProjectUtils.convertExtensionToPng('/path/to/image');
      expect(result, '/path/to/image');
    });

    test('handles empty string', () {
      final result = ProjectUtils.convertExtensionToPng('');
      expect(result, '');
    });

    test('only converts lowercase .jpg', () {
      // The regex is \.jpg$ so it only matches lowercase
      final result = ProjectUtils.convertExtensionToPng('/path/to/image.JPG');
      expect(result, '/path/to/image.JPG');
    });
  });

  group('ProjectUtils.getTimeDiff', () {
    test('returns 0 for same dates', () {
      final date = DateTime(2024, 1, 15);
      final result = ProjectUtils.getTimeDiff(date, date);
      expect(result, 0);
    });

    test('returns positive for later end date', () {
      final start = DateTime(2024, 1, 1);
      final end = DateTime(2024, 1, 10);
      final result = ProjectUtils.getTimeDiff(start, end);
      expect(result, 9);
    });

    test('returns negative for earlier end date', () {
      final start = DateTime(2024, 1, 10);
      final end = DateTime(2024, 1, 1);
      final result = ProjectUtils.getTimeDiff(start, end);
      expect(result, -9);
    });

    test('handles year boundaries', () {
      final start = DateTime(2023, 12, 31);
      final end = DateTime(2024, 1, 1);
      final result = ProjectUtils.getTimeDiff(start, end);
      expect(result, 1);
    });

    test('handles large differences', () {
      final start = DateTime(2020, 1, 1);
      final end = DateTime(2024, 1, 1);
      final result = ProjectUtils.getTimeDiff(start, end);
      // 4 years including leap year
      expect(result, greaterThan(1400));
    });
  });

  group('ProjectUtils.parseTimestampFromFilename', () {
    test('parses numeric filename', () {
      final result =
          ProjectUtils.parseTimestampFromFilename('/path/1704067200000.jpg');
      expect(result, 1704067200000);
    });

    test('handles different extensions', () {
      final result1 =
          ProjectUtils.parseTimestampFromFilename('/path/1234567890.png');
      expect(result1, 1234567890);

      final result2 =
          ProjectUtils.parseTimestampFromFilename('/path/1234567890.jpeg');
      expect(result2, 1234567890);
    });

    test('returns 0 for non-numeric filename', () {
      final result = ProjectUtils.parseTimestampFromFilename('/path/image.jpg');
      expect(result, 0);
    });

    test('returns 0 for empty path', () {
      final result = ProjectUtils.parseTimestampFromFilename('');
      expect(result, 0);
    });

    test('handles filename without extension', () {
      final result =
          ProjectUtils.parseTimestampFromFilename('/path/1234567890');
      expect(result, 1234567890);
    });

    test('handles path with numeric directory names', () {
      final result =
          ProjectUtils.parseTimestampFromFilename('/123/456/789.jpg');
      expect(result, 789);
    });
  });

  group('ProjectUtils.calculateDateDifference', () {
    test('returns zero duration for same timestamps', () {
      final timestamp = 1704067200000;
      final result = ProjectUtils.calculateDateDifference(timestamp, timestamp);
      expect(result.inDays, 0);
    });

    test('returns positive duration for later end timestamp', () {
      final start = 1704067200000; // 2024-01-01 00:00:00 UTC
      final end = 1704153600000; // 2024-01-02 00:00:00 UTC (1 day later)
      final result = ProjectUtils.calculateDateDifference(start, end);
      expect(result.inDays, 1);
    });

    test('returns negative duration for earlier end timestamp', () {
      final start = 1704153600000;
      final end = 1704067200000;
      final result = ProjectUtils.calculateDateDifference(start, end);
      expect(result.inDays, -1);
    });

    test('handles millisecond precision', () {
      final start = 1704067200000;
      final end = 1704067200500;
      final result = ProjectUtils.calculateDateDifference(start, end);
      expect(result.inMilliseconds, 500);
    });
  });

  group('ProjectUtils.getUniquePhotoDates', () {
    test('returns empty list for empty photos', () {
      final result = ProjectUtils.getUniquePhotoDates([]);
      expect(result, isEmpty);
    });

    test('returns single date for single photo', () {
      final photos = [
        {'timestamp': '1704067200000'}
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 1);
    });

    test('returns unique dates only', () {
      // Two photos on same day
      final photos = [
        {'timestamp': '1704067200000'}, // 2024-01-01 00:00:00
        {'timestamp': '1704070800000'}, // 2024-01-01 01:00:00 (same day)
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 1);
    });

    test('returns multiple dates for photos on different days', () {
      final photos = [
        {'timestamp': '1704067200000'}, // 2024-01-01
        {'timestamp': '1704153600000'}, // 2024-01-02
        {'timestamp': '1704240000000'}, // 2024-01-03
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 3);
    });

    test('returns dates sorted newest first', () {
      final photos = [
        {'timestamp': '1704067200000'}, // earliest
        {'timestamp': '1704240000000'}, // latest
        {'timestamp': '1704153600000'}, // middle
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 3);
      // Dates should be sorted newest first
      final firstDate = DateTime.parse(result[0]);
      final lastDate = DateTime.parse(result[2]);
      expect(firstDate.isAfter(lastDate), isTrue);
    });

    test('handles missing timestamp field', () {
      final photos = [
        {'otherField': 'value'}
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      // Should handle gracefully
      expect(result, isA<List<String>>());
    });

    test('handles null timestamp', () {
      final photos = [
        {'timestamp': null}
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result, isA<List<String>>());
    });

    test('handles captureOffsetMinutes', () {
      final photos = [
        {'timestamp': '1704067200000', 'captureOffsetMinutes': 60}
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 1);
    });
  });

  group('ProjectUtils Method Signatures', () {
    test('calculateStreak method exists', () {
      expect(ProjectUtils.calculateStreak, isA<Function>());
    });

    test('isDefaultProject method exists', () {
      expect(ProjectUtils.isDefaultProject, isA<Function>());
    });

    test('deleteProject method exists', () {
      expect(ProjectUtils.deleteProject, isA<Function>());
    });

    test('deleteFile method exists', () {
      expect(ProjectUtils.deleteFile, isA<Function>());
    });

    test('deleteImage method exists', () {
      expect(ProjectUtils.deleteImage, isA<Function>());
    });

    test('deletePngFileIfExists method exists', () {
      expect(ProjectUtils.deletePngFileIfExists, isA<Function>());
    });

    test('loadImage method exists', () {
      expect(ProjectUtils.loadImage, isA<Function>());
    });

    test('deleteStabilizedFileIfExists method exists', () {
      expect(ProjectUtils.deleteStabilizedFileIfExists, isA<Function>());
    });

    test('deletePhotoFromDatabase method exists', () {
      expect(ProjectUtils.deletePhotoFromDatabase, isA<Function>());
    });

    test('deletePhotoFromDatabaseAndReturnCount method exists', () {
      expect(
          ProjectUtils.deletePhotoFromDatabaseAndReturnCount, isA<Function>());
    });

    test('loadImageData method exists', () {
      expect(ProjectUtils.loadImageData, isA<Function>());
    });
  });

  group('ProjectUtils Static Nature', () {
    test('all methods are static', () {
      // ignore: unnecessary_type_check
      expect(ProjectUtils.convertExtensionToPng is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ProjectUtils.getTimeDiff is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ProjectUtils.parseTimestampFromFilename is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ProjectUtils.calculateDateDifference is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(ProjectUtils.getUniquePhotoDates is Function, isTrue);
    });
  });
}
