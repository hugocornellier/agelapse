import 'dart:io';
import 'dart:math' as math;

import 'package:agelapse/main.dart' as app;
import 'package:agelapse/models/face_detection_cache_result.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/face_stabilizer.dart';
import 'package:agelapse/services/log_service.dart';
import 'package:agelapse/services/stabilization_progress.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/services/stabilization_state.dart';
import 'package:agelapse/services/stabilization_settings.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// Issue #35: a face the user picked by hand ("Stabilize on a different
/// face") must survive the full re-stabilization that a settings change
/// triggers. 2.7.0 started storing the pick with the photo's cached faces;
/// these scenarios drive that promise through the same code the app uses:
/// photos are imported, stabilized by [StabilizationService], the pick is
/// made with [FaceStabilizer.stabilize] and a target box exactly like the
/// faces dialog and the "stabilize on a different face" page do, then a
/// setting is changed the way the settings pages save it, and the service
/// runs again.
///
/// Every face scenario composes one photo from two people: the person the
/// rest of the timelapse is about (sample_faces day1, with day3 as the
/// single-face reference photo) and a stranger. The automatic pass picks the
/// timelapse person, by embedding match against the reference photo or, with
/// no reference yet, as the centermost face; the user picks the stranger.
/// That is the shape in which losing the pick is visible: were both faces the
/// same person, the fallback could land on the picked face by chance and hide
/// the loss.
///
/// The scenarios cover the shapes a real project takes. The last two were
/// reproductions of ways the stored pick was lost (a stored fingerprint that
/// no longer hashes the raw file; a cat or dog project) and now guard the
/// fixes, with the former mechanism in each scenario's comment.
///
/// Run with: `flutter test integration_test/manual_face_pick_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Manual face pick survives re-stabilization (#35)', () {
    _registerScenarios(const [
      _Scenario(
        name: 'both faces large, automatic run first',
        secondFaceScale: 1.0,
        autoBeforePick: true,
      ),
      _Scenario(
        name: 'pick made before any automatic run',
        secondFaceScale: 1.0,
        autoBeforePick: false,
      ),
      _Scenario(
        name: 'second face too small for the automatic pass',
        secondFaceScale: 0.3,
        autoBeforePick: true,
      ),
      _Scenario(
        name:
            'eye position changed twice, the second time back to the '
            'original values',
        secondFaceScale: 1.0,
        autoBeforePick: true,
        change: _Change.eyeOffsetsTwice,
      ),
      _Scenario(
        name: 'aspect ratio changed instead of the eye position',
        secondFaceScale: 1.0,
        autoBeforePick: true,
        change: _Change.aspectRatio,
      ),
      _Scenario(
        name: 'project orientation changed instead of the eye position',
        secondFaceScale: 1.0,
        autoBeforePick: true,
        change: _Change.orientation,
      ),
      _Scenario(
        name:
            'legacy photo row with no stored fingerprint at '
            're-stabilization time',
        secondFaceScale: 1.0,
        autoBeforePick: true,
        fingerprint: _Fingerprint.nullBeforeRestab,
      ),
      _Scenario(
        name: 'a Manual Stabilization slider edit saved on top of the pick',
        secondFaceScale: 1.0,
        autoBeforePick: true,
        sliderEditAfterPick: true,
      ),
      // The photo row's stored fingerprint does not match the raw file's
      // content hash. The service keys every cache lookup by the stored value
      // (StabilizationService passes photo['fingerprint'] as knownFingerprint).
      // The pick used to key its write by hashing the file, so its row
      // replaced the service's row under another fingerprint; the next full
      // run missed, detected afresh, picked the automatic face and overwrote
      // it. Every cache key now comes from StabUtils.resolvePhotoFingerprint,
      // which prefers the stored value. A stored fingerprint can drift from
      // the file through ProjectFolderSyncService._tryBackfillSourceInfo,
      // which hashes the LINKED FOLDER file and backfills it onto a legacy row
      // matched only by byte length.
      _Scenario(
        name:
            'stored fingerprint differs from the raw file (linked-folder '
            'legacy backfill)',
        secondFaceScale: 1.0,
        autoBeforePick: true,
        fingerprint: _Fingerprint.staleFromImport,
      ),
      // Cat and dog projects offer "Stabilize on Other Faces" from the gallery
      // menu (gallery_page.dart) and store the pick like face projects do.
      // FaceStabilizer._calculateRotationAngleAndScaleAnimal used to ignore
      // the stored index and always take the centermost subject (and recorded
      // no index on the automatic pass); it now honors and records it like
      // the face path. Sample cats day 2 and day 3 are the pair the cat
      // detector finds both of when composed; day 4 is the reference.
      _Scenario(
        name: 'cat project',
        projectType: 'cat',
        firstDay: 2,
        secondDay: 3,
        refDay: 4,
        secondFaceScale: 0.6,
        autoBeforePick: true,
      ),
    ]);
  });
}

