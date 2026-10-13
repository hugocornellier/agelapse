// Memory readings shared by the Android bulk-import and memory-probe tests
// (see tool/testlab/README.md): the process RSS split, bionic's malloc
// totals, and the Dart heap, the Dart-tracked external memory and the
// collections the VM has run, read through the app's own VM service.
import 'dart:developer' as developer;
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:vm_service/vm_service.dart' as vms;
import 'package:vm_service/vm_service_io.dart' as vms_io;

/// Garbage collects every isolate and reads the Dart heap, the external
/// memory the Dart GC tracks and the collections the VM has run on its own,
/// through the app's own VM service. Debug builds only; [connect] returns
/// null where there is no VM service.
class VmProbe {
  VmProbe._(this._service) {
    _service.onGCEvent.listen((event) {
      final json = event.json ?? const <String, dynamic>{};
      final key = '${json['gcType'] ?? 'gc'}:${json['reason'] ?? 'unknown'}';
      _gcEvents[key] = (_gcEvents[key] ?? 0) + 1;
    });
  }

  final vms.VmService _service;

  /// Collections the VM has run since the probe connected, by the VM's type
  /// and reason for each. Forced ones from [collect] count as "debugging".
  final Map<String, int> _gcEvents = {};

  static Future<VmProbe?> connect() async {
    try {
      final info = await developer.Service.getInfo();
      final http = info.serverUri;
      if (http == null) return null;
      final ws = http.replace(scheme: 'ws', path: '${http.path}ws');
      final probe = VmProbe._(await vms_io.vmServiceConnectUri(ws.toString()));
      await probe._service.streamListen(vms.EventStreams.kGC);
      return probe;
    } catch (e) {
      // ignore: avoid_print
      print('AGELAPSE_PROBE no VM service: $e');
      return null;
    }
  }

  /// Runs a full collection in every isolate, so finalizers have run and
  /// the figures that follow are what is really held.
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

  /// The Dart heap and the Dart-tracked external memory across every isolate
  /// group, the isolate count, and the collections run so far.
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
/// the Flutter image cache, and the VM performance mode the framework has
/// asked for (in latency mode the Dart GC puts off collecting for external
/// allocations).
Map<String, Object?> processMemory() {
  final cache = PaintingBinding.instance.imageCache;
  return {
    'rssMb': ProcessInfo.currentRss ~/ (1024 * 1024),
    'maxRssMb': ProcessInfo.maxRss ~/ (1024 * 1024),
    'deviceAvailableMb': procMb('/proc/meminfo', 'MemAvailable:'),
    'rssAnonMb': procMb('/proc/self/status', 'RssAnon:'),
    'rssFileMb': procMb('/proc/self/status', 'RssFile:'),
    'rssShmemMb': procMb('/proc/self/status', 'RssShmem:'),
    'imageCacheMb': cache.currentSizeBytes ~/ (1024 * 1024),
    'imageCacheCount': cache.currentSize,
    'liveImages': cache.liveImageCount,
    'perfMode': SchedulerBinding.instance
        .debugGetRequestedPerformanceMode()
        ?.name,
  };
}

/// A kB value from a /proc file, in MB, or null where there is no such file.
int? procMb(String file, String key) {
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
Map<String, Object?> mallocStats() {
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
void purgeMalloc() {
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
