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

    test('treats spring DST calendar boundaries as one day (2026)', () {
      final start = DateTime.parse('2026-03-29T00:00:00+01:00');
      final end = DateTime.parse('2026-03-30T00:00:00+02:00');
      final result = ProjectUtils.getTimeDiff(start, end);
      expect(result, 1);
    });

    test('treats spring DST calendar boundaries as one day (2025)', () {
      final start = DateTime.parse('2025-03-30T00:00:00+01:00');
      final end = DateTime.parse('2025-03-31T00:00:00+02:00');
      final result = ProjectUtils.getTimeDiff(start, end);
      expect(result, 1);
    });

    test('treats fall-back DST (autumn) as one day', () {
      // October 26, 2025: clocks fall back, day is 25 hours
      final start = DateTime.parse('2025-10-26T00:00:00+02:00');
      final end = DateTime.parse('2025-10-27T00:00:00+01:00');
      final result = ProjectUtils.getTimeDiff(start, end);
      expect(result, 1);
    });

    test('handles leap year boundary', () {
      // 2024 is a leap year
      expect(
          ProjectUtils.getTimeDiff(
            DateTime(2024, 2, 28),
            DateTime(2024, 2, 29),
          ),
          1);
      expect(
          ProjectUtils.getTimeDiff(
            DateTime(2024, 2, 29),
            DateTime(2024, 3, 1),
          ),
          1);
    });

    test('handles non-leap year Feb 28 to Mar 1', () {
      // 2025 is not a leap year
      expect(
          ProjectUtils.getTimeDiff(
            DateTime(2025, 2, 28),
            DateTime(2025, 3, 1),
          ),
          1);
    });
  });

  group('ProjectUtils.parseTimestampFromFilename', () {
    test('parses numeric filename', () {
      final result = ProjectUtils.parseTimestampFromFilename(
        '/path/1704067200000.jpg',
      );
      expect(result, 1704067200000);
    });

    test('handles different extensions', () {
      final result1 = ProjectUtils.parseTimestampFromFilename(
        '/path/1234567890.png',
      );
      expect(result1, 1234567890);

      final result2 = ProjectUtils.parseTimestampFromFilename(
        '/path/1234567890.jpeg',
      );
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
      final result = ProjectUtils.parseTimestampFromFilename(
        '/path/1234567890',
      );
      expect(result, 1234567890);
    });

    test('handles path with numeric directory names', () {
      final result = ProjectUtils.parseTimestampFromFilename(
        '/123/456/789.jpg',
      );
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
        {'timestamp': '1704067200000'},
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 1);
    });

    test('returns unique dates only', () {
      // Two photos on same day - sorted newest first (descending)
      final photos = [
        {'timestamp': '1704070800000'}, // 2024-01-01 01:00:00 (later)
        {
          'timestamp': '1704067200000',
        }, // 2024-01-01 00:00:00 (earlier, same day)
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 1);
    });

    test('returns multiple dates for photos on different days', () {
      // Photos sorted newest first (descending timestamp order)
      final photos = [
        {'timestamp': '1704240000000'}, // 2024-01-03 (newest)
        {'timestamp': '1704153600000'}, // 2024-01-02
        {'timestamp': '1704067200000'}, // 2024-01-01 (oldest)
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 3);
    });

    test('returns dates sorted newest first', () {
      // Input already sorted newest first (as from getPhotosByProjectIDNewestFirst)
      final photos = [
        {'timestamp': '1704240000000'}, // latest (2024-01-03)
        {'timestamp': '1704153600000'}, // middle (2024-01-02)
        {'timestamp': '1704067200000'}, // earliest (2024-01-01)
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
        {'otherField': 'value'},
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      // Should handle gracefully
      expect(result, isA<List<String>>());
    });

    test('handles null timestamp', () {
      final photos = [
        {'timestamp': null},
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result, isA<List<String>>());
    });

    test('handles captureOffsetMinutes', () {
      final photos = [
        {'timestamp': '1704067200000', 'captureOffsetMinutes': 60},
      ];
      final result = ProjectUtils.getUniquePhotoDates(photos);
      expect(result.length, 1);
    });
  });

  group('ProjectUtils.calculatePhotoStreakFromPhotos', () {
    test('counts consecutive days across a spring DST offset change', () {
      final photos = [
        {
          'timestamp':
              DateTime.utc(2026, 3, 30, 8).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp': DateTime.utc(2026, 3, 29, 0, 30)
              .millisecondsSinceEpoch
              .toString(),
          'captureOffsetMinutes': 60,
        },
        {
          'timestamp':
              DateTime.utc(2026, 3, 28, 9).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 60,
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2026, 3, 30, 12),
      );

      expect(result, 3);
    });

    test('returns 1 for a single photo taken today', () {
      final photos = [
        {
          'timestamp':
              DateTime.utc(2024, 6, 15, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2024, 6, 15, 18),
      );

      expect(result, 1);
    });

    test('returns 0 when latest photo is more than 1 day old', () {
      final photos = [
        {
          'timestamp':
              DateTime.utc(2024, 6, 10, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2024, 6, 15, 18),
      );

      expect(result, 0);
    });

    test('counts streak when latest photo is from yesterday', () {
      final photos = [
        {
          'timestamp':
              DateTime.utc(2024, 6, 14, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 13, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 12, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2024, 6, 15, 8),
      );

      expect(result, 3);
    });

    test('handles photos with null captureOffsetMinutes', () {
      final photos = [
        {
          'timestamp':
              DateTime.utc(2024, 6, 15, 10).millisecondsSinceEpoch.toString(),
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 14, 10).millisecondsSinceEpoch.toString(),
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 13, 10).millisecondsSinceEpoch.toString(),
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2024, 6, 15, 18),
      );

      // Without offset, falls back to device local time.
      // Exact streak depends on test machine timezone, but should not crash.
      expect(result, greaterThanOrEqualTo(1));
    });

    test('long streak spanning both fall-back and spring-forward DST', () {
      // Build a 365-day streak: 2025-04-01 back to 2024-04-02
      // This spans both autumn fall-back (Oct 27 2024) and spring-forward (Mar 30 2025)
      final photos = <Map<String, dynamic>>[];
      for (int i = 0; i < 365; i++) {
        final day = DateTime.utc(2025, 4, 1).subtract(Duration(days: i));
        // Alternate offsets to simulate CET/CEST
        final offset = (day.month >= 4 && day.month <= 10) ? 120 : 60;
        photos.add({
          'timestamp': DateTime.utc(day.year, day.month, day.day, 12)
              .millisecondsSinceEpoch
              .toString(),
          'captureOffsetMinutes': offset,
        });
      }

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2025, 4, 1, 18),
      );

      expect(result, 365);
    });

    test('returns 0 for empty photos', () {
      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        [],
        now: DateTime(2024, 6, 15),
      );
      expect(result, 0);
    });

    test('stops at gap in the middle of dates', () {
      // Photos on Jun 15, 14, 13, 11 (gap on 12th) → streak = 3
      final photos = [
        {
          'timestamp':
              DateTime.utc(2024, 6, 15, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 14, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 13, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 11, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2024, 6, 15, 18),
      );

      expect(result, 3);
    });

    test('deduplicates multiple photos on the same day', () {
      // 3 photos on Jun 15, 1 on Jun 14 → streak = 2
      final photos = [
        {
          'timestamp':
              DateTime.utc(2024, 6, 15, 18).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 15, 12).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 15, 8).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
        {
          'timestamp':
              DateTime.utc(2024, 6, 14, 10).millisecondsSinceEpoch.toString(),
          'captureOffsetMinutes': 120,
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2024, 6, 15, 20),
      );

      expect(result, 2);
    });

    test('handles future photo date gracefully (negative headDiff)', () {
      // Photo appears to be from "tomorrow" due to timezone offset
      // UTC 2024-06-15 23:30 with +120 offset → capture-local = Jun 16 01:30
      final photos = [
        {
          'timestamp': DateTime.utc(2024, 6, 15, 23, 30)
              .millisecondsSinceEpoch
              .toString(),
          'captureOffsetMinutes': 120,
        },
      ];

      final result = ProjectUtils.calculatePhotoStreakFromPhotos(
        photos,
        now: DateTime(2024, 6, 15, 20),
      );

      // headDiff is negative (-1), which is not > 1, so streak = 1
      expect(result, 1);
    });
  });

  group('ProjectUtils.photoWasTakenTodayForPhotos', () {
    test('compares capture-local photo day against the current device day', () {
      final photos = [
        {
          'timestamp': DateTime.utc(2024, 1, 9, 23, 30)
              .millisecondsSinceEpoch
              .toString(),
          'captureOffsetMinutes': 120,
        },
      ];

      expect(
        ProjectUtils.photoWasTakenTodayForPhotos(
          photos,
          now: DateTime(2024, 1, 10, 8),
        ),
        isTrue,
      );
      expect(
        ProjectUtils.photoWasTakenTodayForPhotos(
          photos,
          now: DateTime(2024, 1, 9, 8),
        ),
        isFalse,
      );
    });

    test('returns false for empty photos', () {
      expect(
        ProjectUtils.photoWasTakenTodayForPhotos(
          [],
          now: DateTime(2024, 1, 10),
        ),
        isFalse,
      );
    });

    test('handles photo with null captureOffsetMinutes', () {
      final photos = [
        {
          'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      ];

      // Without offset, falls back to device-local. A photo just taken
      // should be "today" regardless.
      expect(
        ProjectUtils.photoWasTakenTodayForPhotos(photos),
        isTrue,
      );
    });
  });

  group('ProjectUtils Method Signatures', () {
    test('calculateStreak method exists', () {
      expect(ProjectUtils.calculateStreak, isA<Function>());
    });

    test('calculatePhotoStreakFromPhotos method exists', () {
      expect(ProjectUtils.calculatePhotoStreakFromPhotos, isA<Function>());
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
        ProjectUtils.deletePhotoFromDatabaseAndReturnCount,
        isA<Function>(),
      );
    });

    test('loadImageData method exists', () {
      expect(ProjectUtils.loadImageData, isA<Function>());
    });

    test('photoWasTakenTodayForPhotos method exists', () {
      expect(ProjectUtils.photoWasTakenTodayForPhotos, isA<Function>());
    });
  });

  group('ProjectUtils Static Nature', () {
    test('all methods are static', () {
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
