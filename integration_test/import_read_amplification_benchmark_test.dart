// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// On-device version of test/utils/import_read_amplification_benchmark_test.dart
/// for Finding #7 (the import pipeline reads each source file ~4x).
///
/// Identical A/B/C patterns, but the working file lives in the device's temp
/// directory and uses synthetic bytes (content is irrelevant to read
/// amplification). That lets it run on iOS/Android — and desktop — via:
///   flutter test integration_test/import_read_amplification_benchmark_test.dart -d `DEVICE`
///
/// HARD-proves output identity (same fingerprint + same written bytes) and
/// REPORTS per-platform timings. It does NOT assert a universal speedup: the
/// winner is platform-dependent (e.g. Windows File.copy/CopyFileEx beats a
/// userspace write, so variant B regresses there while variant C still wins).
///
///   A  baseline       — 3 reads + File.copy           (current pipeline)
///   B  read-once+write — 1 read + writeAsBytes(memory)
///   C  read-once+copy  — 1 read + File.copy (kernel)   <- the real optimization

const int targetBytes = 16 * 1024 * 1024;
const int benchIterations = 12;

int medianUs(List<int> samples) {
  final sorted = [...samples]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : ((sorted[mid - 1] + sorted[mid]) ~/ 2);
}

Uint8List buildSyntheticBytes() {
  final seed = Uint8List(64 * 1024);
  for (var i = 0; i < seed.length; i++) {
    seed[i] = i & 0xFF;
  }
  final builder = BytesBuilder(copy: false);
  while (builder.length < targetBytes) {
    builder.add(seed);
  }
  return builder.takeBytes();
}

Future<String> baselineFourRead(String src, String dst) async {
  final exifBytes = await File(src).readAsBytes(); // read 1
  final importBytes = await File(src).readAsBytes(); // read 2
  final digest = await sha256.bind(File(src).openRead()).first; // read 3
  await File(src).copy(dst); // read 4 + write
  if (exifBytes.length != importBytes.length) {
    throw StateError('inconsistent reads of the same file');
  }
  return '${importBytes.length}:$digest';
}

Future<String> readOnceWrite(String src, String dst) async {
  final bytes = await File(src).readAsBytes();
  final digest = sha256.convert(bytes);
  await File(dst).writeAsBytes(bytes);
  return '${bytes.length}:$digest';
}

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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String sample;
  late Uint8List srcBytes;
  late String expectedFp;

  setUp(() async {
    final tmpRoot = await getTemporaryDirectory();
    dir = Directory(
      '${tmpRoot.path}${Platform.pathSeparator}'
      'readamp_${DateTime.now().microsecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    sample = '${dir.path}${Platform.pathSeparator}sample.bin';
    srcBytes = buildSyntheticBytes();
    await File(sample).writeAsBytes(srcBytes);
    expectedFp = '${srcBytes.length}:${sha256.convert(srcBytes)}';
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('every variant produces byte-identical output', () async {
    final variants = <String, Future<String> Function(String, String)>{
      'baseline': baselineFourRead,
      'read-once+write': readOnceWrite,
      'read-once+copy': readOnceCopy,
    };
    for (final entry in variants.entries) {
      final dst = '${dir.path}${Platform.pathSeparator}${entry.key}.out';
      final fp = await entry.value(sample, dst);
      expect(fp, expectedFp, reason: '${entry.key} fingerprint diverged');
      expect(await File(dst).readAsBytes(), srcBytes,
          reason: '${entry.key} written bytes diverged');
    }
  });

  test('report read-amplification timings (per platform)', () async {
    final dstA = '${dir.path}${Platform.pathSeparator}a.bin';
    final dstB = '${dir.path}${Platform.pathSeparator}b.bin';
    final dstC = '${dir.path}${Platform.pathSeparator}c.bin';

    // Warm any cache so we measure read amplification, not first-touch I/O.
    await baselineFourRead(sample, dstA);
    await readOnceWrite(sample, dstB);
    await readOnceCopy(sample, dstC);

    final aMed = await timeMedian(() => baselineFourRead(sample, dstA));
    final bMed = await timeMedian(() => readOnceWrite(sample, dstB));
    final cMed = await timeMedian(() => readOnceCopy(sample, dstC));

    final sizeMb = (srcBytes.length / (1024 * 1024)).toStringAsFixed(0);
    String x(int med) => (aMed / med).toStringAsFixed(2);
    print('[read-amplification] platform=${Platform.operatingSystem} '
        '${sizeMb}MB, $benchIterations iters, median/op');
    print('  A baseline (3 reads + copy): '
        '${(aMed / 1000).toStringAsFixed(2)} ms/op  (1.00x)');
    print('  B read-once + write(memory): '
        '${(bMed / 1000).toStringAsFixed(2)} ms/op  (${x(bMed)}x)');
    print('  C read-once + File.copy:     '
        '${(cMed / 1000).toStringAsFixed(2)} ms/op  (${x(cMed)}x)');

    expect(aMed, greaterThan(0));
    expect(bMed, greaterThan(0));
    expect(cMed, greaterThan(0));
  });
}
