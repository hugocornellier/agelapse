@TestOn('windows')
library;

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:agelapse/utils/windows_file_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// The OLD implementation this change replaces: a per-photo `powershell.exe`
/// spawn that copied the NTFS creation time from [src] to [dst]. Kept here
/// verbatim as the "before" reference so CI can prove, on a real Windows
/// runner, that the new FFI path is byte-for-byte identical and faster.
Future<void> preserveCreationTimePowerShell(String src, String dst) async {
  final escaped = dst.replaceAll("'", "''");
  final srcEscaped = src.replaceAll("'", "''");
  await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "(Get-Item '$escaped').CreationTime = "
        "(Get-Item '$srcEscaped').CreationTime",
  ]);
}

/// A fixed, known FILETIME (~2021-06-15) with a non-zero sub-second (100ns)
/// remainder used to stamp the source. The odd low-order ticks prove full
/// FILETIME fidelity — a copy that truncated to seconds/ms would change them.
const int knownFileTime = 132682320001234567;

/// A distinct FILETIME used to stamp targets before the copy, so the
/// precondition (target differs from source) holds regardless of how the OS
/// copies file metadata.
const int otherFileTime = 130000000007654321;

/// Locates a real bundled sample image, read from the filesystem relative to
/// the project root (the cwd when running via `flutter test`).
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
  late Directory tmp;
  late String samplePath;
  late String sampleExt;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('agelapse_ctime_');
    final realSample = findRealSample();
    sampleExt = realSample.substring(realSample.lastIndexOf('.'));
    samplePath = '${tmp.path}${Platform.pathSeparator}source$sampleExt';
    File(realSample).copySync(samplePath);

    // Stamp a known creation time so the copy result is deterministic.
    final ok = setWindowsCreationTimeRaw(samplePath, knownFileTime);
    expect(ok, isTrue, reason: 'failed to stamp known ctime on source');
    expect(readWindowsCreationTimeRaw(samplePath), knownFileTime,
        reason: 'source ctime did not round-trip (FAT volume?)');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String freshTarget(String label) {
    final dst = '${tmp.path}${Platform.pathSeparator}target_$label$sampleExt';
    File(samplePath).copySync(dst);
    // Force a distinct starting ctime so a successful copy is observable.
    setWindowsCreationTimeRaw(dst, otherFileTime);
    return dst;
  }

  test('FFI copy yields a byte-for-byte identical creation time to PowerShell',
      () async {
    final targetPs = freshTarget('ps');
    final targetFfi = freshTarget('ffi');

    // Precondition: targets start with a different ctime than the source.
    expect(readWindowsCreationTimeRaw(targetPs), otherFileTime);
    expect(readWindowsCreationTimeRaw(targetFfi), otherFileTime);

    await preserveCreationTimePowerShell(samplePath, targetPs);
    copyWindowsCreationTime(samplePath, targetFfi);

    final afterPs = readWindowsCreationTimeRaw(targetPs);
    final afterFfi = readWindowsCreationTimeRaw(targetFfi);

    // Both must equal the source exactly...
    expect(afterPs, knownFileTime, reason: 'PowerShell did not copy ctime');
    expect(afterFfi, knownFileTime, reason: 'FFI did not copy ctime');
    // ...and therefore be byte-for-byte identical to each other.
    expect(afterFfi, afterPs,
        reason: 'FFI and PowerShell produced different creation times');
  });

  test('FFI copy is faster than spawning PowerShell', () async {
    const iterations = 20;
    final targetPs = freshTarget('ps_bench');
    final targetFfi = freshTarget('ffi_bench');

    // Warm up both paths (the first PowerShell spawn pays extra startup cost).
    await preserveCreationTimePowerShell(samplePath, targetPs);
    copyWindowsCreationTime(samplePath, targetFfi);

    final psWatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await preserveCreationTimePowerShell(samplePath, targetPs);
    }
    psWatch.stop();

    final ffiWatch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      copyWindowsCreationTime(samplePath, targetFfi);
    }
    ffiWatch.stop();

    final psUs = psWatch.elapsedMicroseconds;
    final ffiUs = ffiWatch.elapsedMicroseconds;
    final psPerMs = psUs / iterations / 1000.0;
    final ffiPerMs = ffiUs / iterations / 1000.0;
    final speedup = ffiUs == 0 ? double.infinity : psUs / ffiUs;

    print('[creation-time benchmark] $iterations iterations on a real sample');
    print('  PowerShell: ${psPerMs.toStringAsFixed(2)} ms/op '
        '(${(psUs / 1000).toStringAsFixed(1)} ms total)');
    print('  FFI:        ${ffiPerMs.toStringAsFixed(3)} ms/op '
        '(${(ffiUs / 1000).toStringAsFixed(2)} ms total)');
    print('  Speedup:    ${speedup.toStringAsFixed(0)}x faster');

    // Correctness must still hold after the benchmark loop.
    expect(readWindowsCreationTimeRaw(targetPs), knownFileTime);
    expect(readWindowsCreationTimeRaw(targetFfi), knownFileTime);

    // FFI is microseconds vs PowerShell's hundreds of ms per spawn, so a 5x
    // floor sits far below the real gap yet stays robust to shared-runner noise.
    expect(psUs, greaterThan(ffiUs * 5),
        reason: 'FFI ($ffiUs us) should be >=5x faster than '
            'PowerShell ($psUs us)');
  });
}
