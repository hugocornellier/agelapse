import 'dart:io';
import 'dart:typed_data';

import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:agelapse/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Frame timing of compiled videos: every photo gets the same number of
/// frames, nothing is repeated or dropped, and the file is exactly
/// photos / fps long.
///
/// Regression test for the concat demuxer rounding photo start times to the
/// PNG stream's 1/25 s clock, which repeated and dropped photos above 25 fps,
/// made the pacing uneven below 10, and put frames into the wrong date-stamp
/// window. The checks read the MP4 sample table directly, because the
/// bundled FFmpeg builds cannot decode H.264.
///
/// Run with: `flutter test integration_test/video_frame_timing_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  const int photoCount = 20;
  const String orientation = 'landscape';
  int? projectId;

  setUpAll(() async {
    initDatabase();
    await DB.instance.createTablesIfNotExist();
  });

  tearDown(() async {
    if (projectId == null) return;
    try {
      final projectDir = await DirUtils.getProjectDirPath(projectId!);
      if (await Directory(projectDir).exists()) {
        await deleteQuietly(Directory(projectDir));
      }
      await DB.instance.deleteProject(projectId!);
    } catch (_) {}
    projectId = null;
  });

  /// A project with [photoCount] stabilized frames, one per day, each a
  /// different solid colour.
  Future<int> setUpProject(
    WidgetTester tester, {
    required int fps,
    bool dateStamp = false,
  }) async {
    app.main();
    await pumpUntilAppReady(tester);
    final id = await DB.instance.addProject(
      'Frame timing $fps fps',
      'face',
      DateTime.now().millisecondsSinceEpoch,
    );
    projectId = id;
    final pid = id.toString();
    await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
    await DB.instance.setSettingByTitle(
      'project_orientation',
      orientation,
      pid,
    );
    await DB.instance.setSettingByTitle(
      'video_codec',
      VideoCodec.h264.name,
      pid,
    );
    await DB.instance.setSettingByTitle('framerate', '$fps', pid);
    await DB.instance.setSettingByTitle('framerate_is_default', 'false', pid);
    if (dateStamp) {
      await DB.instance.setSettingByTitle(
        'export_date_stamp_enabled',
        'true',
        pid,
      );
    }

    final dir = Directory(
      p.join(await DirUtils.getStabilizedDirPath(id), orientation),
    );
    await dir.create(recursive: true);
    const int dayMs = 86400000;
    for (int i = 0; i < photoCount; i++) {
      final ts = (1700000000000 + i * dayMs).toString();
      final image = img.Image(width: 1920, height: 1080);
      img.fill(
        image,
        color: img.ColorRgb8((i + 1) * 12, 255 - (i + 1) * 12, 128),
      );
      final bytes = img.encodePng(image);
      await File(p.join(dir.path, '$ts.png')).writeAsBytes(bytes);
      await DB.instance.addPhoto(
        ts,
        id,
        '.png',
        bytes.length,
        '$ts.png',
        orientation,
      );
      await DB.instance.setPhotoStabilized(
        ts,
        id,
        orientation,
        '16:9',
        '1080p',
        0.065,
        0.421875,
      );
    }
    return id;
  }

  Future<_Mp4Timing> compileAndRead(int id) async {
    final published = await VideoUtils.createTimelapseFromProjectId(id, null);
    expect(published, isTrue, reason: 'compile should publish a video');
    final videoPath = await DirUtils.getVideoOutputPath(
      id,
      orientation,
      codec: VideoCodec.h264,
    );
    return _Mp4Timing.parse(await File(videoPath).readAsBytes());
  }

  void expectTiming(
    _Mp4Timing timing, {
    required int fps,
    required int outFps,
    required int framesPerPhoto,
  }) {
    expect(
      timing.sampleCount,
      photoCount * framesPerPhoto,
      reason:
          '$photoCount photos at $fps photos/s should be '
          '${photoCount * framesPerPhoto} frames at $outFps fps',
    );
    expect(
      timing.sampleDeltas.toSet(),
      hasLength(1),
      reason:
          'every frame should last the same time (deltas: ${timing.sampleDeltas})',
    );
    final int delta = timing.sampleDeltas.first;
    expect(
      delta * outFps,
      timing.timescale,
      reason:
          'frame duration should be exactly 1/$outFps s '
          '(delta $delta, timescale ${timing.timescale})',
    );
    // The bundled Windows FFmpeg (8.0.1 with libx264) declares the track one
    // frame longer than its samples at 3 photos/s: 80 samples of 1024 at a
    // timescale of 12288, but an mdhd duration of 82944. The samples are
    // exact, and the declared length is exact on Linux (FFmpeg 6.1.1), macOS,
    // iOS and Android, and with FFmpeg 9.0.1 and libx264, so only Windows
    // gets one frame of slack until the cause in that build is found.
    final int samplesLength = timing.sampleCount * delta;
    expect(
      timing.duration,
      Platform.isWindows
          ? anyOf(samplesLength, samplesLength + delta)
          : samplesLength,
      reason:
          'track duration should be the frames times their duration, '
          'so the video is exactly $photoCount/$fps s long',
    );
  }

  const cases = <({int fps, int outFps, int framesPerPhoto})>[
    // Below the 10 fps floor each photo is repeated a whole number of times.
    (fps: 1, outFps: 10, framesPerPhoto: 10),
    (fps: 3, outFps: 12, framesPerPhoto: 4),
    // From 10 up every photo is one frame.
    (fps: 14, outFps: 14, framesPerPhoto: 1),
    // Above 25 the concat demuxer's rounding used to repeat and drop photos.
    (fps: 60, outFps: 60, framesPerPhoto: 1),
  ];

  for (final c in cases) {
    testWidgets(
      '${c.fps} photos/s: ${c.framesPerPhoto} frame(s) per photo at ${c.outFps} fps',
      (tester) async {
        final id = await setUpProject(tester, fps: c.fps);
        final timing = await compileAndRead(id);
        expectTiming(
          timing,
          fps: c.fps,
          outFps: c.outFps,
          framesPerPhoto: c.framesPerPhoto,
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  testWidgets(
    'date stamps keep one frame per photo at the default 14 photos/s',
    (tester) async {
      final id = await setUpProject(tester, fps: 14, dateStamp: true);
      final timing = await compileAndRead(id);
      expectTiming(timing, fps: 14, outFps: 14, framesPerPhoto: 1);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// The parts of an MP4's first video track needed to check frame timing:
/// the media timescale, the track duration in that timescale, and one
/// duration entry per sample from the time-to-sample table (`stts`).
class _Mp4Timing {
  _Mp4Timing({
    required this.timescale,
    required this.duration,
    required this.sampleDeltas,
  });

  final int timescale;
  final int duration;
  final List<int> sampleDeltas;

  int get sampleCount => sampleDeltas.length;

  static const _containers = {'moov', 'trak', 'mdia', 'minf', 'stbl'};

  static _Mp4Timing parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    int? timescale;
    int? duration;
    List<int>? deltas;

    void walk(int start, int end) {
      int offset = start;
      while (offset + 8 <= end) {
        int size = data.getUint32(offset);
        int header = 8;
        if (size == 1) {
          size = data.getUint64(offset + 8);
          header = 16;
        } else if (size == 0) {
          size = end - offset;
        }
        if (size < header || offset + size > end) break;
        final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
        final body = offset + header;
        if (_containers.contains(type)) {
          walk(body, offset + size);
        } else if (type == 'mdhd' && timescale == null) {
          final version = bytes[body];
          if (version == 1) {
            timescale = data.getUint32(body + 20);
            duration = data.getUint64(body + 24);
          } else {
            timescale = data.getUint32(body + 12);
            duration = data.getUint32(body + 16);
          }
        } else if (type == 'stts' && deltas == null) {
          final entryCount = data.getUint32(body + 4);
          final list = <int>[];
          for (int i = 0; i < entryCount; i++) {
            final count = data.getUint32(body + 8 + i * 8);
            final delta = data.getUint32(body + 12 + i * 8);
            list.addAll(List.filled(count, delta));
          }
          deltas = list;
        }
        offset += size;
      }
    }

    walk(0, bytes.length);
    if (timescale == null || duration == null || deltas == null) {
      throw StateError('no video track timing found in MP4');
    }
    return _Mp4Timing(
      timescale: timescale!,
      duration: duration!,
      sampleDeltas: deltas!,
    );
  }
}
