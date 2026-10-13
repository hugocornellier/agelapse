import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/face_stabilizer.dart';
import 'package:agelapse/services/isolate_pool.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart' as vms_io;

/// Runs the stabilization pipeline layer by layer on a run of distinct
/// photos, and logs the process memory after each layer as an
/// `AGELAPSE_PROBE {...}` line. The layer that holds on to memory shows as a
/// climb while the others stay flat.
///
/// Written to find the growth behind #15: on Android, memory grew by tens of
/// MB per stabilized photo until the low-memory killer stopped the app. An
/// earlier version of this probe repeated each stage on one photo and saw
/// every stage flat, so this one works on distinct photos and climbs the
/// layers: detector alone, worker-pool source cache alone, the warp pipeline
/// without FaceStabilizer, FaceStabilizer.stabilize() on distinct photos,
/// the same call on one photo over and over, and finally
/// StabilizationService.
///
/// Before each snapshot every Dart isolate is garbage collected through the
/// VM service, so finalizers have run and the figures are what is really
/// held, and the snapshot carries the Dart heap and the Dart-tracked external
/// (native) memory next to the process RSS and malloc totals. Native memory
/// that grows while the Dart external figure does not is held by something
/// the Dart GC does not know about. Each snapshot also counts the
/// collections the VM has run on its own so far (`gcEvents`), so growth
/// with no collections in between (the collector not getting to the garbage)
/// reads differently from growth across collections (something holding on).
///
/// The photos come from the same zip as android_bulk_import_test.dart (see
/// tool/testlab/README.md); without it this test skips.
///
/// Dart defines:
/// - PROBE_ROUNDS (default 10): photos per stage.
/// - PROBE_RAW_ROUNDS (default 25): photos in the uninterrupted
///   FaceStabilizer stage, which reads the memory without collecting.
/// - PROBE_SERVICE_ROUNDS (default 25): photos StabilizationService runs
///   through, read raw every five photos, and read again after a forced
///   collection every PROBE_SERVICE_GC_EVERY (default 10) photos.
/// - BULK_ZIP_PATH (default empty): read the zip from this path instead of
///   the app's files folder.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  const rounds = int.fromEnvironment('PROBE_ROUNDS', defaultValue: 10);
  const rawRounds = int.fromEnvironment('PROBE_RAW_ROUNDS', defaultValue: 25);
  const serviceRounds = int.fromEnvironment(
    'PROBE_SERVICE_ROUNDS',
    defaultValue: 25,
  );
  const serviceGcEvery = int.fromEnvironment(
    'PROBE_SERVICE_GC_EVERY',
    defaultValue: 10,
  );
  const zipPath = String.fromEnvironment('BULK_ZIP_PATH');

  testWidgets('each pipeline layer, on distinct photos', (tester) async {
    final zip = File(
      zipPath.isNotEmpty
          ? zipPath
          : p.join(
              (await getApplicationSupportDirectory()).path,
              'agelapse_bulk_import.zip',
            ),
    );
    if (!await zip.exists()) {
      markTestSkipped('No zip at ${zip.path} (see tool/testlab/README.md)');
      return;
    }
    final tmp = Directory(
      p.join((await getTemporaryDirectory()).path, 'probe'),
    );
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    final List<File> photos = await _extractPhotos(zip, tmp, rounds + 1);
    await IsolatePool.instance.initialize();
    final vm = await _VmProbe.connect();

    final clock = Stopwatch()..start();
    // [gc] collects every isolate first, [purge] hands malloc's free pages
    // back to the OS; both off gives the raw reading the app lives with.
    Future<void> snapshot(
      String stage,
      int done, {
      bool gc = true,
      bool purge = true,
      Map<String, Object?> extra = const {},
    }) async {
      if (gc && vm != null) await vm.collect();
      final dart = vm != null ? await vm.measure() : const {};
      if (purge) _purgeMalloc();
      // print, not debugPrint: debugPrint throttles and can drop lines.
      // ignore: avoid_print
      print(
        'AGELAPSE_PROBE ${jsonEncode({'stage': stage, 'done': done, 'gc': gc && vm != null, 'purge': purge, 'elapsedS': clock.elapsed.inSeconds, ..._memory(), ..._malloc(), ...dart, ..._ops(), ...extra})}',
      );
    }

    // Runs [body] once per photo and snapshots the memory before and after
    // (collected and purged), with a raw reading every five photos.
    Future<void> stage(
      String name,
      int count,
      Future<void> Function(int i) body, {
      Future<void> Function()? after,
      bool collectAtEnd = true,
    }) async {
      await snapshot(name, 0);
      for (var i = 0; i < count; i++) {
        await body(i);
        if ((i + 1) % 5 == 0 && i + 1 != count) {
          await snapshot(name, i + 1, gc: false, purge: false);
        }
      }
      if (after != null) await after();
      await snapshot(name, count, gc: collectAtEnd, purge: collectAtEnd);
    }

    await snapshot('start', 0, extra: {'photos': photos.length});

    // 1. The detector alone: full detection on each photo's encoded bytes,
    // then one embedding on the detected face, as the stabilizer does for a
    // single-face photo. Each photo replaces the detector isolate's decoded
    // source cache.
    await stage('detectEmbedDistinct', rounds, (i) async {
      final bytes = await photos[i].readAsBytes();
      final result = await StabUtils.getFacesFromBytesWithRaw(bytes);
      if (result != null && result.$2.isNotEmpty) {
        await StabUtils.getFaceEmbeddingForFace(result.$2.first, bytes);
      }
    });

    // 2. The worker pool's source cache alone: decode each photo into its
    // sticky worker's cache, replacing the previous one, and clear at the
    // end.
    await stage('poolCacheDistinct', rounds, (i) async {
      await StabUtils.prepareSourceMatAndGetDims(
        await photos[i].readAsBytes(),
        'cache-$i',
      );
    }, after: () => IsolatePool.instance.clearMatCache());

    // 3. The warp pipeline without FaceStabilizer: cache the source, warp
    // four passes onto a 1080x1920 canvas as raw pixels, detect on each,
    // encode the last to PNG, save it, make its thumbnail, clear the cache.
    await stage('pipelineDistinct', rounds, (i) async {
      final bytes = await photos[i].readAsBytes();
      final id = 'pipe-$i';
      await StabUtils.prepareSourceMatAndGetDims(bytes, id);
      Map<String, dynamic>? last;
      for (final rotation in const [0.0, 1.0, -1.0, 0.5]) {
        final raw = await StabUtils.generateStabilizedRawCVAsync(
          bytes,
          rotation,
          0.5,
          0,
          0,
          1080,
          1920,
          srcId: id,
          backgroundColorBGR: const [0, 0, 0],
          useCachedSrc: true,
        );
        if (raw == null) break;
        await StabUtils.getFacesFromRawMatBytes(
          raw['data'] as Uint8List,
          raw['width'] as int,
          raw['height'] as int,
          raw['matType'] as int,
        );
        last = raw;
      }
      if (last != null) {
        final png = await StabUtils.encodeRawToPngAsync(
          last['data'] as Uint8List,
          last['width'] as int,
          last['height'] as int,
          last['matType'] as int,
          pngCompression: 1,
        );
        if (png != null) {
          await FaceStabilizer.saveBytesToPngFileInIsolate(
            png,
            p.join(tmp.path, 'pipe_$i.png'),
          );
          await StabUtils.thumbnailJpgFromPngBytes(png);
        }
      }
      await IsolatePool.instance.clearMatCache();
    });

    // The stabilizer needs a project, so import the zip the way the gallery
    // does. The import itself was flat in every run so far.
    initDatabase();
    await DB.instance.createTablesIfNotExist();
    final projectId = await DB.instance.addProject(
      'Memory probe',
      'face',
      DateTime.now().millisecondsSinceEpoch,
    );
    final notifier = ValueNotifier<String>('');
    await GalleryUtils.processPickedFile(
      zip,
      projectId,
      notifier,
      onImagesLoaded: () {},
      setProgressInMain: (_) {},
      increaseSuccessfulImportCount: () {},
      increasePhotosImported: (_) {},
    );
    notifier.dispose();
    await DB.instance.setSettingByTitle('default_project', '$projectId');
    // Copied: sqflite's result list is read-only.
    final rows = (await DB.instance.getPhotosByProjectID(projectId)).toList()
      ..sort(
        (a, b) =>
            a['timestamp'].toString().compareTo(b['timestamp'].toString()),
      );
    await snapshot('imported', 0, extra: {'imported': rows.length});
    expect(
      rows.length,
      greaterThan(rounds + 1 + rawRounds),
      reason:
          'the zip must hold more than PROBE_ROUNDS + PROBE_RAW_ROUNDS photos',
    );

    Future<String> rawPath(Map<String, dynamic> row) =>
        DirUtils.getRawPhotoPathFromTimestampAndProjectId(
          row['timestamp'].toString(),
          projectId,
          fileExtension: row['fileExtension'] as String?,
        );

    // 4. FaceStabilizer.stabilize() on distinct photos, as the service calls
    // it: the whole per-photo flow including the database and caches.
    final stabilizer = FaceStabilizer(projectId, () {});
    await stabilizer.init();
    var stabilized = 0;
    await stage('stabilizeDistinct', rounds, (i) async {
      final row = rows[i];
      final result = await stabilizer.stabilize(
        await rawPath(row),
        null,
        () {},
        knownFingerprint: row['fingerprint'] as String?,
      );
      if (result.success) stabilized++;
    });

    // 4b. The same, on the next PROBE_RAW_ROUNDS photos, with nothing done
    // to the memory in between: raw readings as the app sees them. Then one
    // reading after returning malloc's free pages alone, and one after a
    // full collection alone: which of the two brings the memory back says
    // whether the growth is pages the allocator is keeping, or native memory
    // held by Dart garbage that nothing has collected yet.
    final rawStart = rounds + 1;
    await stage('stabilizeRaw', rawRounds, (i) async {
      final row = rows[rawStart + i];
      final result = await stabilizer.stabilize(
        await rawPath(row),
        null,
        () {},
        knownFingerprint: row['fingerprint'] as String?,
      );
      if (result.success) stabilized++;
    }, collectAtEnd: false);
    await snapshot('stabilizeRaw+purge', rawRounds, gc: false);
    await snapshot('stabilizeRaw+gc', rawRounds);

    // 5. The same call on one photo over and over, with the detection and
    // transform caches off so every round runs the full flow. Growth here
    // but not in 4 would mean the flow leaks per call; growth in 4 but not
    // here would mean it leaks per distinct source.
    final samePath = await rawPath(rows[rounds]);
    FaceStabilizer.faceDetectionCacheEnabled = false;
    try {
      await stage('stabilizeSame', rounds, (_) async {
        final result = await stabilizer.stabilize(samePath, null, () {});
        if (result.success) stabilized++;
      });
    } finally {
      FaceStabilizer.faceDetectionCacheEnabled = true;
    }

    // 6. StabilizationService on the next PROBE_SERVICE_ROUNDS photos, the
    // way the app runs it. The bulk runs die in this loop while the stages
    // above stay flat, so this one reads the memory raw every five finished
    // photos and, every PROBE_SERVICE_GC_EVERY photos, once more after a
    // forced collection: growth a collection takes back is garbage the
    // collector was not getting to; growth that stays is held by something
    // live. gcEvents says how often the VM collected on its own meanwhile.
    final orientation = await SettingsUtil.loadProjectOrientation('$projectId');
    final before = await DB.instance.getStabilizedPhotoCountByProjectID(
      projectId,
      orientation,
    );
    await snapshot('service', 0, extra: {'alreadyStabilized': before});
    unawaited(StabilizationService.instance.startStabilization(projectId));
    final deadline = clock.elapsed + const Duration(minutes: 25);
    var byService = 0;
    var lastRead = 0;
    var lastCollected = 0;
    while (clock.elapsed < deadline) {
      await tester.pump(const Duration(seconds: 1));
      byService =
          await DB.instance.getStabilizedPhotoCountByProjectID(
            projectId,
            orientation,
          ) -
          before;
      if (byService >= serviceRounds ||
          !StabilizationService.instance.isActive) {
        break;
      }
      final collectNow =
          serviceGcEvery > 0 &&
          byService ~/ serviceGcEvery > lastCollected ~/ serviceGcEvery;
      if (collectNow || byService ~/ 5 > lastRead ~/ 5) {
        lastRead = byService;
        await snapshot('service', byService, gc: false, purge: false);
      }
      if (collectNow) {
        lastCollected = byService;
        await snapshot('service+gc', byService, purge: false);
      }
    }
    await StabilizationService.instance.cancelAndWait();
    await snapshot('service', byService, gc: false, purge: false);
    await snapshot('service+purge', byService, gc: false);
    await snapshot('service+gc', byService);

    await snapshot('done', rounds, extra: {'stabilized': stabilized});
    expect(stabilized, greaterThan(0), reason: 'nothing was stabilized');
  }, timeout: const Timeout(Duration(minutes: 40)));
}

