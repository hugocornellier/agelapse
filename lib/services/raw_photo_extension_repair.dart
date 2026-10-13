import 'dart:io';

import 'package:path/path.dart' as path;

import '../utils/dir_utils.dart';
import '../utils/settings_utils.dart';
import 'database_helper.dart';
import 'log_service.dart';

/// Renames raw photos whose on-disk extension differs only in case from the
/// lower-case extension the database records for them (#41).
///
/// Before 2.8.0 an import copied the picked file to
/// `<timestamp><extension as picked>` but recorded the extension lower-cased,
/// so `IMG_0001.HEIC` became `1700000000000.HEIC` on disk and `.heic` in the
/// database. Every later reader rebuilds the path from the database, which is
/// fine on the case-insensitive file systems of macOS and Windows but not on
/// Linux, Android or iOS: there the gallery preview showed black, stabilization
/// failed and manual stabilization reported "Could not load photo file".
///
/// Imports now save the lower-case extension; this repair runs at startup for
/// files older versions left behind. A renamed photo has never been stabilized
/// (nothing could open it), so its stabilization state is reset and the next
/// pass picks it up.
class RawPhotoExtensionRepair {
  /// Repairs every project. Returns the number of files renamed. Never throws.
  static Future<int> repairAllProjects() async {
    var renamed = 0;
    try {
      for (final project in await DB.instance.getAllProjects()) {
        renamed += await repairProject(project['id'] as int);
      }
      if (renamed > 0) {
        LogService.instance.log(
          '[Repair] Renamed $renamed raw photo(s) to a lower-case extension '
          'and queued them for stabilization',
        );
      }
    } catch (e) {
      LogService.instance.log('[Repair] Raw photo extension repair failed: $e');
    }
    return renamed;
  }

  /// Repairs one project's `photos_raw` directory and resets the stabilization
  /// state of every photo it renamed. Returns the number of files renamed.
  static Future<int> repairProject(int projectId) async {
    final dir = Directory(await DirUtils.getRawPhotoDirPath(projectId));
    final renamed = await renameUpperCaseExtensions(dir);
    if (renamed.isEmpty) return 0;

    final orientation = await SettingsUtil.loadProjectOrientation(
      projectId.toString(),
    );
    for (final file in renamed) {
      await DB.instance.resetPhotoStabilizationState(
        timestamp: path.basenameWithoutExtension(file),
        projectId: projectId,
        orientation: orientation,
      );
    }
    return renamed.length;
  }

  /// The file-system half: every file directly inside [dir] whose extension
  /// contains an upper-case letter is renamed to the lower-case extension,
  /// unless a file of that name already exists (which is also what a
  /// case-insensitive file system reports for the file itself, so this is a
  /// no-op there). Returns the new paths of the renamed files.
  static Future<List<String>> renameUpperCaseExtensions(Directory dir) async {
    if (!await dir.exists()) return const [];

    final renamed = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final ext = path.extension(entity.path);
      final lower = ext.toLowerCase();
      if (ext == lower) continue;

      final target = path.join(
        dir.path,
        '${path.basenameWithoutExtension(entity.path)}$lower',
      );
      if (await File(target).exists()) continue;

      try {
        await entity.rename(target);
        renamed.add(target);
      } catch (e) {
        LogService.instance.log(
          '[Repair] Could not rename ${entity.path} to $target: $e',
        );
      }
    }
    return renamed;
  }
}
