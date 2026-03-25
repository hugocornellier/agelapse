import 'package:agelapse/utils/image_format_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageFormats', () {
    test('accepts standard, HEIC/AVIF, and RAW extensions', () {
      expect(ImageFormats.isAcceptedPath('photo.jpg'), isTrue);
      expect(ImageFormats.isAcceptedPath('photo.heic'), isTrue);
      expect(ImageFormats.isAcceptedPath('photo.avif'), isTrue);
      expect(ImageFormats.isAcceptedPath('photo.dng'), isTrue);
      expect(ImageFormats.isAcceptedPath('photo.cr2'), isTrue);
      expect(ImageFormats.isAcceptedPath('photo.nef'), isTrue);
    });

    test('is case-insensitive', () {
      expect(ImageFormats.isAcceptedPath('photo.CR3'), isTrue);
      expect(ImageFormats.isAcceptedPath('photo.HeIf'), isTrue);
    });

    test('rejects non-image files', () {
      expect(ImageFormats.isAcceptedPath('photo.zip'), isFalse);
      expect(ImageFormats.isAcceptedPath('document.pdf'), isFalse);
    });
  });
}
