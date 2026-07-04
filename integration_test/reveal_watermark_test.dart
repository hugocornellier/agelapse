import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/database_import_ffi.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

/// Proves the gallery reveal watermark in
/// [DB.getStabilizedAndFailedPhotosByProjectID]:
///   1. reveals strictly oldest -> newest, so a photo whose DB flag is written
///      out of order (parallel fast path) never appears before an earlier
///      still-pending photo;
///   2. never retracts an already-revealed photo when a middle photo later goes
///      pending (single-photo re-stab / retry) — the watermark is monotonic;
///   3. re-gates from scratch after a full re-stabilization restart
///      (resolution change), which is the reported "out of order after changing
///      resolution" case;
///   4. clamps on photo deletion, so a stale-high watermark can't outlive the
///      photos that justified it: deleting the newest photos pulls the bound
///      down (without retracting survivors), and clearing the project then
///      re-importing an OLDER set re-gates from scratch instead of revealing
///      the whole re-import ungated below the old bound.
///
/// Isolated DB test (no app.main()) so the launched app can't auto-stabilize
/// the controlled fixtures. Run:
///   flutter test integration_test/reveal_watermark_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  const String orientation = 'landscape';

  setUpAll(() async {
    initDatabase();
    await DB.instance.createTablesIfNotExist();
  });

  setUp(_cleanupTestData);

  Future<List<String>> revealed(int projectId) async {
    final rows = await DB.instance
        .getStabilizedAndFailedPhotosByProjectID(projectId, orientation);
    return rows.map((r) => r['timestamp'] as String).toList();
  }

  Future<void> stabilize(int projectId, String ts) => DB.instance
      .setPhotoStabilized(ts, projectId, orientation, '16:9', '1080p', 0, 0);

  test('reveal watermark: ordered, no-retraction, reset re-gates', () async {
    final int projectId = await DB.instance.addProject('Reveal WM', 'face', 1);
    for (final ts in ['100', '200', '300', '400', '500']) {
      await DB.instance
          .addPhoto(ts, projectId, 'jpg', 1000, 'p.jpg', orientation);
    }

    // 1) Out-of-order completion is gated: 100,200 done and 400 done, but 300
    //    still pending -> 400 must NOT be revealed yet.
    await stabilize(projectId, '100');
    await stabilize(projectId, '200');
    await stabilize(projectId, '400');
    expect(await revealed(projectId), ['100', '200'],
        reason: 'a later photo must not appear before an earlier pending one');

    // 2) Filling the gap advances the prefix (500 still pending).
    await stabilize(projectId, '300');
    expect(await revealed(projectId), ['100', '200', '300', '400']);

    // 3) Complete the run, then re-stab a MIDDLE photo: 300 hides (pending) but
    //    400/500 must NOT retract (monotonic watermark).
    await stabilize(projectId, '500');
    expect(await revealed(projectId), ['100', '200', '300', '400', '500']);
    await DB.instance
        .resetStabilizedColumnByTimestamp(orientation, '300', projectId);
    expect(await revealed(projectId), ['100', '200', '400', '500'],
        reason: '300 hides but its later siblings must not retract');

    // 4) Full restart (resolution change) resets the watermark -> a fresh run
    //    re-gates from scratch: 400 done out of order while 100 pending shows
    //    nothing, then recovers strictly in order.
    await DB.instance
        .resetStabilizationStatusForProject(projectId, orientation);
    await stabilize(projectId, '400');
    expect(await revealed(projectId), isEmpty,
        reason: 'after a full reset the watermark must re-gate from scratch');
    await stabilize(projectId, '100');
    await stabilize(projectId, '200');
    await stabilize(projectId, '300');
    expect(await revealed(projectId), ['100', '200', '300', '400']);
  });

  test('deletion clamps watermark: no retraction, reimport-older re-gates',
      () async {
    final int projectId =
        await DB.instance.addProject('Reveal WM del', 'face', 1);
    for (final ts in ['100', '200', '300', '400', '500']) {
      await DB.instance
          .addPhoto(ts, projectId, 'jpg', 1000, 'p.jpg', orientation);
      await stabilize(projectId, ts);
    }
    expect(await revealed(projectId), ['100', '200', '300', '400', '500']);

    // 1) Deleting the newest photo clamps the stale-high watermark to one past
    //    the new max WITHOUT retracting: 300 is mid-sequence pending (retry)
    //    and 400 must stay revealed.
    await DB.instance
        .resetStabilizedColumnByTimestamp(orientation, '300', projectId);
    await DB.instance.softDeletePhoto(500, projectId);
    expect(await revealed(projectId), ['100', '200', '400'],
        reason: 'clamp must not retract 400 while 300 is pending');

    // 2) Clearing the project drops the watermark entirely, so re-importing an
    //    OLDER photo set re-gates from scratch: 30 stabilized out of order
    //    while 10 pending must stay hidden, then reveal strictly in order.
    for (final ts in ['100', '200', '300', '400']) {
      await DB.instance.softDeletePhoto(int.parse(ts), projectId);
    }
    for (final ts in ['10', '20', '30']) {
      await DB.instance
          .addPhoto(ts, projectId, 'jpg', 1000, 'p.jpg', orientation);
    }
    await stabilize(projectId, '30');
    expect(await revealed(projectId), isEmpty,
        reason: 'old watermark must not leak onto a re-imported older set');
    await stabilize(projectId, '10');
    expect(await revealed(projectId), ['10']);
    await stabilize(projectId, '20');
    expect(await revealed(projectId), ['10', '20', '30']);
  });
}

Future<void> _cleanupTestData() async {
  try {
    await DB.instance.deleteAllPhotos();
    final projects = await DB.instance.getAllProjects();
    for (final project in projects) {
      await DB.instance.deleteProject(project['id'] as int);
    }
  } catch (_) {
    // Ignore cleanup errors.
  }
}
