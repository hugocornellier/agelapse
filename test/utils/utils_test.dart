import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/utils.dart';

void main() {
  group('Utils', () {
    group('parseBoolean', () {
      test('returns true for "true"', () {
        expect(Utils.parseBoolean('true'), isTrue);
      });

      test('returns true for "TRUE"', () {
        expect(Utils.parseBoolean('TRUE'), isTrue);
      });

      test('returns true for "True"', () {
        expect(Utils.parseBoolean('True'), isTrue);
      });

      test('returns false for "false"', () {
        expect(Utils.parseBoolean('false'), isFalse);
      });

      test('returns false for "FALSE"', () {
        expect(Utils.parseBoolean('FALSE'), isFalse);
      });

      test('returns false for "False"', () {
        expect(Utils.parseBoolean('False'), isFalse);
      });

      test('returns null for null input', () {
        expect(Utils.parseBoolean(null), isNull);
      });

      test('returns null for invalid string', () {
        expect(Utils.parseBoolean('yes'), isNull);
        expect(Utils.parseBoolean('no'), isNull);
        expect(Utils.parseBoolean('1'), isNull);
        expect(Utils.parseBoolean('0'), isNull);
        expect(Utils.parseBoolean(''), isNull);
      });
    });

    group('formatUnixTimestamp', () {
      // Use local DateTime to avoid timezone issues in tests
      test('formats date with st suffix for 1st', () {
        final timestamp = DateTime(2024, 1, 1, 12).millisecondsSinceEpoch;
        final result = Utils.formatUnixTimestamp(timestamp);
        expect(result, contains('1st'));
        expect(result, contains('Jan'));
        expect(result, contains('2024'));
      });

      test('formats date with nd suffix for 2nd', () {
        final timestamp = DateTime(2024, 1, 2, 12).millisecondsSinceEpoch;
        final result = Utils.formatUnixTimestamp(timestamp);
        expect(result, contains('2nd'));
      });

      test('formats date with rd suffix for 3rd', () {
        final timestamp = DateTime(2024, 1, 3, 12).millisecondsSinceEpoch;
        final result = Utils.formatUnixTimestamp(timestamp);
        expect(result, contains('3rd'));
      });

      test('formats date with th suffix for 4th', () {
        final timestamp = DateTime(2024, 1, 4, 12).millisecondsSinceEpoch;
        final result = Utils.formatUnixTimestamp(timestamp);
        expect(result, contains('4th'));
      });

      test('formats date with th suffix for 11th, 12th, 13th', () {
        final timestamp11 = DateTime(2024, 1, 11, 12).millisecondsSinceEpoch;
        final timestamp12 = DateTime(2024, 1, 12, 12).millisecondsSinceEpoch;
        final timestamp13 = DateTime(2024, 1, 13, 12).millisecondsSinceEpoch;

        expect(Utils.formatUnixTimestamp(timestamp11), contains('11th'));
        expect(Utils.formatUnixTimestamp(timestamp12), contains('12th'));
        expect(Utils.formatUnixTimestamp(timestamp13), contains('13th'));
      });

      test('formats date with st suffix for 21st, 31st', () {
        final timestamp21 = DateTime(2024, 1, 21, 12).millisecondsSinceEpoch;
        final timestamp31 = DateTime(2024, 1, 31, 12).millisecondsSinceEpoch;

        expect(Utils.formatUnixTimestamp(timestamp21), contains('21st'));
        expect(Utils.formatUnixTimestamp(timestamp31), contains('31st'));
      });

      test('formats date with nd suffix for 22nd', () {
        final timestamp = DateTime(2024, 1, 22, 12).millisecondsSinceEpoch;
        final result = Utils.formatUnixTimestamp(timestamp);
        expect(result, contains('22nd'));
      });

      test('formats date with rd suffix for 23rd', () {
        final timestamp = DateTime(2024, 1, 23, 12).millisecondsSinceEpoch;
        final result = Utils.formatUnixTimestamp(timestamp);
        expect(result, contains('23rd'));
      });

      test('includes month abbreviation', () {
        final timestamps = [
          DateTime(2024, 1, 15, 12).millisecondsSinceEpoch,
          DateTime(2024, 6, 15, 12).millisecondsSinceEpoch,
          DateTime(2024, 12, 15, 12).millisecondsSinceEpoch,
        ];

        expect(Utils.formatUnixTimestamp(timestamps[0]), contains('Jan'));
        expect(Utils.formatUnixTimestamp(timestamps[1]), contains('Jun'));
        expect(Utils.formatUnixTimestamp(timestamps[2]), contains('Dec'));
      });
    });

    group('capitalizeFirstLetter', () {
      test('capitalizes lowercase first letter', () {
        expect(Utils.capitalizeFirstLetter('hello'), 'Hello');
      });

      test('keeps uppercase first letter', () {
        expect(Utils.capitalizeFirstLetter('Hello'), 'Hello');
      });

      test('handles single character', () {
        expect(Utils.capitalizeFirstLetter('a'), 'A');
        expect(Utils.capitalizeFirstLetter('A'), 'A');
      });

      test('returns empty string for empty input', () {
        expect(Utils.capitalizeFirstLetter(''), '');
      });

      test('handles numbers and special characters', () {
        expect(Utils.capitalizeFirstLetter('123abc'), '123abc');
        expect(Utils.capitalizeFirstLetter('!hello'), '!hello');
      });

      test('only capitalizes first character', () {
        expect(Utils.capitalizeFirstLetter('hELLO'), 'HELLO');
        expect(Utils.capitalizeFirstLetter('hello world'), 'Hello world');
      });
    });

    group('isImage', () {
      test('returns true for common image extensions', () {
        expect(Utils.isImage('photo.jpg'), isTrue);
        expect(Utils.isImage('photo.jpeg'), isTrue);
        expect(Utils.isImage('photo.png'), isTrue);
        expect(Utils.isImage('photo.heic'), isTrue);
        expect(Utils.isImage('photo.heif'), isTrue);
        expect(Utils.isImage('photo.webp'), isTrue);
        expect(Utils.isImage('photo.avif'), isTrue);
        expect(Utils.isImage('photo.bmp'), isTrue);
        expect(Utils.isImage('photo.tiff'), isTrue);
      });

      test('returns true for uppercase extensions', () {
        expect(Utils.isImage('photo.JPG'), isTrue);
        expect(Utils.isImage('photo.JPEG'), isTrue);
        expect(Utils.isImage('photo.PNG'), isTrue);
        expect(Utils.isImage('photo.HEIC'), isTrue);
      });

      test('returns true for mixed case extensions', () {
        expect(Utils.isImage('photo.JpG'), isTrue);
        expect(Utils.isImage('photo.Png'), isTrue);
      });

      test('returns false for PDF files', () {
        expect(Utils.isImage('document.pdf'), isFalse);
        expect(Utils.isImage('document.PDF'), isFalse);
      });

      test('returns false for non-image files', () {
        expect(Utils.isImage('document.txt'), isFalse);
        expect(Utils.isImage('video.mp4'), isFalse);
        expect(Utils.isImage('music.mp3'), isFalse);
        expect(Utils.isImage('archive.zip'), isFalse);
      });

      test('handles paths with directories', () {
        expect(Utils.isImage('/path/to/photo.jpg'), isTrue);
        expect(Utils.isImage('C:\\Users\\photo.png'), isTrue);
        expect(Utils.isImage('/path/to/document.pdf'), isFalse);
      });

      test('handles jfif, pjpeg, pjp extensions', () {
        expect(Utils.isImage('photo.jfif'), isTrue);
        expect(Utils.isImage('photo.pjpeg'), isTrue);
        expect(Utils.isImage('photo.pjp'), isTrue);
      });

      test('handles apng extension', () {
        expect(Utils.isImage('animation.apng'), isTrue);
      });
    });
  });
}
