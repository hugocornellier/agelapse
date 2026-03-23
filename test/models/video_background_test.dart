import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/video_background.dart';

void main() {
  group('VideoBackground', () {
    group('transparent constructor', () {
      test('creates transparent background', () {
        const bg = VideoBackground.transparent();
        expect(bg.keepTransparent, true);
        expect(bg.solidColorHex, isNull);
      });

      test('requires alpha codec', () {
        const bg = VideoBackground.transparent();
        expect(bg.requiresAlphaCodec, true);
      });
    });

    group('solidColor constructor', () {
      test('creates solid color background', () {
        final bg = VideoBackground.solidColor('#FF0000');
        expect(bg.keepTransparent, false);
        expect(bg.solidColorHex, '#FF0000');
      });

      test('uppercases hex color', () {
        final bg = VideoBackground.solidColor('#ff0000');
        expect(bg.solidColorHex, '#FF0000');
      });

      test('does not require alpha codec', () {
        final bg = VideoBackground.solidColor('#000000');
        expect(bg.requiresAlphaCodec, false);
      });
    });

    group('fromString', () {
      test('parses TRANSPARENT value', () {
        final bg = VideoBackground.fromString('TRANSPARENT');
        expect(bg.keepTransparent, true);
        expect(bg.solidColorHex, isNull);
      });

      test('parses transparent value case-insensitively', () {
        final bg = VideoBackground.fromString('transparent');
        expect(bg.keepTransparent, true);
      });

      test('parses hex color value', () {
        final bg = VideoBackground.fromString('#FF0000');
        expect(bg.keepTransparent, false);
        expect(bg.solidColorHex, '#FF0000');
      });

      test('parses lowercase hex color', () {
        final bg = VideoBackground.fromString('#ff0000');
        expect(bg.keepTransparent, false);
        expect(bg.solidColorHex, '#FF0000');
      });

      test('parses black hex', () {
        final bg = VideoBackground.fromString('#000000');
        expect(bg.keepTransparent, false);
        expect(bg.solidColorHex, '#000000');
      });

      test('parses BLURRED value', () {
        final bg = VideoBackground.fromString('BLURRED');
        expect(bg.keepTransparent, false);
        expect(bg.solidColorHex, isNull);
        expect(bg.isBlurred, true);
      });

      test('parses blurred value case-insensitively', () {
        final bg = VideoBackground.fromString('blurred');
        expect(bg.isBlurred, true);
      });
    });

    group('toDbValue', () {
      test('transparent returns TRANSPARENT', () {
        const bg = VideoBackground.transparent();
        expect(bg.toDbValue(), 'TRANSPARENT');
      });

      test('solid color returns hex string', () {
        final bg = VideoBackground.solidColor('#FF0000');
        expect(bg.toDbValue(), '#FF0000');
      });

      test('blurred returns BLURRED', () {
        const bg = VideoBackground.blurred();
        expect(bg.toDbValue(), 'BLURRED');
      });

      test('round-trips through fromString', () {
        const transparent = VideoBackground.transparent();
        final roundTripped = VideoBackground.fromString(
          transparent.toDbValue(),
        );
        expect(roundTripped.keepTransparent, true);

        final solid = VideoBackground.solidColor('#ABCDEF');
        final roundTripped2 = VideoBackground.fromString(solid.toDbValue());
        expect(roundTripped2.keepTransparent, false);
        expect(roundTripped2.solidColorHex, '#ABCDEF');

        const blurred = VideoBackground.blurred();
        final roundTripped3 = VideoBackground.fromString(blurred.toDbValue());
        expect(roundTripped3.isBlurred, true);
        expect(roundTripped3.keepTransparent, false);
        expect(roundTripped3.solidColorHex, isNull);
      });
    });

    group('requiresAlphaCodec', () {
      test('transparent requires alpha codec', () {
        const bg = VideoBackground.transparent();
        expect(bg.requiresAlphaCodec, true);
      });

      test('solid color does not require alpha codec', () {
        final bg = VideoBackground.solidColor('#000000');
        expect(bg.requiresAlphaCodec, false);
      });
    });

    group('keepTransparentValue constant', () {
      test('is TRANSPARENT', () {
        expect(VideoBackground.keepTransparentValue, 'TRANSPARENT');
      });
    });

    group('blurred constructor', () {
      test('creates blurred background', () {
        const bg = VideoBackground.blurred();
        expect(bg.keepTransparent, false);
        expect(bg.solidColorHex, isNull);
        expect(bg.isBlurred, true);
        expect(bg.isSolidColor, false);
      });

      test('does not require alpha codec', () {
        const bg = VideoBackground.blurred();
        expect(bg.requiresAlphaCodec, false);
      });
    });

    group('isBlurred getter', () {
      test('returns true for blurred', () {
        const bg = VideoBackground.blurred();
        expect(bg.isBlurred, true);
      });

      test('returns false for transparent', () {
        const bg = VideoBackground.transparent();
        expect(bg.isBlurred, false);
      });

      test('returns false for solidColor', () {
        final bg = VideoBackground.solidColor('#000000');
        expect(bg.isBlurred, false);
      });
    });

    group('isSolidColor getter', () {
      test('returns true for solidColor', () {
        final bg = VideoBackground.solidColor('#000000');
        expect(bg.isSolidColor, true);
      });

      test('returns false for transparent', () {
        const bg = VideoBackground.transparent();
        expect(bg.isSolidColor, false);
      });

      test('returns false for blurred', () {
        const bg = VideoBackground.blurred();
        expect(bg.isSolidColor, false);
      });
    });
  });
}
