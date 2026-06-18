import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/isolate_pool.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

import 'test_utils.dart';

/// Op-level micro-benchmarks for the Tier-A plumbing optimizations.
///
/// The end-to-end benchmark is detection-bound, so the decode/encode/cache
/// savings these changes target are below its noise floor. These micro-benches
/// measure each operation in isolation to decide, on evidence, whether a
/// byte-identical plumbing change is worth banking.
///
///   flutter test integration_test/stabilization_microbench_test.dart -d macos
double _medianMs(List<int> micros) {
  micros.sort();
  return micros[micros.length ~/ 2] / 1000.0;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Tier-A micro-benchmarks', () {
    Uint8List? srcBytes;

    setUpAll(() async {
      await IsolatePool.instance.initialize();
    });

    tearDownAll(() async {
      await IsolatePool.instance.dispose();
      await cleanupFixtures();
    });

    testWidgets('load fixture', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await preloadFixtures();
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available');
        return;
      }
      final path = await getSampleFacePathAsync(1);
      if (!await File(path).exists()) {
        markTestSkipped('Face fixture day1.jpg not found');
        return;
      }
      srcBytes = await File(path).readAsBytes();
    });

    testWidgets('A.1 — source decode cost', (tester) async {
      final bytes = srcBytes;
      if (bytes == null) {
        markTestSkipped('Fixture not loaded');
        return;
      }
      const warm = 5, n = 60;
      for (int i = 0; i < warm; i++) {
        cv.imdecode(bytes, cv.IMREAD_COLOR).dispose();
      }
      final times = <int>[];
      for (int i = 0; i < n; i++) {
        final sw = Stopwatch()..start();
        final m = cv.imdecode(bytes, cv.IMREAD_COLOR);
        sw.stop();
        times.add(sw.elapsedMicroseconds);
        m.dispose();
      }
      debugPrint('A.1  source decode (IMREAD_COLOR): '
          'median ${_medianMs(times).toStringAsFixed(2)} ms/call (n=$n) '
          '— removed once per photo by folding dims into the warp decode');
    });

    testWidgets('A.4 — Mat reconstruct: fromList vs create+setAll',
        (tester) async {
      final bytes = srcBytes;
      if (bytes == null) {
        markTestSkipped('Fixture not loaded');
        return;
      }
      // Representative full frame: decode the fixture and reuse its raw bytes,
      // dims, and type (encodeRawToPng reconstructs a frame of this kind).
      final base = cv.imdecode(bytes, cv.IMREAD_COLOR);
      final int h = base.rows, w = base.cols, tv = base.type.value;
      final Uint8List frame = Uint8List.fromList(base.data);
      base.dispose();
      debugPrint('A.4  frame: ${w}x$h type=$tv bytes=${frame.length}');

      // Op-level parity: the faster path must reproduce identical bytes.
      final a = cv.Mat.fromList(h, w, cv.MatType(tv), frame);
      final fast = cv.Mat.create(rows: h, cols: w, type: cv.MatType(tv));
      fast.data.setAll(0, frame);
      final identical = _bytesEqual(a.data, fast.data);
      a.dispose();
      fast.dispose();
      expect(identical, isTrue,
          reason: 'create+setAll must reproduce Mat.fromList bytes exactly');

      const warm = 5, n = 80;
      for (int i = 0; i < warm; i++) {
        cv.Mat.fromList(h, w, cv.MatType(tv), frame).dispose();
        (cv.Mat.create(rows: h, cols: w, type: cv.MatType(tv))
              ..data.setAll(0, frame))
            .dispose();
      }
      final tFromList = <int>[];
      for (int i = 0; i < n; i++) {
        final sw = Stopwatch()..start();
        final m = cv.Mat.fromList(h, w, cv.MatType(tv), frame);
        sw.stop();
        tFromList.add(sw.elapsedMicroseconds);
        m.dispose();
      }
      final tCreate = <int>[];
      for (int i = 0; i < n; i++) {
        final sw = Stopwatch()..start();
        final m = cv.Mat.create(rows: h, cols: w, type: cv.MatType(tv));
        m.data.setAll(0, frame);
        sw.stop();
        tCreate.add(sw.elapsedMicroseconds);
        m.dispose();
      }
      debugPrint('A.4  Mat.fromList:   '
          'median ${_medianMs(tFromList).toStringAsFixed(2)} ms/call (n=$n)');
      debugPrint('A.4  create+setAll:  '
          'median ${_medianMs(tCreate).toStringAsFixed(2)} ms/call (n=$n) '
          '— op-parity verified; runs once per saved photo');
    });

    testWidgets('A.3 — clearMatCache broadcast cost', (tester) async {
      const warm = 3, n = 40;
      for (int i = 0; i < warm; i++) {
        await IsolatePool.instance.clearMatCache();
      }
      final times = <int>[];
      for (int i = 0; i < n; i++) {
        final sw = Stopwatch()..start();
        await IsolatePool.instance.clearMatCache();
        sw.stop();
        times.add(sw.elapsedMicroseconds);
      }
      debugPrint('A.3  clearMatCache (broadcast ${IsolatePool.workerCount} '
          'workers): median ${_medianMs(times).toStringAsFixed(2)} ms/call '
          '(n=$n) — called once per photo');
    });

    testWidgets('#3 — redundant decode cost vs image size', (tester) async {
      final bytes = srcBytes;
      if (bytes == null) {
        markTestSkipped('Fixture not loaded');
        return;
      }

      double benchDecode(Uint8List jpeg) {
        const warm = 3, n = 30;
        for (int i = 0; i < warm; i++) {
          cv.imdecode(jpeg, cv.IMREAD_COLOR).dispose();
        }
        final t = <int>[];
        for (int i = 0; i < n; i++) {
          final sw = Stopwatch()..start();
          final m = cv.imdecode(jpeg, cv.IMREAD_COLOR);
          sw.stop();
          t.add(sw.elapsedMicroseconds);
          m.dispose();
        }
        return _medianMs(t);
      }

      // Fixture-size decode.
      final base = cv.imdecode(bytes, cv.IMREAD_COLOR);
      final smallMs = benchDecode(bytes);

      // Upscale to representative large-camera sizes and re-encode to JPEG,
      // so we measure decode cost across the range that matters on old
      // hardware / big photos (the regime the 640x480 fixtures hide).
      final sizes = <(int, int)>[(2000, 1500), (4000, 3000), (5500, 4125)];
      final results = <String>[];
      for (final (w, h) in sizes) {
        final big = cv.resize(base, (w, h), interpolation: cv.INTER_CUBIC);
        final (ok, bigJpeg) = cv.imencode('.jpg', big);
        big.dispose();
        if (!ok) continue;
        final mp = (w * h / 1000000).toStringAsFixed(1);
        results.add('${mp}MP ${benchDecode(bigJpeg).toStringAsFixed(2)} ms');
      }
      base.dispose();

      debugPrint('#3  redundant decode cost (saved once per single-face photo '
          'if detect+embed share one decode in the plugin):');
      debugPrint('#3  fixture(${smallMs.toStringAsFixed(2)} ms)  |  '
          '${results.join('  |  ')}');
    });
  });
}
