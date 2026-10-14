import 'dart:io';
import 'dart:math' as math;

import 'package:agelapse/models/transform_cache_entry.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/services/face_stabilizer.dart';
import 'package:agelapse/services/log_service.dart';
import 'package:agelapse/services/stabilization_progress.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/services/stabilization_settings.dart';
import 'package:agelapse/services/stabilization_state.dart';
import 'package:agelapse/utils/dir_utils.dart';
import 'package:agelapse/utils/gallery_utils.dart';
import 'package:agelapse/utils/manual_transform_reprojection.dart';
import 'package:agelapse/utils/settings_utils.dart';
import 'package:agelapse/utils/stabilizer_utils/stabilizer_utils.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;
import 'package:agelapse/utils/transform_cache_key.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'test_utils.dart';

/// A hand-tuned transform saved from the Manual Stabilization page (offset,
/// rotation, scale) must survive the settings changes that re-stabilize
/// every photo: eye position, aspect ratio and resolution, including a custom
/// canvas whose width and height change by different factors. 2.7.0 kept
/// such an edit only across a proportional resolution change and dropped it
/// for everything else. It is now re-projected (ManualTransformReprojection)
/// onto the new settings, and comes back exactly when the settings do.
///
/// Both tests drive the app's own path: a photo is imported, stabilized by
/// [StabilizationService], edited through [FaceStabilizer.persistManualTransform]
/// (the part of the page's save that outlives the page), then each setting is
/// changed the way the settings pages save it and the service runs again.
/// The stored transform is compared with the re-projection of the saved edit
/// to a millionth of a pixel, values the detector could not land on by
/// chance, and the manual cache row is checked to still be there with the
/// settings the edit was saved under.
///
/// The second test plants a row under the key 2.7.0 and 2.8.0 wrote manual
/// edits with, which carries no eye offsets, and checks it is still found,
/// re-keyed, and carried across the next change.
///
/// Run with: `flutter test integration_test/manual_edit_reprojection_test.dart -d macos`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  group('Manual slider edits survive settings changes', () {
    int? testProjectId;

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
    });

    tearDownAll(() async {
      await cleanupFixtures();
    });

    testWidgets(
      'an edit is re-projected across eye position, aspect ratio and custom '
      'canvas changes, and returns exactly when the settings do',
      (tester) async {
        await launchApp(tester);
        if (fixturesUnavailable) {
          markTestSkipped('Test fixtures not available: $fixtureLoadError');
          return;
        }

        final pid = testProjectId = await DB.instance.addProject(
          'Manual edit reprojection',
          'face',
          DateTime.now().millisecondsSinceEpoch,
        );
        final photo = await _Photo.importAndStabilize(pid);

        // The edit on top of the automatic result: 10 px down, 2 degrees
        // more tilt, 5% larger. Saved exactly as the page saves it.
        final auto = await photo.storedTransform();
        final edit = (
          rotationDegrees: auto.rotationDegrees + 2.0,
          scaleFactor: auto.scaleFactor * 1.05,
          translateX: auto.translateX,
          translateY: auto.translateY + 10.0,
        );
        await photo.saveManualEdit(edit);
        final savedSettings = photo.settings;

        Future<void> expectCarriedOver(String what) async {
          final settings = photo.settings;
          final expected = ManualTransformReprojection.reproject(
            rotationDegrees: edit.rotationDegrees,
            scaleFactor: edit.scaleFactor,
            translateX: edit.translateX,
            translateY: edit.translateY,
            savedCanvasWidth: _canvas(savedSettings).$1,
            savedCanvasHeight: _canvas(savedSettings).$2,
            savedEyeOffsetX: savedSettings.eyeOffsetX,
            savedEyeOffsetY: savedSettings.eyeOffsetY,
            canvasWidth: _canvas(settings).$1,
            canvasHeight: _canvas(settings).$2,
            eyeOffsetX: settings.eyeOffsetX,
            eyeOffsetY: settings.eyeOffsetY,
          )!;
          _expectTransform(
            await photo.storedTransform(),
            expected,
            'after $what',
          );
          expect(
            await (await photo.stabilizedFile()).exists(),
            isTrue,
            reason: 'after $what the stabilized photo is written',
          );
          // The row the service rendered from: still there, still holding the
          // saved values and the settings they were saved under. The
          // re-projection happens at render time, not in the row.
          final row = await DB.instance.getTransformCache(photo.manualKey());
          expect(row, isNotNull, reason: 'after $what the manual row is kept');
          expect(row!.eyeOffsetX, savedSettings.eyeOffsetX);
          expect(row.eyeOffsetY, savedSettings.eyeOffsetY);
          expect(row.canvasWidth, _canvas(savedSettings).$1);
          expect(row.canvasHeight, _canvas(savedSettings).$2);
          expect(row.scaleFactor, closeTo(edit.scaleFactor, 1e-9));
          expect(row.translateY, closeTo(edit.translateY, 1e-9));
        }

        // "This will re-stabilize all photos." Each change is what the
        // settings page does on save, minus the UI.
        await photo.change(
          'the eye position',
          () => photo.moveEyes(0.02, 0.04),
        );
        await expectCarriedOver('the eye position change');

        await photo.change('the aspect ratio', photo.toggleAspectRatio);
        await expectCarriedOver('the aspect ratio change');

        await photo.change('a custom canvas', () => photo.setCustomCanvas());
        await expectCarriedOver('the custom canvas change');

        // Everything back as it was: the edit is reproduced exactly, with no
        // drift from having been carried through three other settings.
        await photo.change('the original settings', () async {
          await photo.moveEyes(-0.02, -0.04);
          await photo.toggleAspectRatio();
          await photo.setResolution(savedSettings.resolution);
        });
        expect(photo.settings.eyeOffsetX, savedSettings.eyeOffsetX);
        expect(photo.settings.aspectRatio, savedSettings.aspectRatio);
        expect(_canvas(photo.settings), _canvas(savedSettings));
        _expectTransform(
          await photo.storedTransform(),
          edit,
          'with the original settings restored',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    testWidgets('an edit saved by 2.7.0 or 2.8.0 is still found, re-keyed, and '
        'carried across the next eye position change', (tester) async {
      await launchApp(tester);
      if (fixturesUnavailable) {
        markTestSkipped('Test fixtures not available: $fixtureLoadError');
        return;
      }

      final pid = testProjectId = await DB.instance.addProject(
        'Manual edit legacy row',
        'face',
        DateTime.now().millisecondsSinceEpoch,
      );
      final photo = await _Photo.importAndStabilize(pid);
      final auto = await photo.storedTransform();
      final edit = (
        rotationDegrees: auto.rotationDegrees - 1.5,
        scaleFactor: auto.scaleFactor * 0.9,
        translateX: auto.translateX + 12.0,
        translateY: auto.translateY - 8.0,
      );
      final savedSettings = photo.settings;
      final legacyKey = await photo.plantLegacyManualRow(edit);
      expect(
        await DB.instance.getTransformCache(photo.manualKey()),
        isNull,
        reason: 'nothing under the current key before the first run',
      );

      // Unchanged settings: the legacy key still matches and the edit is
      // rendered as saved.
      await photo.change('nothing', () async {});
      _expectTransform(
        await photo.storedTransform(),
        edit,
        'on the first run after upgrading',
      );
      final rekeyed = await DB.instance.getTransformCache(photo.manualKey());
      expect(rekeyed, isNotNull, reason: 'the row is re-keyed on its hit');
      expect(rekeyed!.eyeOffsetX, savedSettings.eyeOffsetX);
      expect(rekeyed.eyeOffsetY, savedSettings.eyeOffsetY);
      expect(rekeyed.scaleFactor, closeTo(edit.scaleFactor, 1e-9));
      expect(rekeyed.translateX, closeTo(edit.translateX, 1e-9));
      expect(
        await DB.instance.getTransformCache(legacyKey),
        isNotNull,
        reason: 'the legacy row is left in place',
      );

      // The eye position changes: the legacy key no longer matches, the
      // re-keyed row does, and the edit is carried over.
      await photo.change('the eye position', () => photo.moveEyes(0.03, -0.02));
      final settings = photo.settings;
      final expected = ManualTransformReprojection.reproject(
        rotationDegrees: edit.rotationDegrees,
        scaleFactor: edit.scaleFactor,
        translateX: edit.translateX,
        translateY: edit.translateY,
        savedCanvasWidth: _canvas(savedSettings).$1,
        savedCanvasHeight: _canvas(savedSettings).$2,
        savedEyeOffsetX: savedSettings.eyeOffsetX,
        savedEyeOffsetY: savedSettings.eyeOffsetY,
        canvasWidth: _canvas(settings).$1,
        canvasHeight: _canvas(settings).$2,
        eyeOffsetX: settings.eyeOffsetX,
        eyeOffsetY: settings.eyeOffsetY,
      )!;
      _expectTransform(
        await photo.storedTransform(),
        expected,
        'after the eye position change',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}

/// One imported face photo in a project, with the settings changes the
/// settings pages make and the reads the assertions need.
class _Photo {
  _Photo._(this.pid, this.timestamp, this.rawPath, this.fingerprint);

  final int pid;
  final String timestamp;
  final String rawPath;
  final String fingerprint;
  late StabilizationSettings settings;

  static Future<_Photo> importAndStabilize(int pid) async {
    // Stabilization only; no FFmpeg here.
    await SettingsUtil.setAutoCompileVideo(pid.toString(), false);
    await _import(await getSampleFacePathAsync(1), pid);
    final row = (await DB.instance.getPhotosByProjectID(pid)).single;
    final ts = row['timestamp'] as String;
    final rawPath = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
      ts,
      pid,
      fileExtension: row['fileExtension'],
    );
    final fingerprint = row['fingerprint'] as String?;
    expect(fingerprint, isNotNull, reason: 'import stores a fingerprint');
    final photo = _Photo._(pid, ts, rawPath, fingerprint!);
    photo.settings = await StabilizationSettings.load(pid);
    await _runService(pid, 'the automatic run');
    return photo;
  }

  String get _column =>
      DB.instance.getStabilizedColumn(settings.projectOrientation);

  Future<ManualTransform> storedTransform() async {
    final row = (await DB.instance.getPhotoByTimestamp(timestamp, pid))!;
    double read(String name) => (row['$_column$name'] as num).toDouble();
    return (
      rotationDegrees: read('RotationDegrees'),
      scaleFactor: read('ScaleFactor'),
      translateX: read('TranslateX'),
      translateY: read('TranslateY'),
    );
  }

  Future<File> stabilizedFile() async {
    final path = await StabUtils.getStabilizedImagePath(
      rawPath,
      pid,
      settings.projectOrientation,
    );
    return File(p.setExtension(path, '.png'));
  }

  /// What the Manual Stabilization page's save does beyond writing the
  /// stabilized file: the transform cache row the next re-stabilization uses.
  Future<void> saveManualEdit(ManualTransform edit) async {
    final editor = FaceStabilizer(pid, () {});
    await editor.init();
    try {
      await editor.persistManualTransform(
        rawPhotoPath: rawPath,
        timestamp: timestamp,
        translateX: edit.translateX,
        translateY: edit.translateY,
        rotationDegrees: edit.rotationDegrees,
        scaleFactor: edit.scaleFactor,
      );
    } finally {
      await editor.dispose();
    }
  }

  String manualKey() => TransformCacheKey.buildCacheKey(
    projectId: pid,
    fingerprint: fingerprint,
    projectType: 'face',
    modelVersion: StabUtils.detectorModelVersionForProjectType('face'),
    settingsHash: TransformCacheKey.buildManualReuseHash(
      projectOrientation: settings.projectOrientation,
    ),
    scope: TransformCacheKey.manualScope,
  );

  /// Writes a manual row the way 2.7.0 and 2.8.0 did: keyed by aspect ratio,
  /// eye offsets and orientation, with no eye offsets stored on the row.
  Future<String> plantLegacyManualRow(ManualTransform edit) async {
    final settingsHash = TransformCacheKey.buildLegacyManualReuseHash(
      aspectRatio: settings.aspectRatio,
      eyeOffsetX: settings.eyeOffsetX,
      eyeOffsetY: settings.eyeOffsetY,
      projectOrientation: settings.projectOrientation,
    );
    final cacheKey = TransformCacheKey.buildCacheKey(
      projectId: pid,
      fingerprint: fingerprint,
      projectType: 'face',
      modelVersion: StabUtils.detectorModelVersionForProjectType('face'),
      settingsHash: settingsHash,
      scope: TransformCacheKey.manualScope,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final canvas = _canvas(settings);
    await DB.instance.writeTransformCache(
      TransformCacheEntry(
        cacheKey: cacheKey,
        projectId: pid,
        fingerprint: fingerprint,
        projectType: 'face',
        modelVersion: StabUtils.detectorModelVersionForProjectType('face'),
        transformAlgorithmVersion: TransformCacheKey.transformAlgorithmVersion,
        settingsHash: settingsHash,
        scope: TransformCacheKey.manualScope,
        sourceOrientation: 'original',
        canvasWidth: canvas.$1,
        canvasHeight: canvas.$2,
        translateX: edit.translateX,
        translateY: edit.translateY,
        rotationDegrees: edit.rotationDegrees,
        scaleFactor: edit.scaleFactor,
        exampleTimestamp: timestamp,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await DB.instance.clearTransformCacheForFingerprint(
      pid,
      fingerprint,
      scope: TransformCacheKey.defaultScope,
    );
    return cacheKey;
  }

  /// Applies [edit], queues every photo again as the settings pages do, and
  /// runs the service.
  Future<void> change(String what, Future<void> Function() edit) async {
    await edit();
    settings = await StabilizationSettings.load(pid);
    await DB.instance.resetStabilizationStatusForProject(
      pid,
      settings.projectOrientation,
    );
    expect(
      (await StabUtils.getUnstabilizedPhotos(pid)).length,
      1,
      reason: 'changing $what queues the photo again',
    );
    await _runService(pid, 'the re-stabilization after changing $what');
  }

  Future<void> moveEyes(double dx, double dy) async {
    final suffix = settings.projectOrientation == 'landscape'
        ? 'Landscape'
        : 'Portrait';
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
  }

  Future<void> toggleAspectRatio() async {
    await DB.instance.setSettingByTitle(
      'aspect_ratio',
      settings.aspectRatio == '4:3' ? '16:9' : '4:3',
      pid.toString(),
    );
  }

  /// A custom canvas whose width and height differ from the preset's by
  /// different factors, which the proportional rescale used to reject.
  Future<void> setCustomCanvas() async {
    final isLandscape = settings.projectOrientation == 'landscape';
    await setResolution(isLandscape ? '2000x1500' : '1500x2000');
  }

  Future<void> setResolution(String resolution) async {
    await DB.instance.setSettingByTitle(
      'video_resolution',
      resolution,
      pid.toString(),
    );
  }
}

(int, int) _canvas(StabilizationSettings settings) {
  return StabUtils.getOutputDimensions(
    settings.resolution,
    settings.aspectRatio,
    settings.projectOrientation,
  )!;
}

void _expectTransform(
  ManualTransform actual,
  ManualTransform expected,
  String when,
) {
  const tolerance = 1e-6;
  final detail = 'stored $actual, expected $expected';
  expect(
    actual.rotationDegrees,
    closeTo(expected.rotationDegrees, tolerance),
    reason: '$when, rotation differs: $detail',
  );
  expect(
    actual.scaleFactor,
    closeTo(expected.scaleFactor, tolerance),
    reason: '$when, scale differs: $detail',
  );
  expect(
    actual.translateX,
    closeTo(expected.translateX, tolerance),
    reason: '$when, horizontal offset differs: $detail',
  );
  expect(
    actual.translateY,
    closeTo(expected.translateY, tolerance),
    reason: '$when, vertical offset differs: $detail',
  );
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

/// Runs the stabilization service as the app does. On failure reports its
/// last error or cancellation state and the tail of the app log.
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
