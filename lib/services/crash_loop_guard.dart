import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

import '../utils/dir_utils.dart';
import '../utils/platform_utils.dart';
import '../utils/test_mode.dart' as test_config;
import 'async_mutex.dart';
import 'cancellation_token.dart';
import 'database_helper.dart';
import 'log_service.dart';

/// Where [CrashLoopGuard] keeps its notes, behind an interface so its rules
/// can be unit tested without the file system.
abstract class CrashGuardStore {
  /// The saved notes, or null when there are none.
  Future<String?> read();

  /// Replaces the saved notes. When the returned future completes, the notes
  /// must have reached the operating system, so they outlive the app process.
  Future<void> write(String contents);
}

/// Stops work that crashes the app from starting again on every launch.
///
/// When a project opens, the app picks up unfinished work by itself: it
/// stabilizes new photos, then compiles the video if one is needed. Work
/// counts as unfinished until it succeeds, so work that kills the app (a
/// native crash, or the OS killing it for memory) used to run again on the
/// next launch and crash again, on every launch (#15, #42).
///
/// Before that work starts, the guard writes a note. Once the work ends in
/// any way the app survives, the guard removes the note. A note still there
/// at launch means the app died during that work. The first time is let go,
/// because swiping the app away or the OS killing it in the background
/// leaves a note too. Once it has happened [deathsBeforeStopping] times:
/// - Compiles: auto-compile is paused for the project, as if it were turned
///   off in Settings, until a compile finishes or the app is updated. The
///   video page says why and still offers Compile Video. Only on Android and
///   iOS, where FFmpeg runs inside the app. On desktop it is a separate
///   process, so a compile can fail without taking the app down.
/// - Photos: the photo is marked as failed, like any photo stabilization
///   gives up on, and the rest carry on. Once the app has died on a photo,
///   that photo is never stabilized alongside others in the parallel fast
///   path, so a second death points at that photo alone.
///
/// The notes live in a small file rather than the database: a photo's note
/// is written before and after every photo, and a file write is much cheaper
/// than a database transaction. Each note is written before its work starts,
/// so a crash can't outrun it.
///
/// Nothing here throws into callers. If the notes can't be read or written,
/// the work still runs and the failure is logged under `[CrashGuard]`.
/// Inactive in test mode.
class CrashLoopGuard {
  CrashLoopGuard._()
    : this.forTesting(
        store: _FileCrashGuardStore(),
        markPhotoFailed: (projectId, timestamp) =>
            DB.instance.setPhotoStabFailed(timestamp, projectId),
        appVersion: _installedAppVersion,
      );

  @visibleForTesting
  CrashLoopGuard.forTesting({
    required this._store,
    required this._markPhotoFailed,
    required this._appVersion,
    bool? active,
    bool? guardCompiles,
  }) : _activeOverride = active,
       _guardCompilesOverride = guardCompiles;

  static CrashLoopGuard _instance = CrashLoopGuard._();

  /// The guard every stabilization and compile goes through.
  static CrashLoopGuard get instance => _instance;

  /// Replaces [instance], so a test can switch on a guard with known notes.
  @visibleForTesting
  static set instance(CrashLoopGuard guard) => _instance = guard;

  /// How many times the app may die during the same work before the guard
  /// stops that work from starting by itself.
  static const int deathsBeforeStopping = 2;

  final CrashGuardStore _store;
  final Future<void> Function(int projectId, String timestamp) _markPhotoFailed;
  final Future<String> Function() _appVersion;
  final bool? _activeOverride;
  final bool? _guardCompilesOverride;

  bool get _active => _activeOverride ?? !test_config.isTestMode;
  bool get _guardsCompiles => _guardCompilesOverride ?? isMobile;

  final Map<int, _ProjectNotes> _notes = {};
  final Set<int> _pausedCompiles = {};
  String? _currentVersion;
  Future<void>? _started;

  final AsyncMutex _writeLock = AsyncMutex();
  int _changes = 0;
  int _changesWritten = 0;

  /// Reads the notes the last launch left and acts on them. Call once at
  /// startup, before anything can stabilize or compile. Idempotent, never
  /// throws.
  ///
  /// The other methods call this themselves, so a note written early can
  /// never replace the last launch's notes before they are read.
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    if (!_active) return;
    try {
      _currentVersion = await _appVersion();
    } catch (e) {
      _log('Could not read the app version: $e');
    }
    _notes.addAll(await _readNotes());