/// The first [count] photos of [zip] (by name), written to [dir].
Future<List<File>> _extractPhotos(File zip, Directory dir, int count) async {
  final input = InputFileStream(zip.path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final photos =
        archive.files
            .where((f) => f.isFile && f.name.toLowerCase().endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final files = <File>[];
    for (final photo in photos.take(count)) {
      final file = File(p.join(dir.path, p.basename(photo.name)));
      final out = OutputFileStream(file.path);
      photo.writeContent(out);
      out.close();
      files.add(file);
    }
    return files;
  } finally {
    input.close();
  }
}

/// Garbage collects every isolate and reads the Dart heap and the external
/// memory the Dart GC tracks, through the app's own VM service.
class _VmProbe {
  _VmProbe._(this._service) {
    _service.onGCEvent.listen((event) {
      final json = event.json ?? const <String, dynamic>{};
      final key = '${json['gcType'] ?? 'gc'}:${json['reason'] ?? 'unknown'}';
      _gcEvents[key] = (_gcEvents[key] ?? 0) + 1;
    });
  }

  final vms.VmService _service;

  /// Collections the VM has run on its own since the probe connected, by the
  /// VM's type and reason for each.
  final Map<String, int> _gcEvents = {};

  static Future<_VmProbe?> connect() async {
    try {
      final info = await developer.Service.getInfo();
      final http = info.serverUri;
      if (http == null) return null;
      final ws = http.replace(scheme: 'ws', path: '${http.path}ws');
      final probe = _VmProbe._(await vms_io.vmServiceConnectUri(ws.toString()));
      await probe._service.streamListen(vms.EventStreams.kGC);
      return probe;
    } catch (e) {
      // ignore: avoid_print
      print('AGELAPSE_PROBE no VM service: $e');
      return null;
    }
  }

  Future<void> collect() async {
    try {
      final vm = await _service.getVM();
      for (final isolate in vm.isolates ?? const <vms.IsolateRef>[]) {
        final id = isolate.id;
        if (id == null) continue;
        try {
          await _service.callMethod('_collectAllGarbage', isolateId: id);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<Map<String, Object?>> measure() async {
    try {
      final vm = await _service.getVM();
      final isolates = vm.isolates ?? const <vms.IsolateRef>[];
      var heap = 0;
      var external = 0;
      final groups = vm.isolateGroups ?? const <vms.IsolateGroupRef>[];
      for (final group in groups) {
        final id = group.id;
        if (id == null) continue;
        final usage = await _service.getIsolateGroupMemoryUsage(id);
        heap += usage.heapUsage ?? 0;
        external += usage.externalUsage ?? 0;
      }
      return {
        'isolates': isolates.length,
        'dartHeapMb': heap ~/ (1024 * 1024),
        'dartExternalMb': external ~/ (1024 * 1024),
        'gcEvents': Map<String, int>.of(_gcEvents),
      };
    } catch (e) {
      return {'vmError': e.toString()};
    }
  }
}

/// The app's memory: RSS split into anonymous, file-backed and shared pages,
/// and the Flutter image cache (expected to stay empty here).
Map<String, Object?> _memory() {
  final cache = PaintingBinding.instance.imageCache;
  return {
    'rssMb': ProcessInfo.currentRss ~/ (1024 * 1024),
    'maxRssMb': ProcessInfo.maxRss ~/ (1024 * 1024),
    'deviceAvailableMb': _procMb('/proc/meminfo', 'MemAvailable:'),
    'rssAnonMb': _procMb('/proc/self/status', 'RssAnon:'),
    'rssFileMb': _procMb('/proc/self/status', 'RssFile:'),
    'imageCacheMb': cache.currentSizeBytes ~/ (1024 * 1024),
    'liveImages': cache.liveImageCount,
    // The VM mode the framework has asked for; in latency mode the Dart GC
    // puts off collecting for external (native) allocations.
    'perfMode': SchedulerBinding.instance
        .debugGetRequestedPerformanceMode()
        ?.name,
  };
}

/// How many of each pipeline operation have run so far.
Map<String, Object?> _ops() => {
  'detectFull': StabUtils.opDetectFull,
  'detectRaw': StabUtils.opDetectRaw,
  'embeds': StabUtils.opEmbeds,
  'warps': StabUtils.opWarps,
  'pngEncodes': StabUtils.opPngEncodes,
  'sourceDecodes': StabUtils.opSourceDecodes,
};

/// A kB value from a /proc file, in MB, or null where there is no such file.
int? _procMb(String file, String key) {
  try {
    final line = File(
      file,
    ).readAsLinesSync().firstWhere((line) => line.startsWith(key));
    return int.parse(line.split(RegExp(r'\s+'))[1]) ~/ 1024;
  } catch (_) {
    return null;
  }
}

/// Bionic's `struct mallinfo`: every field is a size_t.
final class _MallInfo extends ffi.Struct {
  @ffi.Size()
  external int arena;
  @ffi.Size()
  external int ordblks;
  @ffi.Size()
  external int smblks;
  @ffi.Size()
  external int hblks;
  @ffi.Size()
  external int hblkhd;
  @ffi.Size()
  external int usmblks;
  @ffi.Size()
  external int fsmblks;
  @ffi.Size()
  external int uordblks;
  @ffi.Size()
  external int fordblks;
  @ffi.Size()
  external int keepcost;
}

/// The C heap as malloc sees it: bytes handed out and bytes free but still
/// mapped. Android only (glibc's mallinfo has int fields and is deprecated).
Map<String, Object?> _malloc() {
  if (!Platform.isAndroid) return const {};
  try {
    final mallinfo = ffi.DynamicLibrary.process()
        .lookupFunction<_MallInfo Function(), _MallInfo Function()>('mallinfo');
    final info = mallinfo();
    return {
      'mallocUsedMb': info.uordblks ~/ (1024 * 1024),
      'mallocFreeMb': info.fordblks ~/ (1024 * 1024),
      'mallocArenaMb': info.arena ~/ (1024 * 1024),
      'mallocMmapMb': info.hblkhd ~/ (1024 * 1024),
    };
  } catch (_) {
    return const {};
  }
}

/// Asks the allocator to return freed pages to the OS, so RSS reflects what
/// is in use rather than what malloc is keeping around. Android only.
void _purgeMalloc() {
  if (!Platform.isAndroid) return;
  try {
    const mPurge = -101; // bionic's M_PURGE
    final mallopt = ffi.DynamicLibrary.process()
        .lookupFunction<
          ffi.Int32 Function(ffi.Int32, ffi.Int32),
          int Function(int, int)
        >('mallopt');
    mallopt(mPurge, 0);
  } catch (_) {}
}
