import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/capture_timezone.dart';

void main() {
  group('CaptureTimezone', () {
    group('extractOffset', () {
      test('returns null when photoData is null', () {
        expect(CaptureTimezone.extractOffset(null), isNull);
      });

      test('returns null when captureOffsetMinutes key is missing', () {
        expect(CaptureTimezone.extractOffset({}), isNull);
        expect(CaptureTimezone.extractOffset({'other': 'data'}), isNull);
      });

      test('returns null when captureOffsetMinutes is not an int', () {
        expect(
            CaptureTimezone.extractOffset({'captureOffsetMinutes': 'string'}),
            isNull);
        expect(CaptureTimezone.extractOffset({'captureOffsetMinutes': 3.14}),
            isNull);
        expect(CaptureTimezone.extractOffset({'captureOffsetMinutes': null}),
            isNull);
        expect(
            CaptureTimezone.extractOffset({
              'captureOffsetMinutes': [1, 2, 3]
            }),
            isNull);
      });

      test('returns int when captureOffsetMinutes is valid', () {
        expect(CaptureTimezone.extractOffset({'captureOffsetMinutes': 0}),
            equals(0));
        expect(CaptureTimezone.extractOffset({'captureOffsetMinutes': 60}),
            equals(60));
        expect(CaptureTimezone.extractOffset({'captureOffsetMinutes': -300}),
            equals(-300));
        expect(CaptureTimezone.extractOffset({'captureOffsetMinutes': 330}),
            equals(330));
      });

      test('handles map with additional keys', () {
        final data = {
          'timestamp': 1234567890,
          'captureOffsetMinutes': 120,
          'filename': 'test.jpg',
        };
        expect(CaptureTimezone.extractOffset(data), equals(120));
      });
    });

    group('toLocalDateTime', () {
      test('converts UTC timestamp with positive offset', () {
        // Jan 15, 2024 12:00:00 UTC = 1705320000000 ms
        final timestamp =
            DateTime.utc(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch;
        // UTC+5:30 = 330 minutes
        final result =
            CaptureTimezone.toLocalDateTime(timestamp, offsetMinutes: 330);

        // Should be 17:30 in that timezone
        expect(result.hour, equals(17));
        expect(result.minute, equals(30));
        expect(result.day, equals(15));
      });

      test('converts UTC timestamp with negative offset', () {
        // Jan 15, 2024 12:00:00 UTC
        final timestamp =
            DateTime.utc(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch;
        // UTC-5 = -300 minutes
        final result =
            CaptureTimezone.toLocalDateTime(timestamp, offsetMinutes: -300);

        // Should be 07:00 in that timezone
        expect(result.hour, equals(7));
        expect(result.minute, equals(0));
      });

      test('converts UTC timestamp with zero offset', () {
        // Jan 15, 2024 12:00:00 UTC
        final timestamp =
            DateTime.utc(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch;
        final result =
            CaptureTimezone.toLocalDateTime(timestamp, offsetMinutes: 0);

        // Should stay at 12:00
        expect(result.hour, equals(12));
        expect(result.minute, equals(0));
      });

      test('falls back to device local time when offset is null', () {
        final timestamp =
            DateTime.utc(2024, 1, 15, 12, 0, 0).millisecondsSinceEpoch;
        final result = CaptureTimezone.toLocalDateTime(timestamp);

        // Result should be local time - verify it matches toLocal() behavior
        final expected =
            DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
                .toLocal();
        expect(result.hour, equals(expected.hour));
        expect(result.minute, equals(expected.minute));
      });

      test('handles day rollover with positive offset', () {
        // Jan 15, 2024 22:00:00 UTC
        final timestamp =
            DateTime.utc(2024, 1, 15, 22, 0, 0).millisecondsSinceEpoch;
        // UTC+5 = 300 minutes, should roll over to next day
        final result =
            CaptureTimezone.toLocalDateTime(timestamp, offsetMinutes: 300);

        expect(result.day, equals(16));
        expect(result.hour, equals(3));
      });

      test('handles day rollover with negative offset', () {
        // Jan 15, 2024 02:00:00 UTC
        final timestamp =
            DateTime.utc(2024, 1, 15, 2, 0, 0).millisecondsSinceEpoch;
        // UTC-5 = -300 minutes, should roll back to previous day
        final result =
            CaptureTimezone.toLocalDateTime(timestamp, offsetMinutes: -300);

        expect(result.day, equals(14));
        expect(result.hour, equals(21));
      });
    });

    group('formatOffsetLabel', () {
      test('formats positive offset correctly', () {
        expect(CaptureTimezone.formatOffsetLabel(0), equals('UTC+00:00'));
        expect(CaptureTimezone.formatOffsetLabel(60), equals('UTC+01:00'));
        expect(CaptureTimezone.formatOffsetLabel(330), equals('UTC+05:30'));
        expect(CaptureTimezone.formatOffsetLabel(540), equals('UTC+09:00'));
        expect(CaptureTimezone.formatOffsetLabel(570), equals('UTC+09:30'));
        expect(CaptureTimezone.formatOffsetLabel(720), equals('UTC+12:00'));
      });

      test('formats negative offset correctly', () {
        expect(CaptureTimezone.formatOffsetLabel(-60), equals('UTC−01:00'));
        expect(CaptureTimezone.formatOffsetLabel(-300), equals('UTC−05:00'));
        expect(CaptureTimezone.formatOffsetLabel(-330), equals('UTC−05:30'));
        expect(CaptureTimezone.formatOffsetLabel(-480), equals('UTC−08:00'));
        expect(CaptureTimezone.formatOffsetLabel(-720), equals('UTC−12:00'));
      });

      test('uses proper minus sign (U+2212) for negative offsets', () {
        final result = CaptureTimezone.formatOffsetLabel(-60);
        // Should use '−' (U+2212) not '-' (U+002D)
        expect(result.contains('−'), isTrue);
        expect(result.contains('-'), isFalse);
      });

      test('pads hours and minutes to two digits', () {
        expect(CaptureTimezone.formatOffsetLabel(5), equals('UTC+00:05'));
        expect(CaptureTimezone.formatOffsetLabel(65), equals('UTC+01:05'));
        expect(CaptureTimezone.formatOffsetLabel(-5), equals('UTC−00:05'));
      });

      test('uses fallback DateTime offset when offsetMinutes is null', () {
        // Create a DateTime in a specific timezone to test fallback
        final fallback = DateTime(2024, 1, 15, 12, 0);
        final result =
            CaptureTimezone.formatOffsetLabel(null, fallbackDateTime: fallback);

        // Result should match the timezone offset of the fallback
        final expectedOffset = fallback.timeZoneOffset.inMinutes;
        final expectedSign = expectedOffset >= 0 ? '+' : '−';
        final expectedHours =
            (expectedOffset.abs() ~/ 60).toString().padLeft(2, '0');
        final expectedMinutes =
            (expectedOffset.abs() % 60).toString().padLeft(2, '0');
        expect(
            result, equals('UTC$expectedSign$expectedHours:$expectedMinutes'));
      });

      test('uses current device timezone when both params are null', () {
        final result = CaptureTimezone.formatOffsetLabel(null);

        // Should match current device timezone
        final now = DateTime.now();
        final expectedOffset = now.timeZoneOffset.inMinutes;
        final expectedSign = expectedOffset >= 0 ? '+' : '−';
        final expectedHours =
            (expectedOffset.abs() ~/ 60).toString().padLeft(2, '0');
        final expectedMinutes =
            (expectedOffset.abs() % 60).toString().padLeft(2, '0');
        expect(
            result, equals('UTC$expectedSign$expectedHours:$expectedMinutes'));
      });

      test('prefers offsetMinutes over fallbackDateTime', () {
        final fallback = DateTime(2024, 1, 15, 12, 0);
        // Pass an explicit offset that's different from device timezone
        final result =
            CaptureTimezone.formatOffsetLabel(0, fallbackDateTime: fallback);
        expect(result, equals('UTC+00:00'));
      });
    });
  });
}