    var changed = false;
    for (final MapEntry(key: projectId, value: notes)
        in _notes.entries.toList()) {
      changed |= await _applyLastLaunch(projectId, notes);
    }
    _notes.removeWhere((_, notes) => notes.isEmpty);
    if (changed) await _persist();
  }

  /// Acts on the notes [projectId] had when the app last stopped. Returns
  /// whether they changed.
  Future<bool> _applyLastLaunch(int projectId, _ProjectNotes notes) async {
    var changed = false;

    if (notes.compilesUnfinished > 0 &&
        _currentVersion != null &&
        notes.compileAppVersion != _currentVersion) {
      _log(
        'Project $projectId: the app was updated since its last unfinished '
        'compile, so auto-compile starts afresh',
      );
      notes.compilesUnfinished = 0;
      notes.compileAppVersion = null;
      changed = true;
    }
    if (notes.compilesUnfinished >= deathsBeforeStopping) {
      _pausedCompiles.add(projectId);
      _log(
        'Project $projectId: the app closed during its last '
        '${notes.compilesUnfinished} compiles; auto-compile is paused until '
        'a compile finishes',
      );
    } else if (notes.compilesUnfinished > 0) {
      _log(
        'Project $projectId: the last compile did not finish; auto-compile '
        'will try once more',
      );
    }

    for (final timestamp in notes.photosInFlight.keys) {
      final deaths = (notes.photoDeaths[timestamp] ?? 0) + 1;
      // Kept after the photo is marked failed: if it is ever retried, it
      // runs alone, and one more death marks it again.
      notes.photoDeaths[timestamp] = deaths;
      if (deaths < deathsBeforeStopping) {
        _log(
          'Project $projectId: the app closed while stabilizing photo '
          '$timestamp; it will be stabilized on its own next time',
        );
        continue;
      }
      _log(
        'Project $projectId: the app closed while stabilizing photo '
        '$timestamp ($deaths times); marking it failed',
      );
      try {
        await _markPhotoFailed(projectId, timestamp);
      } catch (e) {
        _log('Could not mark photo $timestamp failed: $e');
      }
    }
    if (notes.photosInFlight.isNotEmpty) {
      notes.photosInFlight.clear();
      changed = true;
    }
    return changed;
  }

  /// Whether auto-compile is paused for [projectId] because the app kept
  /// closing during its compiles.
  Future<bool> isAutoCompilePaused(int projectId) async {
    if (!_active || !_guardsCompiles) return false;
    await start();
    return _pausedCompiles.contains(projectId);
  }

  /// Runs one compile of [projectId] with a note around it. Whatever the
  /// outcome, a compile the app survives clears the note and resumes
  /// auto-compile.
  Future<T> runCompile<T>(int projectId, Future<T> Function() compile) async {
    if (!_active || !_guardsCompiles) return compile();
    await start();
    final notes = _notesFor(projectId);
    notes.compilesUnfinished++;
    notes.compileAppVersion = _currentVersion;
    await _persist();
    try {
      return await compile();
    } finally {
      final notes = _notesFor(projectId);
      notes.compilesUnfinished = 0;
      notes.compileAppVersion = null;
      _dropIfEmpty(projectId);
      if (_pausedCompiles.remove(projectId)) {
        _log('Project $projectId: a compile finished; auto-compile resumed');
      }
      await _persist();
    }
  }

  /// Whether the app has died while stabilizing this photo before, so it
  /// must not be stabilized alongside other photos.
  Future<bool> mustStabilizeAlone(int projectId, String? timestamp) async {
    if (!_active || timestamp == null) return false;
    await start();
    return _notes[projectId]?.photoDeaths.containsKey(timestamp) ?? false;
  }

  /// Runs [stabilize] for one photo with a note around it.
  ///
  /// [settled] says whether the photo got a result the app survived: a
  /// success or a failure. A photo that settles is cleared of earlier
  /// deaths. One that didn't (cancelled, or left for a later step) keeps
  /// them. A photo that throws has failed, so it settles too, unless it was
  /// cancelled.
  Future<T> runPhoto<T>(
    int projectId,
    String? timestamp,
    Future<T> Function() stabilize, {
    required bool Function(T result) settled,
  }) async {
    if (!_active || timestamp == null) return stabilize();
    await start();
    final inFlight = _notesFor(projectId).photosInFlight;
    inFlight[timestamp] = (inFlight[timestamp] ?? 0) + 1;
    await _persist();
    var didSettle = false;
    try {
      final result = await stabilize();
      didSettle = settled(result);
      return result;
    } on CancelledException {
      rethrow;
    } catch (_) {
      didSettle = true;
      rethrow;
    } finally {
      final notes = _notesFor(projectId);
      final runs = (notes.photosInFlight[timestamp] ?? 1) - 1;
      if (runs > 0) {
        notes.photosInFlight[timestamp] = runs;
      } else {
        notes.photosInFlight.remove(timestamp);
      }
      if (didSettle) notes.photoDeaths.remove(timestamp);
      _dropIfEmpty(projectId);
      await _persist();
    }
  }

  _ProjectNotes _notesFor(int projectId) =>
      _notes.putIfAbsent(projectId, _ProjectNotes.new);

  void _dropIfEmpty(int projectId) {
    if (_notes[projectId]?.isEmpty ?? false) _notes.remove(projectId);
  }

  /// Saves the notes. Returns once a write that includes every change made
  /// before the call has finished. Writes run one at a time, and one write
  /// covers every change made while it waited.
  Future<void> _persist() async {
    final wanted = ++_changes;
    await _writeLock.protect(() async {
      if (_changesWritten >= wanted) return;
      final upTo = _changes;
      try {
        await _store.write(_encode());
        _changesWritten = upTo;
      } catch (e) {
        _log('Could not save notes: $e');
      }
    });
  }

  String _encode() => jsonEncode({
    'version': 1,
    'projects': {
      for (final MapEntry(key: projectId, value: notes) in _notes.entries)
        if (!notes.isEmpty) '$projectId': notes.toJson(),
    },
  });

  Future<Map<int, _ProjectNotes>> _readNotes() async {
    final String? contents;
    try {
      contents = await _store.read();
    } catch (e) {
      _log('Could not read notes: $e');
      return {};
    }
    if (contents == null || contents.trim().isEmpty) return {};
    try {
      final projects = (jsonDecode(contents) as Map)['projects'] as Map;
      final result = <int, _ProjectNotes>{};
      for (final MapEntry(:key, :value) in projects.entries) {
        final projectId = int.tryParse('$key');
        if (projectId == null || value is! Map) continue;
        result[projectId] = _ProjectNotes.fromJson(value);
      }
      return result;
    } catch (e) {
      _log('Ignoring unreadable notes: $e');
      return {};
    }
  }

  static Future<String> _installedAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  static void _log(String message) =>
      LogService.instance.log('[CrashGuard] $message');
}

