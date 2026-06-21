import 'dart:io';

import 'package:agelapse/utils/photo_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the Finding #7 (variant C) optimization: the import path now computes
/// the dedup fingerprint from the bytes it already read, via
/// [PhotoFingerprint.fromBytes], instead of a second file read via
/// [PhotoFingerprint.compute]. These must stay byte-identical or dedup breaks.

String findRealSample() {
  const candidates = [
    'assets/test_fixtures/sample-heic.HEIC',
    'assets/images/stab_tut1.jpg',
    'assets/images/logo.png',
    'assets/images/fireworks.png',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  throw StateError(
    'No real sample image found (cwd=${Directory.current.path}); '
    'looked for: $candidates',
  );
}

void main() {
  test('fromBytes matches compute byte-for-byte for a real file', () async {
    final path = findRealSample();
    final bytes = await File(path).readAsBytes();

    final viaFile = await PhotoFingerprint.compute(path);
    final viaBytes = PhotoFingerprint.fromBytes(bytes);

    expect(viaBytes, viaFile,
        reason: 'fromBytes must equal compute or import dedup diverges');
    expect(viaBytes, startsWith('${bytes.length}:')); // {size}:{sha256hex}
  });

  test('fromBytes is deterministic and content-sensitive', () {
    final a = PhotoFingerprint.fromBytes([1, 2, 3, 4]);
    final b = PhotoFingerprint.fromBytes([1, 2, 3, 4]);
    final c = PhotoFingerprint.fromBytes([1, 2, 3, 5]);

    expect(a, b);
    expect(a, isNot(c));
    expect(a, startsWith('4:'));
  });

  test('fromBytes handles empty input', () {
    expect(PhotoFingerprint.fromBytes(const []), startsWith('0:'));
  });
}
