import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/video_codec.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/ffmpeg_process_manager.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:agelapse/utils/video_utils.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'test_utils.dart';

/// Decoded frame luma (0-255) below this counts as black. The frames are
/// bright color bars, so a correctly decoded frame sits far above it.
const _blackLuma = 30.0;

/// The user's settings: portrait 1080p H.264 at 12 fps, 16-bit frames. Three
/// keyframe intervals (-g 240) so a damaged start would be visible.
const _frameCount = 720;

/// Regression test for corrupted videos from overlapping encodes (a user's
/// report: iPhone 17, iOS 27, AgeLapse 2.7.0; most of the video decoded
/// black). In 2.7.0 a cancel never reached FFmpeg, and a new build wrote the
/// same agelapse.mp4 while the "cancelled" one was still running.
///
/// Replays that sequence with the real compile path and checks that the
/// cancel stops FFmpeg, the cancelled build publishes nothing, and the final
/// video decodes completely. iOS only: the decode uses the native video
/// diagnostics plugin.
///
/// Run with: `flutter test integration_test/video_cancel_race_test.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  int? projectId;
  Directory? templateDir;

  setUpAll(() async {
    initDatabase();
    await DB.instance.createTablesIfNotExist();
  });

  tearDown(() async {
    await templateDir?.delete(recursive: true);
    templateDir = null;
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

  /// Creates a project with [_frameCount] stabilized frames.
  Future<({int id, List<File> templates})> setUpProject(
    WidgetTester tester,
  ) async {
    app.main();
    await pumpUntilAppReady(tester);
    final id = await DB.instance.addProject(
      'Cancel race repro',
      'face',
      DateTime.now().millisecondsSinceEpoch,
    );
    projectId = id;
    final pid = id.toString();
    await DB.instance.setSettingByTitle('video_resolution', '1080p', pid);
    await DB.instance.setSettingByTitle('project_orientation', 'portrait', pid);
    await DB.instance.setSettingByTitle(
      'video_codec',
      VideoCodec.h264.name,
      pid,
    );
    await DB.instance.setSettingByTitle('framerate', '12', pid);
    await DB.instance.setSettingByTitle('framerate_is_default', 'false', pid);
    templateDir = await Directory.systemTemp.createTemp('race_frames');
    final templates = await _writeTemplateFrames(templateDir!);
    for (var i = 0; i < _frameCount; i++) {
      await _addStabilizedFrame(id, i, templates);
    }
    return (id: id, templates: templates);
  }

  testWidgets(
    'cancelling a running build stops FFmpeg and keeps the video intact',
    (tester) async {
      if (!Platform.isIOS) {
        markTestSkipped('Decoding uses the iOS video diagnostics plugin');
        return;
      }
      final project = await setUpProject(tester);
      final timeline = _Timeline();

      var framesA = 0;
      timeline.add('build A started');
      final buildA =
          VideoUtils.createTimelapseFromProjectId(
            project.id,
            (frame) => framesA = frame,
          ).then(
            (ok) =>
                timeline.addAndReturn('build A finished, published=$ok', ok),
          );

      // A new photo arrives about a third of the way in (the user's log:
      // frame 212 of 689), and the stabilization service cancels.
      await _waitUntil(
        () => framesA >= _frameCount ~/ 3,
        'build A never reached a third of its frames',
      );
      timeline.add('cancel at build A frame $framesA');
      final killed = await FFmpegProcessManager.instance.killActiveProcess();
      timeline.add('killActiveProcess returned $killed (FFmpeg exited)');
      final resultA = await buildA;

      await _addStabilizedFrame(project.id, _frameCount, project.templates);
      timeline.add('build B started');
      final resultB = await VideoUtils.createTimelapseFromProjectId(
        project.id,
        null,
      );
      timeline.add('build B finished, published=$resultB');

      final check = await _checkVideo(project.id, _frameCount + 1);
      final summary = {
        'timeline': timeline.entries,
        'killActiveProcessReturned': killed,
        'buildAPublished': resultA,
        'buildBPublished': resultB,
        ...check.summary,
      };
      // ignore: avoid_print
      print('CANCEL_RACE_RESULT ${jsonEncode(summary)}');

      expect(
        <String>[
          if (!killed) 'cancelling did not reach the running FFmpeg session',
          if (resultA) 'the cancelled build still published',
          if (!resultB) 'the follow-up build did not publish',
          ...check.problems,
        ],
        isEmpty,
        reason: jsonEncode(summary),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets('a new build request during a build supersedes it cleanly', (
    tester,
  ) async {
    if (!Platform.isIOS) {
      markTestSkipped('Decoding uses the iOS video diagnostics plugin');
      return;
    }
    final project = await setUpProject(tester);
    final timeline = _Timeline();

    // What a photo import does: request a new build while one is running,
    // without an explicit cancel. The old build must stop first.
    var framesC = 0;
    timeline.add('build C started');
    final buildC =
        VideoUtils.createTimelapseFromProjectId(
          project.id,
          (frame) => framesC = frame,
        ).then(
          (ok) => timeline.addAndReturn('build C finished, published=$ok', ok),
        );
    await _waitUntil(
      () => framesC >= _frameCount ~/ 3,
      'build C never reached a third of its frames',
    );

    await _addStabilizedFrame(project.id, _frameCount, project.templates);
    timeline.add('build D requested at build C frame $framesC');
    final buildD = VideoUtils.createTimelapseFromProjectId(project.id, null)
        .then(
          (ok) => timeline.addAndReturn('build D finished, published=$ok', ok),
        );
    final resultC = await buildC;
    final resultD = await buildD;

    final check = await _checkVideo(project.id, _frameCount + 1);
    final summary = {
      'timeline': timeline.entries,
      'buildCPublished': resultC,
      'buildDPublished': resultD,
      ...check.summary,
    };
    // ignore: avoid_print
    print('SUPERSEDE_RESULT ${jsonEncode(summary)}');

    expect(
      <String>[
        if (resultC) 'the superseded build still published',
        if (!resultD) 'the newer build did not publish',
        ...check.problems,
      ],
      isEmpty,
      reason: jsonEncode(summary),
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}

class _Timeline {
  final _clock = Stopwatch()..start();
  final List<String> entries = [];

  void add(String event) => entries.add(
    '${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s $event',
  );

  T addAndReturn<T>(String event, T value) {
    add(event);
    return value;
  }
}

/// Decodes every frame of the project's published video and lists problems:
/// missing or black frames, or private encode files left behind.
Future<({Map<String, Object?> summary, List<String> problems})> _checkVideo(
  int projectId,
  int expectedFrames,
) async {
  final videoPath = await DirUtils.getVideoOutputPath(
    projectId,
    'portrait',
    codec: VideoCodec.h264,
  );
  final docs = await getApplicationDocumentsDirectory();
  final copy = await File(
    videoPath,
  ).copy(p.join(docs.path, 'cancel_race_repro.mp4'));
  final decoded = await const MethodChannel(
    'com.agelapse/video_diagnostics',
  ).invokeMapMethod<String, dynamic>('decodeAllFrames', {'path': copy.path});
  final lumas = ((decoded?['lumas'] as List?) ?? const [])
      .map((luma) => (luma as num).toDouble())
      .toList();
  final blackFrames = lumas.where((luma) => luma < _blackLuma).length;
  final leftovers = await Directory(p.dirname(videoPath))
      .list()
      .where((e) => p.basename(e.path).startsWith('.agelapse-job'))
      .map((e) => p.basename(e.path))
      .toList();

  return (
    summary: <String, Object?>{
      'expectedFrames': expectedFrames,
      'decodedFrames': lumas.length,
      'blackFrames': blackFrames,
      'blackRuns': _blackRuns(lumas),
      'readerStatus': decoded?['status'],
      'readerError': decoded?['error'],
      'fileBytes': await copy.length(),
      'leftoverPrivateFiles': leftovers,
      'os': Platform.operatingSystemVersion,
    },
    problems: <String>[
      if (lumas.length != expectedFrames)
        'decoded ${lumas.length} of $expectedFrames frames',
      if (blackFrames > 0) '$blackFrames frames decode black',
      if (leftovers.isNotEmpty) 'private encode files left: $leftovers',
    ],
  );
}

Future<void> _waitUntil(bool Function() done, String failure) async {
  final end = DateTime.now().add(const Duration(seconds: 120));
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: failure);
}

/// Encodes six distinct 16-bit color-bar frames (the user's frames were
/// 16-bit). Kept outside the stabilized folder, which the compile purges of
/// files it doesn't know.
///
/// Drawn in 8 bits and converted: filling a uint16 image directly with
/// ColorUint16 writes all-zero (black) pixels.
Future<List<File>> _writeTemplateFrames(Directory dir) async {
  const colors = [
    [255, 0, 0],
    [0, 255, 0],
    [255, 255, 0],
    [0, 0, 255],
    [255, 0, 255],
    [0, 255, 255],
  ];
  const width = 1080;
  const height = 1920;
  final barWidth = width ~/ colors.length;
  final templates = <File>[];
  for (var i = 0; i < colors.length; i++) {
    final image = img.Image(width: width, height: height);
    for (var b = 0; b < colors.length; b++) {
      final c = colors[(b + i) % colors.length];
      img.fillRect(
        image,
        x1: b * barWidth,
        y1: 0,
        x2: (b + 1) * barWidth - 1,
        y2: height - 1,
        color: img.ColorRgb8(c[0], c[1], c[2]),
      );
    }
    final file = File(p.join(dir.path, 'template_$i.png'));
    await file.writeAsBytes(
      img.encodePng(image.convert(format: img.Format.uint16)),
    );
    templates.add(file);
  }
  return templates;
}

/// Adds frame [index] as an already-stabilized portrait photo.
Future<void> _addStabilizedFrame(
  int projectId,
  int index,
  List<File> templates,
) async {
  final dir = Directory(
    p.join(await DirUtils.getStabilizedDirPath(projectId), 'portrait'),
  );
  await dir.create(recursive: true);
  final timestamp = (1000000000 + index * 1000).toString();
  final png = await templates[index % templates.length].copy(
    p.join(dir.path, '$timestamp.png'),
  );
  await DB.instance.addPhoto(
    timestamp,
    projectId,
    '.png',
    await png.length(),
    '$timestamp.png',
    'portrait',
  );
  await DB.instance.setPhotoStabilized(
    timestamp,
    projectId,
    'portrait',
    '16:9',
    '1080p',
    0.065,
    0.421875,
  );
}

/// Index ranges ("start-end") of consecutive black frames.
List<String> _blackRuns(List<double> lumas) {
  final runs = <String>[];
  int? start;
  for (var i = 0; i <= lumas.length; i++) {
    final black = i < lumas.length && lumas[i] < _blackLuma;
    if (black && start == null) start = i;
    if (!black && start != null) {
      runs.add('$start-${i - 1}');
      start = null;
    }
  }
  return runs;
}