/// What the guard knows about one project's unfinished work.
class _ProjectNotes {
  _ProjectNotes();

  /// Compiles started and never finished, in a row.
  int compilesUnfinished = 0;

  /// The app version that started those compiles.
  String? compileAppVersion;

  /// Photos being stabilized right now, with how many runs have each.
  final Map<String, int> photosInFlight = {};

  /// Photos the app has died on, with how many times.
  final Map<String, int> photoDeaths = {};

  bool get isEmpty =>
      compilesUnfinished == 0 &&
      compileAppVersion == null &&
      photosInFlight.isEmpty &&
      photoDeaths.isEmpty;

  Map<String, Object?> toJson() => {
    if (compilesUnfinished > 0) 'compilesUnfinished': compilesUnfinished,
    if (compileAppVersion != null) 'compileAppVersion': compileAppVersion,
    if (photosInFlight.isNotEmpty)
      'photosInFlight': photosInFlight.keys.toList(),
    if (photoDeaths.isNotEmpty) 'photoDeaths': photoDeaths,
  };

  /// Reads what [toJson] wrote, skipping anything malformed.
  factory _ProjectNotes.fromJson(Map<dynamic, dynamic> json) {
    final notes = _ProjectNotes();
    final unfinished = json['compilesUnfinished'];
    if (unfinished is int && unfinished > 0) {
      notes.compilesUnfinished = unfinished;
    }
    final version = json['compileAppVersion'];
    if (version is String) notes.compileAppVersion = version;
    final inFlight = json['photosInFlight'];
    if (inFlight is List) {
      for (final timestamp in inFlight) {
        if (timestamp is String) notes.photosInFlight[timestamp] = 1;
      }
    }
    final deaths = json['photoDeaths'];
    if (deaths is Map) {
      for (final MapEntry(:key, :value) in deaths.entries) {
        if (key is String && value is int && value > 0) {
          notes.photoDeaths[key] = value;
        }
      }
    }
    return notes;
  }
}

/// Keeps the notes in `crash_guard.json` in the app's data folder.
class _FileCrashGuardStore implements CrashGuardStore {
  static const String _fileName = 'crash_guard.json';

  String? _path;

  Future<File> _file() async => File(
    _path ??= path.join(await DirUtils.getAppDocumentsDirPath(), _fileName),
  );

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Writes a temporary file and renames it over the notes, so a crash
  /// mid-write leaves the previous notes instead of a half-written file.
  @override
  Future<void> write(String contents) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents);
    await temp.rename(file.path);
  }
}
