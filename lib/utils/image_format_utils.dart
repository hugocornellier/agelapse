import 'package:path/path.dart' as path;

class ImageFormats {
  static const Set<String> acceptedExtensions = {
    '.jpg',
    '.jpeg',
    '.jfif',
    '.pjpeg',
    '.pjp',
    '.png',
    '.apng',
    '.webp',
    '.bmp',
    '.tif',
    '.tiff',
    '.heic',
    '.heif',
    '.avif',
    '.gif',
    '.dng',
    '.cr2',
    '.cr3',
    '.nef',
    '.arw',
    '.raf',
    '.orf',
    '.rw2',
    '.jp2',
  };

  static bool isAcceptedPath(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    return acceptedExtensions.contains(extension);
  }
}
