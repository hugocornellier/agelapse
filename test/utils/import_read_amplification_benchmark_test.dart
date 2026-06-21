// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// A/B measurement for Finding #7: the import pipeline reads each source file
/// ~4x (preview EXIF, import bytes, SHA-256 fingerprint, and the final copy).
///
/// This is a measurement harness, NOT the production pipeline. It HARD-PROVES
/// the read-once approaches are OUTPUT-IDENTICAL (same fingerprint + same
/// written bytes) and REPORTS per-platform timings. It deliberately does NOT
/// assert a universal speedup, because the winner is platform-dependent:
///
///   On Windows, the native `File.copy` (CopyFileEx, kernel-side) is faster
///   than a userspace `readAsBytes`+`writeAsBytes`. So "read once then write
///   from memory" (variant B) can be SLOWER on Windows, while "read once but
///   keep File.copy" (variant C) still wins by dropping the redundant reads.
///   CI measured B at ~0.84x on windows-latest — exactly this effect.
///
/// Variants:
///   A  baseline        — 3 reads + File.copy           (current pipeline)
///   B  read-once+write  — 1 read + writeAsBytes(memory)
///   C  read-once+copy   — 1 read + File.copy (kernel)   <- the real optimization

const int targetBytes = 16 * 1024 * 1024; // RAW/HEIC-like, for a stable signal
const int benchIterations = 20;

/// Median (robust to GC/scheduler spikes that would skew a sum/mean on a noisy
/// shared CI runner).
int medianUs(List<int> samples) {
  final sorted = [...samples]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : ((sorted[mid - 1] + sorted[mid]) ~/ 2);
}

String findRealSample() {
  const candidates = [
    'assets/test_fixtures/sample-heic.HEIC',
    'assets/images/stab_tut1.jpg',
    'assets/images/fireworks.png',
    'assets/images/logo.png',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  throw StateError(
    'No real sample image found (cwd=${Directory.current.path}); '
    'looked for: $candidates',
  );
}

/// Builds a working file from REAL photo bytes, repeated up to ~[targetBytes],
/// so the read-amplification signal is stable (mirrors a large RAW/HEIC import).
String buildWorkingSample(Directory tmp) {
  final seed = File(findRealSample()).readAsBytesSync();
  final builder = BytesBuilder(copy: false);
  while (builder.length < targetBytes) {
    builder.add(seed);
  }
  final path = '${tmp.path}${Platform.pathSeparator}sample.bin';
  File(path).writeAsBytesSync(builder.takeBytes());
  return path;
}

/// A — current pipeline: the source file is read four times.
/// Returns a `{size}:{sha256}` fingerprint (the format PhotoFingerprint uses).
Future<String> baselineFourRead(String src, String dst) async {
  final exifBytes = await File(src).readAsBytes(); // read 1: preview EXIF
  final importBytes = await File(src).readAsBytes(); // read 2: import bytes
  final digest =
      await sha256.bind(File(src).openRead()).first; // read 3: fingerprint
  await File(src).copy(dst); // read 4 + write (kernel copy)
  if (exifBytes.length != importBytes.length) {
    throw StateError('inconsistent reads of the same file');
  }
  return '${importBytes.length}:$digest';
}

/// B — read once, then write the in-memory bytes back out (userspace write).
Future<String> readOnceWrite(String src, String dst) async {
  final bytes = await File(src).readAsBytes();
  final digest = sha256.convert(bytes);
  await File(dst).writeAsBytes(bytes);
  return '${bytes.length}:$digest';
}

/// C — read once (reused for hash, and would feed EXIF/decode), but keep the
/// kernel-side File.copy for final placement. This is the real optimization.
Future<String> readOnceCopy(String src, String dst) async {
  final bytes = await File(src).readAsBytes();
  final digest = sha256.convert(bytes);
  await File(src).copy(dst);
  return '${bytes.length}:$digest';
}

Future<int> timeMedian(Future<String> Function() op) async {
  final samples = <int>[];
  for (var i = 0; i < benchIterations; i++) {
    final watch = Stopwatch()..start();
    await op();
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  return medianUs(samples);
}

void main() {
  late Directory tmp;
  late String sample;
  late Uint8List srcBytes;
  late String expectedFp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('agelapse_readamp_');
    sample = buildWorkingSample(tmp);
    srcBytes = File(sample).readAsBytesSync();
    expectedFp = '${srcBytes.length}:${sha256.convert(srcBytes)}';
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('every variant produces byte-identical output', () async {
    final variants = <String, Future<String> Function(String, String)>{
      'baseline': baselineFourRead,
      'read-once+write': readOnceWrite,
      'read-once+copy': readOnceCopy,
    };
    for (final entry in variants.entries) {
      final dst = '${tmp.path}${Platform.pathSeparator}${entry.key}.out';
      final fp = await entry.value(sample, dst);
      expect(fp, expectedFp, reason: '${entry.key} fingerprint diverged');
      expect(await File(dst).readAsBytes(), srcBytes,
          reason: '${entry.key} written bytes diverged');
    }
  });

  test('report read-amplification timings (per platform)', () async {
    final dstA = '${tmp.path}${Platform.pathSeparator}a.bin';
    final dstB = '${tmp.path}${Platform.pathSeparator}b.bin';
    final dstC = '${tmp.path}${Platform.pathSeparator}c.bin';

    // Warm the page cache so we measure read amplification, not first-touch I/O.
    await baselineFourRead(sample, dstA);
    await readOnceWrite(sample, dstB);
    await readOnceCopy(sample, dstC);

    final aMed = await timeMedian(() => baselineFourRead(sample, dstA));
    final bMed = await timeMedian(() => readOnceWrite(sample, dstB));
    final cMed = await timeMedian(() => readOnceCopy(sample, dstC));

    final sizeMb = (srcBytes.length / (1024 * 1024)).toStringAsFixed(0);
    String x(int med) => (aMed / med).toStringAsFixed(2);
    print('[read-amplification] ${sizeMb}MB, $benchIterations iters, median/op '
        '(warm cache; cold/NTFS gap differs)');
    print('  A baseline (3 reads + copy): '
        '${(aMed / 1000).toStringAsFixed(2)} ms/op  (1.00x)');
    print('  B read-once + write(memory): '
        '${(bMed / 1000).toStringAsFixed(2)} ms/op  (${x(bMed)}x)');
    print('  C read-once + File.copy:     '
        '${(cMed / 1000).toStringAsFixed(2)} ms/op  (${x(cMed)}x)');
    print('  Note: winner is platform-dependent — Windows CopyFile (kernel) '
        'beats userspace write, so prefer variant C.');

    // Output identity is the hard guarantee (asserted above). Timings are
    // reported, not gated, because the fastest variant differs per platform.
    expect(aMed, greaterThan(0));
    expect(bMed, greaterThan(0));
    expect(cMed, greaterThan(0));
  });
}
