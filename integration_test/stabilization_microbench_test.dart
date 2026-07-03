import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/isolate_pool.dart';
import 'package:agelapse/utils/photo_fingerprint.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:path/path.dart' as p;

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

  group('Tier-B micro-benchmarks', () {
    setUpAll(() async {
      await IsolatePool.instance.initialize();
    });

    tearDownAll(() async {
      await IsolatePool.instance.dispose();
      await cleanupFixtures();
    });

    testWidgets('B.1 — isolate payload send: plain vs transferable',
        (tester) async {
      // The pool sends big per-photo payloads (canvas raw for encodeRawToPng,
      // source JPEG for prepareSourceMat) as plain Uint8List map values. This
      // measures whether wrapping them in TransferableTypedData is actually
      // faster, or whether the VM's serializer copy is already a plain memcpy
      // and the swap would be a wash.
      final echoReady = ReceivePort();
      final echo = await Isolate.spawn(_echoEntry, echoReady.sendPort);
      final echoPort = await echoReady.first as SendPort;
      echoReady.close();

      Future<double> bench(int sizeBytes, bool transferable, int n) async {
        final buf = Uint8List(sizeBytes);
        for (int i = 0; i < buf.length; i += 4096) {
          buf[i] = i & 0xff; // touch pages so the copy cost is real
        }
        final reply = ReceivePort();
        final replies = StreamIterator(reply);
        final times = <int>[];
        for (int i = 0; i < n + 3; i++) {
          final sw = Stopwatch()..start();
          echoPort.send({
            'bytes': transferable ? TransferableTypedData.fromList([buf]) : buf,
            'reply': reply.sendPort,
          });
          await replies.moveNext();
          sw.stop();
          if (i >= 3) times.add(sw.elapsedMicroseconds); // 3 warm-up sends
        }
        await replies.cancel();
        return _medianMs(times);
      }

      // Canvas raw frame (1080x1350 BGR) and 12 MP raw BGR.
      for (final (label, size) in [
        ('4.4MB canvas raw', 1080 * 1350 * 3),
        ('36MB 12MP raw', 4000 * 3000 * 3),
      ]) {
        final plain = await bench(size, false, 25);
        final transf = await bench(size, true, 25);
        debugPrint('B.1  $label: plain ${plain.toStringAsFixed(2)} ms  |  '
            'transferable ${transf.toStringAsFixed(2)} ms  (one-way + tiny reply)');
      }
      echo.kill(priority: Isolate.immediate);
    });

    testWidgets('B.2 — photo-save DB writes: separate vs coalesced',
        (tester) async {
      // saveStabilizedImage issues two UPDATEs on the same Photos row
      // (setPhotoStabilized, then setPhotoFaceData). Without WAL each UPDATE
      // is its own transaction+fsync; this measures what coalescing into one
      // UPDATE would save per photo.
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final now = DateTime.now().millisecondsSinceEpoch;
      final projectId =
          await DB.instance.addProject('microbench-db', 'face', now);
      const ts = '2000000000';
      await DB.instance
          .addPhoto(ts, projectId, '.jpg', 1000, '$ts.jpg', 'portrait');
      final embedding = Uint8List(768);
      for (int i = 0; i < embedding.length; i++) {
        embedding[i] = i & 0xff;
      }

      final stabilizedColumn = DB.instance.getStabilizedColumn('portrait');
      final db = await DB.instance.database;

      Future<double> bench(bool coalesced, int n) async {
        final times = <int>[];
        for (int i = 0; i < n + 5; i++) {
          final sw = Stopwatch()..start();
          if (coalesced) {
            await db.update(
              DB.photoTable,
              {
                stabilizedColumn: 1,
                '${stabilizedColumn}AspectRatio': '16:9',
                '${stabilizedColumn}Resolution': '1080p',
                '${stabilizedColumn}OffsetX': '0.5',
                '${stabilizedColumn}OffsetY': '0.5',
                'stabFailed': 0,
                'noFacesFound': 0,
                'stabAttempts': 0,
                'stabLastError': null,
                '${stabilizedColumn}TranslateX': 1.0,
                '${stabilizedColumn}TranslateY': 2.0,
                '${stabilizedColumn}RotationDegrees': 0.5,
                '${stabilizedColumn}ScaleFactor': 0.25,
                'faceCount': 1,
                'faceEmbedding': embedding,
              },
              where: 'timestamp = ? AND projectID = ?',
              whereArgs: [ts, projectId],
            );
          } else {
            await DB.instance.setPhotoStabilized(
              ts,
              projectId,
              'portrait',
              '16:9',
              '1080p',
              0.5,
              0.5,
              translateX: 1.0,
              translateY: 2.0,
              rotationDegrees: 0.5,
              scaleFactor: 0.25,
            );
            await DB.instance.setPhotoFaceData(
              ts,
              projectId,
              1,
              embedding: embedding,
            );
          }
          sw.stop();
          if (i >= 5) times.add(sw.elapsedMicroseconds);
        }
        return _medianMs(times);
      }

      final separate = await bench(false, 40);
      final coalesced = await bench(true, 40);
      debugPrint('B.2  photo-save DB writes: separate '
          '${separate.toStringAsFixed(2)} ms  |  coalesced '
          '${coalesced.toStringAsFixed(2)} ms  (per photo)');

      await DB.instance.deleteProjectCascade(projectId);
    });

    testWidgets('B.3 — per-photo fingerprint cost (benchmark harness skew)',
        (tester) async {
      // When stabilize() is called without knownFingerprint (as the benchmark
      // does), the cache path streams the whole source file through pure-Dart
      // SHA-256 per photo. The real batch path passes the import-time
      // fingerprint from the photo row, so users never pay this at stab time.
      // This sizes what the benchmark numbers include that the app path skips.
      await preloadFixtures();
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available');
        return;
      }
      final srcPath = await getSampleFacePathAsync(1);
      final small = await File(srcPath).readAsBytes();

      // Re-create the 12 MP fixture exactly like the PERF_LARGE benchmark.
      final mat = cv.imdecode(small, cv.IMREAD_COLOR);
      final big = cv.resize(mat, (4000, 3000), interpolation: cv.INTER_CUBIC);
      final (ok, bigJpeg) = cv.imencode('.jpg', big);
      mat.dispose();
      big.dispose();
      if (!ok) throw StateError('Failed to encode large fixture');

      final tmp = File(
        p.join(Directory.systemTemp.path, 'agelapse_fp_bench.jpg'),
      );
      await tmp.writeAsBytes(bigJpeg);

      Future<double> benchFile(File f, int n) async {
        final times = <int>[];
        for (int i = 0; i < n + 3; i++) {
          final sw = Stopwatch()..start();
          await PhotoFingerprint.compute(f.path);
          sw.stop();
          if (i >= 3) times.add(sw.elapsedMicroseconds);
        }
        return _medianMs(times);
      }

      final smallTmp = File(
        p.join(Directory.systemTemp.path, 'agelapse_fp_bench_small.jpg'),
      );
      await smallTmp.writeAsBytes(small);

      final smallMs = await benchFile(smallTmp, 30);
      final bigMs = await benchFile(tmp, 30);
      debugPrint('B.3  fingerprint sha256: fixture '
          '${(small.length / 1024).round()}KB ${smallMs.toStringAsFixed(2)} ms'
          '  |  12MP JPEG ${(bigJpeg.length / 1024 / 1024).toStringAsFixed(1)}MB '
          '${bigMs.toStringAsFixed(2)} ms  (paid per photo by the benchmark, '
          'not by the real batch path)');

      await tmp.delete();
      await smallTmp.delete();
    });

    testWidgets('B.4 — per-op prices at 12 MP (budget reconciliation)',
        (tester) async {
      // Prices each hot-path op on real pipeline data so the per-photo op mix
      // (printed by the benchmark) can be multiplied out and reconciled
      // against the measured ms/photo. Steady-state timings: the plugin's
      // one-entry decode cache and the pool's source-Mat cache are warm, which
      // matches the real flow (each op after the first reuses the decode its
      // predecessor paid for).
      await preloadFixtures();
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available');
        return;
      }
      final srcPath = await getSampleFacePathAsync(1);
      final small = await File(srcPath).readAsBytes();

      // 12 MP fixture, exactly like PERF_LARGE.
      final mat = cv.imdecode(small, cv.IMREAD_COLOR);
      final big = cv.resize(mat, (4000, 3000), interpolation: cv.INTER_CUBIC);
      final (ok, bigJpegVec) = cv.imencode('.jpg', big);
      mat.dispose();
      big.dispose();
      if (!ok) throw StateError('Failed to encode large fixture');
      final bigJpeg = Uint8List.fromList(bigJpegVec);

      // Benchmark-project canvas: 1080p, 16:9, portrait.
      const canvasW = 1080, canvasH = 1920;
      const srcId = 'b4_fixture';

      Future<double> timeOp(
        int n,
        int warm,
        Future<void> Function() op,
      ) async {
        for (int i = 0; i < warm; i++) {
          await op();
        }
        final times = <int>[];
        for (int i = 0; i < n; i++) {
          final sw = Stopwatch()..start();
          await op();
          sw.stop();
          times.add(sw.elapsedMicroseconds);
        }
        return _medianMs(times);
      }

      // 1. Source decode on the pool (prices prepareSourceMat).
      final decodeMs = await timeOp(20, 3, () async {
        final dims = await StabUtils.prepareSourceMatAndGetDims(
          bigJpeg,
          srcId,
        );
        if (dims == null) throw StateError('prepareSourceMat failed');
      });

      // 2. Warp render, source Mat cache warm (prices each pool warp).
      final warpMs = await timeOp(20, 3, () async {
        final raw = await StabUtils.generateStabilizedRawCVAsync(
          bigJpeg,
          0.0,
          canvasH / 3000.0,
          0.0,
          0.0,
          canvasW,
          canvasH,
          srcId: srcId,
          backgroundColorBGR: const [0, 0, 0],
        );
        if (raw == null) throw StateError('warp failed');
      });

      // Keep one canvas frame for the detect/encode prices below.
      final canvasRaw = await StabUtils.generateStabilizedRawCVAsync(
        bigJpeg,
        0.0,
        canvasH / 3000.0,
        0.0,
        0.0,
        canvasW,
        canvasH,
        srcId: srcId,
        backgroundColorBGR: const [0, 0, 0],
      );
      final canvasData = canvasRaw!['data'] as Uint8List;
      final canvasMatType = canvasRaw['matType'] as int;

      // 3. FULL-mode detect on the source (plugin decode cache warm after the
      // first call, so steady state prices pure inference; the real per-photo
      // path pays the decode once, which is line 1 of the ledger).
      List<dynamic>? rawFacesHolder;
      final detectFullMs = await timeOp(12, 2, () async {
        final result = await StabUtils.getFacesFromBytesWithRaw(bigJpeg);
        if (result == null || result.$1.isEmpty) {
          throw StateError('source detect found no faces');
        }
        rawFacesHolder = result.$2;
      });

      // 4. FULL-mode detect on the warped canvas frame (refinement-pass price).
      int rawDetectFaces = -1;
      final detectRawMs = await timeOp(12, 2, () async {
        final faces = await StabUtils.getFacesFromRawMatBytes(
          canvasData,
          canvasW,
          canvasH,
          canvasMatType,
        );
        rawDetectFaces = faces?.length ?? -1;
      });

      // 5. Embedding for an already-detected face (plugin decode cache warm).
      final embedMs = await timeOp(12, 2, () async {
        final emb = await StabUtils.getFaceEmbeddingForFace(
          rawFacesHolder!.first,
          bigJpeg,
        );
        if (emb == null) throw StateError('embedding failed');
      });

      // 6. PNG encode of the final canvas at the shipped compression level,
      // plus level 1 for the pixel-identical byte-different tradeoff question.
      int png3Bytes = 0, png1Bytes = 0;
      final png3Ms = await timeOp(15, 3, () async {
        final png = await StabUtils.encodeRawToPngAsync(
          canvasData,
          canvasW,
          canvasH,
          canvasMatType,
        );
        png3Bytes = png!.length;
      });
      final png1Ms = await timeOp(15, 3, () async {
        final png = await StabUtils.encodeRawToPngAsync(
          canvasData,
          canvasW,
          canvasH,
          canvasMatType,
          pngCompression: 1,
        );
        png1Bytes = png!.length;
      });

      await IsolatePool.instance.clearMatCache();

      debugPrint(
          'B.4  op prices at 12 MP source / ${canvasW}x$canvasH canvas:');
      debugPrint('B.4    srcDecode(pool):   ${decodeMs.toStringAsFixed(1)} ms');
      debugPrint('B.4    warp(cached src):  ${warpMs.toStringAsFixed(1)} ms');
      debugPrint('B.4    detectFull(src, decode-cached): '
          '${detectFullMs.toStringAsFixed(1)} ms');
      debugPrint('B.4    detectRaw(canvas, faces=$rawDetectFaces): '
          '${detectRawMs.toStringAsFixed(1)} ms');
      debugPrint('B.4    embed(cached):     ${embedMs.toStringAsFixed(1)} ms');
      debugPrint('B.4    pngEncode L3:      ${png3Ms.toStringAsFixed(1)} ms '
          '(${(png3Bytes / 1024).round()} KB)');
      debugPrint('B.4    pngEncode L1:      ${png1Ms.toStringAsFixed(1)} ms '
          '(${(png1Bytes / 1024).round()} KB) — pixel-identical, '
          'byte-different; decision pending');
    });

    testWidgets('B.5 — real-frame PNG encode price + L3 vs L1 pixel parity',
        (tester) async {
      // B.4 priced the encode on a synthetic full-content canvas. Real
      // stabilized frames are mostly black border (manifest scale ~0.22-0.27),
      // so this reproduces photo 1's exact transform from the benchmark
      // manifest and prices L3/L1 on that frame, plus proves the two levels
      // decode to identical pixels (the save path already mixes them: L3 when
      // the initial pass wins, L1 when a refinement pass wins).
      await preloadFixtures();
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available');
        return;
      }
      final srcPath = await getSampleFacePathAsync(1);
      final small = await File(srcPath).readAsBytes();
      final mat = cv.imdecode(small, cv.IMREAD_COLOR);
      final big = cv.resize(mat, (4000, 3000), interpolation: cv.INTER_CUBIC);
      final (ok, bigJpegVec) = cv.imencode('.jpg', big);
      mat.dispose();
      big.dispose();
      if (!ok) throw StateError('Failed to encode large fixture');
      final bigJpeg = Uint8List.fromList(bigJpegVec);

      // Photo 1's transform from the 12 MP benchmark manifest.
      const canvasW = 1080, canvasH = 1920;
      final real = await StabUtils.generateStabilizedRawCVAsync(
        bigJpeg,
        -2.370442,
        0.268130,
        -26.424864,
        -116.388821,
        canvasW,
        canvasH,
        srcId: 'b5_fixture',
        backgroundColorBGR: const [0, 0, 0],
      );
      final data = real!['data'] as Uint8List;
      final matType = real['matType'] as int;

      Future<double> timeOp(
        int n,
        int warm,
        Future<void> Function() op,
      ) async {
        for (int i = 0; i < warm; i++) {
          await op();
        }
        final times = <int>[];
        for (int i = 0; i < n; i++) {
          final sw = Stopwatch()..start();
          await op();
          sw.stop();
          times.add(sw.elapsedMicroseconds);
        }
        return _medianMs(times);
      }

      Uint8List? png3, png1;
      final l3Ms = await timeOp(15, 3, () async {
        png3 = await StabUtils.encodeRawToPngAsync(
          data,
          canvasW,
          canvasH,
          matType,
        );
      });
      final l1Ms = await timeOp(15, 3, () async {
        png1 = await StabUtils.encodeRawToPngAsync(
          data,
          canvasW,
          canvasH,
          matType,
          pngCompression: 1,
        );
      });

      // Pixel parity: both levels must decode to identical pixels.
      final m3 = cv.imdecode(png3!, cv.IMREAD_UNCHANGED);
      final m1 = cv.imdecode(png1!, cv.IMREAD_UNCHANGED);
      final pixelIdentical = _bytesEqual(m3.data, m1.data);
      m3.dispose();
      m1.dispose();

      await IsolatePool.instance.clearMatCache();

      debugPrint('B.5  real-frame encode (photo1 transform, scale 0.27):');
      debugPrint('B.5    L3: ${l3Ms.toStringAsFixed(1)} ms '
          '(${(png3!.length / 1024).round()} KB) — paid when the initial '
          'pass wins');
      debugPrint('B.5    L1: ${l1Ms.toStringAsFixed(1)} ms '
          '(${(png1!.length / 1024).round()} KB) — paid when a refinement '
          'pass wins');
      debugPrint('B.5    pixel parity L3 vs L1: '
          '${pixelIdentical ? "IDENTICAL" : "DIFFER (bug!)"}');
      expect(pixelIdentical, isTrue,
          reason: 'PNG compression level must not change decoded pixels');
    });

    testWidgets('B.7 — PNG compression curve (time + size, levels 0..9)',
        (tester) async {
      // Prices the full zlib-level curve on real stabilized frames, so a
      // speed-vs-size setting can be grounded in numbers instead of a guess.
      // Fully in-process (cv.warpAffine + cv.imencode, no isolate pool), so
      // it runs identically on macOS, an Android emulator, and the iOS
      // simulator. NOTE: emulators/simulators execute on this Mac's CPU, so
      // absolute ms reflect host silicon, not real phone hardware; the useful
      // portable signal is the SHAPE of the curve (level-to-level ratios) and
      // the size deltas (which are CPU-independent).
      // A deterministic synthetic 12 MP source, built from pure integer pixel
      // math so it is byte-identical on every platform. This lets B.7 run on
      // the iOS simulator and Android emulator (where the fixture assets are
      // not bundled) and, crucially, lets the SIZE columns be compared
      // cross-platform: identical synthetic input must yield identical PNG
      // sizes if encoding is deterministic, which is the claim behind reusing
      // the macOS real-fixture sizes for mobile. Structured (not noise) so
      // high levels stay tractable.
      const srcW = 4000, srcH = 3000;
      final synthData = Uint8List(srcW * srcH * 3);
      for (int y = 0; y < srcH; y++) {
        final row = y * srcW * 3;
        for (int x = 0; x < srcW; x++) {
          final i = row + x * 3;
          synthData[i] = (x * 13 + y * 7) & 0xFF; // B: diagonal gradient
          synthData[i + 1] = (x ^ y) & 0xFF; // G: xor texture
          synthData[i + 2] = ((x >> 2) + (y >> 2)) & 0xFF; // R: coarse gradient
        }
      }
      final synthSrc =
          cv.Mat.create(rows: srcH, cols: srcW, type: cv.MatType.CV_8UC3);
      synthSrc.data.setAll(0, synthData);

      // Real 12 MP fixture source, only when the assets are present (desktop).
      await preloadFixtures();
      cv.Mat? realSrc;
      if (!fixturesUnavailable) {
        final srcPath = await getSampleFacePathAsync(1);
        final small = await File(srcPath).readAsBytes();
        final srcSmall = cv.imdecode(small, cv.IMREAD_COLOR);
        realSrc = cv.resize(srcSmall, (srcW, srcH),
            interpolation: cv.INTER_CUBIC); // like PERF_LARGE
        srcSmall.dispose();
      }

      const canvasW = 1080, canvasH = 1920;

      // Reproduces the pool's opaque warp (isolate_pool stabilizeCVRaw) fully
      // in-process, so the frame content matches what the app actually saves.
      cv.Mat warpFrame(
          cv.Mat s, double rot, double scale, double tx, double ty) {
        final iw = s.cols, ih = s.rows;
        final rotMat =
            cv.getRotationMatrix2D(cv.Point2f(iw / 2.0, ih / 2.0), -rot, scale);
        final offX = (canvasW - iw) / 2.0 + tx;
        final offY = (canvasH - ih) / 2.0 + ty;
        rotMat.set<double>(0, 2, rotMat.at<double>(0, 2) + offX);
        rotMat.set<double>(1, 2, rotMat.at<double>(1, 2) + offY);
        final dst = cv.warpAffine(
          s,
          rotMat,
          (canvasW, canvasH),
          flags: cv.INTER_CUBIC,
          borderMode: cv.BORDER_CONSTANT,
          borderValue: cv.Scalar(0, 0, 0, 255),
        );
        rotMat.dispose();
        return dst;
      }

      // Synthetic frames run on every platform (cross-platform size-determinism
      // check). Real-fixture frames run only on desktop and give the absolute
      // numbers used for the decision: a well-aligned face (scale 0.27, mostly
      // black border, the common case my level-1 change sped up) and a tighter
      // crop (scale 0.55, more content, compresses harder).
      final frames = <(String, cv.Mat)>[
        (
          'synthetic aligned scale0.27',
          warpFrame(synthSrc, -2.370442, 0.268130, -26.4, -116.4)
        ),
        if (realSrc != null) ...[
          (
            'real aligned scale0.27',
            warpFrame(realSrc, -2.370442, 0.268130, -26.4, -116.4)
          ),
          ('real tight scale0.55', warpFrame(realSrc, 0.0, 0.55, 0.0, -40.0)),
        ],
      ];

      const levels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

      debugPrint('B.7  PNG compression curve on ${Platform.operatingSystem} '
          '(${canvasW}x$canvasH, in-process encode):');

      for (final (label, frame) in frames) {
        // Reference pixels (level 1) to assert losslessness across the curve.
        final (okRef, refPng) = cv.imencode('.png', frame,
            params: cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, 1]));
        if (!okRef) throw StateError('ref encode failed');
        final refDec = cv.imdecode(refPng, cv.IMREAD_UNCHANGED);

        debugPrint('B.7  --- frame: $label ---');
        int? l1Kb;
        double? l1Ms;
        for (final lvl in levels) {
          final params = cv.VecI32.fromList([cv.IMWRITE_PNG_COMPRESSION, lvl]);
          // warm
          for (int i = 0; i < 2; i++) {
            final (_, w) = cv.imencode('.png', frame, params: params);
            w;
          }
          final times = <int>[];
          int bytes = 0;
          for (int i = 0; i < 9; i++) {
            final sw = Stopwatch()..start();
            final (ok, png) = cv.imencode('.png', frame, params: params);
            sw.stop();
            if (!ok) throw StateError('encode failed at level $lvl');
            times.add(sw.elapsedMicroseconds);
            bytes = png.length;
          }
          final ms = _medianMs(times);
          final kb = (bytes / 1024).round();
          // Capture the level-1 reference (the current/proposed default) so
          // the ratio columns are genuinely "vs L1". L0 (store) precedes it in
          // the loop and shows '--'.
          if (lvl == 1) {
            l1Kb = kb;
            l1Ms = ms;
          }
          // Losslessness: every level must decode to the level-1 pixels.
          final dec = cv.imdecode(
            (cv.imencode('.png', frame, params: params).$2),
            cv.IMREAD_UNCHANGED,
          );
          final lossless = _bytesEqual(refDec.data, dec.data);
          dec.dispose();
          final refKb = l1Kb;
          final refMs = l1Ms;
          final vsL1Size = (refKb == null || refKb == 0)
              ? '--'
              : '${(100 * (kb - refKb) / refKb).toStringAsFixed(1)}%';
          final vsL1Speed = (refMs == null || refMs == 0)
              ? '--'
              : '${(ms / refMs).toStringAsFixed(2)}x';
          debugPrint('B.7    L$lvl: ${ms.toStringAsFixed(1)} ms '
              '($vsL1Speed)  $kb KB ($vsL1Size vs L1)  '
              '${lossless ? "lossless" : "PIXELS DIFFER!"}');
          expect(lossless, isTrue,
              reason: 'level $lvl must be pixel-identical to level 1');
        }
        refDec.dispose();
        frame.dispose();
      }
      synthSrc.dispose();
      realSrc?.dispose();
    });
  });
}

/// Echo isolate for B.1: receives {bytes, reply}, materializes if
/// transferable, and replies with the byte length.
void _echoEntry(SendPort mainPort) {
  final rp = ReceivePort();
  mainPort.send(rp.sendPort);
  rp.listen((msg) {
    final map = msg as Map;
    final b = map['bytes'];
    final reply = map['reply'] as SendPort;
    final int len;
    if (b is TransferableTypedData) {
      len = b.materialize().asUint8List().length;
    } else {
      len = (b as Uint8List).length;
    }
    reply.send(len);
  });
}