void _registerScenarios(List<_Scenario> scenarios) {
  int? testProjectId;
  Directory? tempDir;

  setUpAll(() async {
    initDatabase();
    await DB.instance.createTablesIfNotExist();
    await preloadFixtures();
  });

  setUp(() async {
    await _cleanupTestData();
    testProjectId = null;
  });

  tearDown(() async {
    await StabilizationService.instance.cancelAndWait();
    if (testProjectId != null) {
      try {
        final projectDir = await DirUtils.getProjectDirPath(testProjectId!);
        await _deleteDir(Directory(projectDir));
        await DB.instance.deleteProject(testProjectId!);
      } catch (_) {}
      testProjectId = null;
    }
    if (tempDir != null) {
      await _deleteDir(tempDir!);
      tempDir = null;
    }
  });

  tearDownAll(() async {
    await cleanupFixtures();
  });

  for (final scenario in scenarios) {
    testWidgets(
      '${scenario.name}: the picked ${scenario.subject} is still used after '
      '${scenario.change.label}',
      (tester) async {
        app.main();
        // A fixed pump is not enough on cold CI runners (see test_utils):
        // the app's startup work was still running when the service was
        // asked to stabilize, and the run failed.
        await pumpUntilAppReady(tester);

        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        testProjectId = await DB.instance.addProject(
          'Manual face pick',
          scenario.projectType,
          DateTime.now().millisecondsSinceEpoch,
        );
        tempDir = await Directory.systemTemp.createTemp('face_pick_');
        await _runScenario(scenario, testProjectId!, tempDir!);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}

Future<void> _runScenario(
  _Scenario scenario,
  int pid,
  Directory tempDir,
) async {
  final type = scenario.projectType;
  final modelVersion = StabUtils.detectorModelVersionForProjectType(type);
  // Keep the service runs to stabilization only; no FFmpeg here.
  await SettingsUtil.setAutoCompileVideo(pid.toString(), false);

  final fixture = await _composeTwoSubjectPhoto(
    tempDir,
    firstPath: await scenario.samplePath(scenario.firstDay),
    secondPath: await scenario.secondSubjectPath(tempDir),
    secondScale: scenario.secondFaceScale,
  );

  // Photo 1: two subjects of different sizes.
  await _import(fixture.path, pid);
  final twoFaces = (await DB.instance.getPhotosByProjectID(pid)).single;
  final ts = twoFaces['timestamp'] as String;
  final importFingerprint = twoFaces['fingerprint'] as String?;
  expect(importFingerprint, isNotNull, reason: 'import stores a fingerprint');

  // Photo 2: a single subject. For faces it is the embedding reference the
  // automatic pick matches against, like any real timelapse; for every type
  // it gives the scale ratio a settings change is expected to produce.
  await _import(await scenario.samplePath(scenario.refDay), pid);
  final photos = await DB.instance.getPhotosByProjectID(pid);
  expect(photos, hasLength(2));
  final refTs =
      photos.firstWhere((r) => r['timestamp'] != ts)['timestamp'] as String;

  final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
    ts,
    pid,
    fileExtension: twoFaces['fileExtension'],
  );
  final fileFingerprint = await StabUtils.computeRawPhotoFingerprint(rawPath);
  expect(
    fileFingerprint,
    importFingerprint,
    reason:
        'an import copies the bytes verbatim, so the stored fingerprint '
        'is the file hash',
  );

  if (scenario.fingerprint == _Fingerprint.staleFromImport) {
    // What ProjectFolderSyncService._tryBackfillSourceInfo leaves behind when
    // a legacy row is matched by byte length against a linked-folder file
    // whose bytes differ from the raw file: a stored fingerprint that no
    // longer hashes the raw photo. From here on the service, every dialog and
    // the pick must all key their cache rows by this value.
    await _setFingerprint(ts, pid, 'stale:${'0' * 64}');
  }

  var settings = await StabilizationSettings.load(pid);
  var orientation = settings.projectOrientation;
  String scaleColumn() =>
      '${DB.instance.getStabilizedColumn(orientation)}ScaleFactor';

  Future<String?> storedFingerprint() async =>
      (await DB.instance.getPhotoByTimestamp(ts, pid))!['fingerprint']
          as String?;

  /// The row the service and the faces dialog see: keyed by the stored
  /// fingerprint.
  Future<FaceDetectionCacheResult?> readServiceCache() async {
    final fp = await storedFingerprint() ?? fileFingerprint;
    return DB.instance.getFaceDetectionCache(ts, pid, modelVersion, fp);
  }

  /// The row for this photo whatever fingerprint it was written under.
  Future<FaceDetectionCacheResult?> readAnyCache() =>
      _readCacheAnyFingerprint(ts, pid, modelVersion);

  Future<double> readScale([String? timestamp]) async {
    final row = await DB.instance.getPhotoByTimestamp(timestamp ?? ts, pid);
    return (row![scaleColumn()] as num).toDouble();
  }

  // 1. Automatic stabilization, as the app does when photos arrive.
  double? autoScale;
  Rect? autoBox;
  if (scenario.autoBeforePick) {
    await _runService(pid, 'the automatic run');
    final autoCache = await readServiceCache();
    expect(autoCache, isNotNull, reason: 'auto run caches the faces');
    final autoIndex = autoCache!.selectedFaceIndex;
    expect(autoIndex, isNotNull, reason: 'auto run records its pick');
    autoBox = autoCache.faces[autoIndex!].boundingBox;
    autoScale = await readScale();
  }

  // 2. The user picks the other subject. The faces dialog offers the cached
  //    faces; the "stabilize on a different face" page runs detection without
  //    the size filter. Both hand the chosen box to the same stabilize call.
  final picker = FaceStabilizer(pid, () {});
  await picker.init();
  final List<Rect> candidates;
  final cached = await readServiceCache();
  if (cached != null && cached.faces.length >= 2) {
    candidates = cached.faces.map((f) => f.boundingBox).toList();
  } else {
    final detected = await picker.getFacesFromRawPhotoPath(
      rawPath,
      fixture.width,
      filterByFaceSize: false,
    );
    candidates = [for (final f in detected ?? const []) f.boundingBox as Rect];
  }
  expect(
    candidates.length,
    2,
    reason: 'the fixture must show two detectable ${scenario.subject}s',
  );
  // The second subject sits to the right of the first on the canvas.
  final Rect pickedBox = candidates.singleWhere(
    (b) => b.left >= fixture.secondLeft,
    orElse: () => throw TestFailure(
      'exactly one detected ${scenario.subject} should lie in the second '
      'subject\'s area (x >= ${fixture.secondLeft}): $candidates',
    ),
  );
  if (autoBox != null) {
    expect(
      _iou(autoBox, pickedBox),
      lessThan(0.5),
      reason:
          'the automatic pass is expected to choose the first subject (the '
          'embedding match for the single-${scenario.subject} photo, or the '
          'centermost ${scenario.subject}); the user then picks the other '
          'one. Auto box $autoBox, second subject $pickedBox',
    );
  }

  final pick = await picker.stabilize(
    rawPath,
    null,
    () {},
    targetBoundingBox: pickedBox,
  );
  expect(pick.success, isTrue, reason: 'stabilizing on the picked subject');
  final manualScale = await readScale();
  if (autoScale != null) {
    expect(
      (manualScale - autoScale).abs() / autoScale,
      greaterThan(0.05),
      reason:
          'the two subjects differ in size, so the pick must change the '
          'scale',
    );
  }
  if (!scenario.autoBeforePick) {
    // The picked photo is done; this run only stabilizes the single-subject
    // photo, as the app would after the pick.
    await _runService(pid, 'the automatic run after the pick');
    expect(await readScale(), manualScale, reason: 'pick untouched');
  }

  double? sliderScale;
  if (scenario.sliderEditAfterPick) {
    // The Manual Stabilization page saves a hand-tuned transform through
    // persistManualTransform; this is the part of that save that outlives the
    // page. A scale the algorithm would never produce makes the entry easy to
    // recognize later.
    final row = (await DB.instance.getPhotoByTimestamp(ts, pid))!;
    final column = DB.instance.getStabilizedColumn(orientation);
    sliderScale = manualScale * 1.37;
    await picker.persistManualTransform(
      rawPhotoPath: rawPath,
      timestamp: ts,
      translateX: (row['${column}TranslateX'] as num).toDouble(),
      translateY: (row['${column}TranslateY'] as num).toDouble(),
      rotationDegrees: (row['${column}RotationDegrees'] as num).toDouble(),
      scaleFactor: sliderScale,
    );
  }
  await picker.dispose();

  final pickedCache = await readAnyCache();
  expect(pickedCache, isNotNull, reason: 'the pick is cached');
  expect(
    _bestMatch(pickedCache!, pickedBox),
    pickedCache.selectedFaceIndex,
    reason: 'the cache records the picked subject as selected',
  );

  // 3 and 4. The user changes a setting that re-stabilizes every photo, and
  //    the service runs again. Each change is what the settings page does on
  //    save, minus the UI.
  final steps = scenario.change == _Change.eyeOffsetsTwice ? 2 : 1;
  // The algorithm's scale for the picked subject, and for the subject the
  // automatic pass chose, carried through each change.
  // With a slider edit saved, the stored scale is the edit's, carried over.
  var pickedScale = sliderScale ?? manualScale;
  var otherScale = autoScale;
  for (var step = 0; step < steps; step++) {
    final refScaleBefore = await readScale(refTs);
    final settingsBefore = settings;

    switch (scenario.change) {
      case _Change.eyeOffsets:
      case _Change.eyeOffsetsTwice:
        // Step 0 moves the eyes; step 1 moves them back to where they were.
        final dx = step == 0 ? 0.02 : -0.02;
        final dy = step == 0 ? 0.04 : -0.04;
        final suffix = orientation == 'landscape' ? 'Landscape' : 'Portrait';
        await DB.instance.setSettingByTitle(
          'eyeOffsetX$suffix',
          (settings.eyeOffsetX + dx).toString(),
          pid.toString(),
        );
        await DB.instance.setSettingByTitle(
          'eyeOffsetY$suffix',
          (settings.eyeOffsetY + dy).toString(),
          pid.toString(),
        );
      case _Change.aspectRatio:
        await DB.instance.setSettingByTitle(
          'aspect_ratio',
          settings.aspectRatio == '4:3' ? '16:9' : '4:3',
          pid.toString(),
        );
      case _Change.orientation:
        orientation = orientation == 'landscape' ? 'portrait' : 'landscape';
        await DB.instance.setSettingByTitle(
          'project_orientation',
          orientation,
          pid.toString(),
        );
    }
    await DB.instance.resetStabilizationStatusForProject(pid, orientation);
    settings = await StabilizationSettings.load(pid);
    expect(
      (await StabUtils.getUnstabilizedPhotos(pid)).length,
      2,
      reason: 'the change queues every photo again',
    );

    if (scenario.fingerprint == _Fingerprint.nullBeforeRestab) {
      // A row imported before fingerprints existed and never backfilled.
      await _setFingerprint(ts, pid, null);
      expect(await storedFingerprint(), isNull);
    }

    // "This will re-stabilize all photos."
    await _runService(
      pid,
      'the re-stabilization after ${scenario.change.label}',
    );

    final afterCache = await readAnyCache();
    expect(afterCache, isNotNull);
    final afterIndex = afterCache!.selectedFaceIndex;
    final afterScale = await readScale();
    final rowVisibleToService = (await readServiceCache()) != null;
    // A settings change moves every photo's scale by the same ratio (the X
    // eye offset sets the eye spacing, the aspect ratio and orientation set
    // the canvas width); the single-subject photo gives that ratio. The
    // refinement passes re-detect on the output, so a few percent of drift is
    // normal; the two subjects differ in size by 30% or more.
    final refRatio = await readScale(refTs) / refScaleBefore;
    final expectedPicked = pickedScale * refRatio;
    final expectedOther = otherScale == null ? null : otherScale * refRatio;
    final when = 'After ${scenario.change.label} (step ${step + 1})';
    final detail =
        'scale now $afterScale; expected about $expectedPicked for the '
        'picked ${scenario.subject} and about $expectedOther for the '
        'other one (single-${scenario.subject} photo ratio $refRatio). '
        'Cache row: selected index $afterIndex, the picked '
        '${scenario.subject} is index ${_bestMatch(afterCache, pickedBox)}, '
        'row keyed by the stored fingerprint: $rowVisibleToService.';
    expect(
      (afterScale - expectedPicked).abs() / expectedPicked,
      lessThan(0.1),
      reason:
          '$when, the photo should be scaled for the picked '
          '${scenario.subject} (#35). $detail',
    );
    // With a slider edit the exact check below is the stronger one, and a
    // 1.37x edit can land near the other subject's size by coincidence.
    if (expectedOther != null && sliderScale == null) {
      expect(
        (afterScale - expectedPicked).abs(),
        lessThan((afterScale - expectedOther).abs()),
        reason:
            '$when, the scale is closer to the other ${scenario.subject}\'s '
            'than to the picked one\'s (#35). $detail',
      );
    }
    expect(
      afterIndex != null && _bestMatch(afterCache, pickedBox) == afterIndex,
      isTrue,
      reason:
          '$when, the cache row no longer records the picked '
          '${scenario.subject} as selected (#35). $detail',
    );
    pickedScale = afterScale;
    otherScale = expectedOther;
    if (sliderScale != null) {
      // A saved slider edit is re-projected onto the new settings
      // (ManualTransformReprojection) with no detection involved: its scale
      // follows the goal eye spacing (eye offset X times canvas width)
      // exactly. 2.7.0 keyed the edit by the eye offsets and dropped it here.
      final widthBefore = StabUtils.getOutputDimensions(
        settingsBefore.resolution,
        settingsBefore.aspectRatio,
        settingsBefore.projectOrientation,
      )!.$1;
      final widthAfter = StabUtils.getOutputDimensions(
        settings.resolution,
        settings.aspectRatio,
        settings.projectOrientation,
      )!.$1;
      final expectedSlider =
          sliderScale *
          (settings.eyeOffsetX * widthAfter) /
          (settingsBefore.eyeOffsetX * widthBefore);
      expect(
        afterScale,
        closeTo(expectedSlider, 1e-6 * expectedSlider),
        reason:
            '$when, the slider edit should be carried over: slider '
            '$sliderScale, expected $expectedSlider, now $afterScale',
      );
      sliderScale = expectedSlider;
    }
  }
}

enum _Change {
  eyeOffsets('the eye position changes'),
  eyeOffsetsTwice('the eye position changes twice'),
  aspectRatio('the aspect ratio changes'),
  orientation('the project orientation changes');

  const _Change(this.label);
  final String label;
}

enum _Fingerprint {
  /// The stored fingerprint is left as the import wrote it.
  keep,

  /// The stored fingerprint is cleared right before the re-stabilization, as
  /// on a row imported before fingerprints existed.
  nullBeforeRestab,

  /// The stored fingerprint is replaced by a value that does not hash the raw
  /// file, before any stabilization, as the linked-folder legacy backfill can
  /// leave it.
  staleFromImport,
}

class _Scenario {
  const _Scenario({
    required this.name,
    required this.secondFaceScale,
    required this.autoBeforePick,
    this.projectType = 'face',
    this.firstDay = 1,
    this.secondDay = 2,
    this.refDay = 3,
    this.change = _Change.eyeOffsets,
    this.fingerprint = _Fingerprint.keep,
    this.sliderEditAfterPick = false,
  });

  final String name;
  final String projectType;

  /// Sample days for the first subject, the second subject (animals only;
  /// faces use the stranger) and the single-subject reference photo.
  final int firstDay;
  final int secondDay;
  final int refDay;

  /// Size of the second subject relative to the first. Below about 0.75 the
  /// stranger's face drops under a tenth of the canvas width and the
  /// automatic pass filters it out as too small, as it does in group photos.
  final double secondFaceScale;

  /// Whether the photo was stabilized automatically before the user picked.
  final bool autoBeforePick;

  final _Change change;
  final _Fingerprint fingerprint;

  /// Whether a Manual Stabilization slider edit is saved after the pick.
  final bool sliderEditAfterPick;

  String get subject => projectType == 'face' ? 'face' : projectType;

  Future<String> samplePath(int day) => switch (projectType) {
    'cat' => getSampleCatPathAsync(day),
    'dog' => getSampleDogPathAsync(day),
    _ => getSampleFacePathAsync(day),
  };

  /// The subject the user picks: for faces a stranger (the person on the
  /// right in sample_poses/two_people.jpeg, cropped to head and shoulders and
  /// brought to the sample's width), for animals the day 2 sample.
  Future<String> secondSubjectPath(Directory tempDir) async {
    if (projectType != 'face') return samplePath(secondDay);
    final source = await getFixturePathAsync(
      p.join('sample_poses', 'two_people.jpeg'),
    );
    final image = img.decodeImage(await File(source).readAsBytes())!;
    final head = img.copyCrop(image, x: 1300, y: 180, width: 380, height: 420);
    final resized = img.copyResize(
      head,
      width: 640,
      interpolation: img.Interpolation.cubic,
    );
    final out = p.join(tempDir.path, 'stranger.jpg');
    await File(out).writeAsBytes(img.encodeJpg(resized, quality: 92));
    return out;
  }
}

/// Index of the cached face that overlaps [box] the most.
int _bestMatch(FaceDetectionCacheResult cache, Rect box) {
  var best = -1;
  var bestIoU = -1.0;
  for (var i = 0; i < cache.faces.length; i++) {
    final iou = _iou(cache.faces[i].boundingBox, box);
    if (iou > bestIoU) {
      bestIoU = iou;
      best = i;
    }
  }
  return best;
}

double _iou(Rect a, Rect b) {
  final inter = a.intersect(b);
  if (inter.width <= 0 || inter.height <= 0) return 0;
  final interArea = inter.width * inter.height;
  final union = a.width * a.height + b.width * b.height - interArea;
  return union <= 0 ? 0 : interArea / union;
}

Future<void> _import(String path, int projectId) async {
  final notifier = ValueNotifier<String>('');
  try {
    final imported = await GalleryUtils.importXFile(
      XFile(path),
      projectId,
      notifier,
    );
    expect(imported, isTrue, reason: '${p.basename(path)} should import');
  } finally {
    notifier.dispose();
  }
}

/// Runs the stabilization service as the app does. The service only logs the
/// reason when a run fails, so on failure this reports its last error or
/// cancellation state and the tail of the app log.
Future<void> _runService(int pid, String what) async {
  StabilizationProgress? last;
  final sub = StabilizationService.instance.progressStream.listen((p) {
    if (p.state == StabilizationState.error ||
        p.state == StabilizationState.cancelled) {
      last = p;
    }
  });
  final ok = await StabilizationService.instance.startStabilization(pid);
  await sub.cancel();
  if (ok) return;
  var logTail = '';
  try {
    final lines = (await LogService.instance.getLogContent()).split('\n');
    logTail = lines.skip(math.max(0, lines.length - 40)).join('\n');
  } catch (_) {}
  fail(
    'The stabilization service reported failure during $what '
    '(state ${last?.state}, message ${last?.errorMessage}). '
    'Last log lines:\n$logTail',
  );
}

/// Overwrites (or clears, with null) the fingerprint stored on a photo row.
/// The app never does this directly; the test uses it to put a row into the
/// states described on [_Fingerprint].
Future<void> _setFingerprint(String ts, int pid, String? value) async {
  final db = await DB.instance.database;
  await db.update(
    DB.photoTable,
    {'fingerprint': value},
    where: 'timestamp = ? AND projectID = ?',
    whereArgs: [ts, pid],
  );
}

/// Reads this photo's face cache row by (timestamp, project) alone, so a row
/// written under a fingerprint other than the stored one is still found.
Future<FaceDetectionCacheResult?> _readCacheAnyFingerprint(
  String ts,
  int pid,
  String modelVersion,
) async {
  final db = await DB.instance.database;
  final rows = await db.query(
    DB.faceDetectionCacheTable,
    columns: ['fingerprint'],
    where: 'timestamp = ? AND projectID = ?',
    whereArgs: [ts, pid],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return DB.instance.getFaceDetectionCache(
    ts,
    pid,
    modelVersion,
    rows.single['fingerprint'] as String,
  );
}

/// Two sample subjects side by side on one canvas: the first at full size,
/// the second scaled by [secondScale], so the two picks give clearly
/// different transforms.
Future<({String path, int width, int secondLeft})> _composeTwoSubjectPhoto(
  Directory dir, {
  required String firstPath,
  required String secondPath,
  required double secondScale,
}) async {
  final a = img.decodeJpg(await File(firstPath).readAsBytes())!;
  final b = img.decodeJpg(await File(secondPath).readAsBytes())!;
  final bSmall = img.copyResize(
    b,
    width: (b.width * secondScale).round(),
    interpolation: img.Interpolation.average,
  );
  const gap = 40;
  final canvas = img.Image(
    width: a.width + gap + bSmall.width,
    height: math.max(a.height, bSmall.height) + gap,
  );
  img.fill(canvas, color: img.ColorRgb8(236, 236, 236));
  img.compositeImage(canvas, a, dstX: 0, dstY: gap);
  img.compositeImage(
    canvas,
    bSmall,
    dstX: a.width + gap,
    dstY: canvas.height - bSmall.height,
  );
  final out = p.join(dir.path, 'two_subjects.jpg');
  await File(out).writeAsBytes(img.encodeJpg(canvas, quality: 92));
  return (path: out, width: canvas.width, secondLeft: a.width + gap);
}

Future<void> _deleteDir(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (_) {}
}

Future<void> _cleanupTestData() async {
  try {
    await DB.instance.deleteAllPhotos();
    final projects = await DB.instance.getAllProjects();
    for (final project in projects) {
      await DB.instance.deleteProject(project['id'] as int);
    }
    await DB.instance.setSettingByTitle('default_project', 'none');
  } catch (_) {}
}
