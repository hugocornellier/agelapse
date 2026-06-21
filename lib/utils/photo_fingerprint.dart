import 'dart:io';

import 'package:crypto/crypto.dart';

/// Computes a content-based fingerprint for a raw photo file.
///
/// Separated from `StabUtils` so the import path (`camera_utils.dart`) can
/// depend on it without pulling in the OpenCV / face-detection graph that
/// `stabilizer_utils.dart` would drag along.
class PhotoFingerprint {
  PhotoFingerprint._();

  /// Returns a fingerprint as `{size}:{sha256hex}`.
  ///
  /// Hashes the full file contents so a fingerprint match can be treated as
  /// strong duplicate evidence during import.
  /// Deliberately content-only: mtime is excluded so fingerprints survive
  /// legitimate file operations (cloud-backup restores, rsync, adb pull,
  /// file copies) that change mtime without changing bytes.
  /// Throws if the file does not exist.
  static Future<String> compute(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('File does not exist: $filePath');
    }
    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    return '$size:$digest';
  }

  /// Same fingerprint as [compute], but from already-in-memory [bytes].
  ///
  /// Lets the import path reuse the source bytes it already read (for decoding)
  /// instead of reading the file a second time just to hash it. Byte-identical
  /// to [compute] for the same content: `file.length()` equals `bytes.length`
  /// for a full read, and SHA-256 of the bytes equals the streamed digest.
  static String fromBytes(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return '${bytes.length}:$digest';
  }
}
