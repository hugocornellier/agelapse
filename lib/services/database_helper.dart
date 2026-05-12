import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/face_detection_cache_result.dart';
import '../models/setting_model.dart';
import '../models/transform_cache_entry.dart';
import 'database_import_ffi.dart';
import 'package:path/path.dart';

import '../utils/dir_utils.dart';
import '../utils/notification_util.dart';
import '../utils/settings_utils.dart';
import '../utils/test_mode.dart' as test_config;
import 'log_service.dart';

class DB {
  static final DB _instance = DB._internal();
  Database? _database;

  static const int _version = 1;
  static const String _prodDbName = "Settings.db";
  static const String _testDbName = "Settings_test.db";
  static String get _dbName =>
      test_config.isTestMode ? _testDbName : _prodDbName;
  static const String settingTable = "Setting";
  static const String photoTable = "Photos";
  static const String projectTable = "Projects";
  static const String videoTable = "Videos";
  static const String customFontTable = "CustomFonts";
  static const String deletedLinkedSourcesTable = "DeletedLinkedSources";
  static const String faceDetectionCacheTable = "FaceDetectionCache";
  static const String transformCacheTable = "TransformCache";

  /// Read-only SQL view exposing only active (non-soft-deleted) rows in
  /// [photoTable]. Every read query against photos that should hide trashed
  /// rows targets this view instead of [photoTable] — so forgetting the
  /// `deletedAt IS NULL` predicate is no longer possible at the call site.
  ///
  /// Writes (INSERT / UPDATE / DELETE) and trash-management reads
  /// (`deletedAt IS NOT NULL`) stay on [photoTable] directly. SQLite views
  /// are read-only by default, so any accidental write attempt fails loudly
  /// at the storage layer rather than silently corrupting state.
  static const String photoActiveView = "photos_active";

  static const String _photoWhereClause = 'timestamp = ? AND projectID = ?';
  static const String _orderByTimestamp = 'CAST(timestamp AS INTEGER)';

  /// Default retention window for soft-deleted photos before permanent
  /// purge (mirrors iOS Photos "Recently Deleted").
  static const int recentlyDeletedRetentionDays = 30;

  DB._internal();

  static DB get instance => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final dbPath = join(await getDatabasesPath(), _dbName);
      return await openDatabase(dbPath, version: _version);
    } else {
      final base = await DirUtils.getAppDocumentsDirPath();
      final dbPath = join(base, _dbName);
      return await openDatabase(dbPath, version: _version);
    }
  }

  Future<void> createTablesIfNotExist() async {
    final db = await database;
    List<String> existingTables = (await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ?',
      whereArgs: ['table'],
    ))
        .map((row) => row['name'] as String)
        .toList();

    Map<String, String> tablesToCreate = {
      // NOTE: 'timestamp' is TEXT but stores milliseconds-since-epoch integers.
      // TEXT sort is WRONG across the 12→13 digit boundary (pre/post Sept 2001).
      // Always use CAST(timestamp AS INTEGER) in ORDER BY clauses.
      photoTable: "CREATE TABLE $photoTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "timestamp TEXT NOT NULL, "
          "projectID INTEGER NOT NULL, "
          "fileExtension TEXT NOT NULL, "
          "originalFilename TEXT NOT NULL, "
          "imageLength INTEGER NOT NULL, "
          "fingerprint TEXT, "
          "originalOrientation TEXT, "
          "stabilizedPortrait INTEGER NOT NULL, "
          "stabilizedPortraitAspectRatio TEXT, "
          "stabilizedPortraitResolution TEXT, "
          "stabilizedPortraitOffsetX TEXT, "
          "stabilizedPortraitOffsetY TEXT, "
          "stabilizedLandscape INTEGER NOT NULL, "
          "stabilizedLandscapeAspectRatio TEXT, "
          "stabilizedLandscapeResolution TEXT, "
          "stabilizedLandscapeOffsetX TEXT, "
          "stabilizedLandscapeOffsetY TEXT, "
          "stabFailed INTEGER NOT NULL, "
          "noFacesFound INTEGER NOT NULL, "
          "favorite INTEGER NOT NULL, "
          "captureOffsetMinutes INTEGER, "
          "tempPath TEXT, "
          "deletedAt INTEGER"
          ");",
      settingTable: "CREATE TABLE $settingTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "title TEXT NOT NULL, "
          "value TEXT NOT NULL, "
          "projectID TEXT NOT NULL, "
          "UNIQUE(title, projectID)"
          ");",
      projectTable: "CREATE TABLE $projectTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "name TEXT NOT NULL, "
          "type TEXT NOT NULL, "
          "timestampCreated INTEGER NOT NULL,"
          "newVideoNeeded INTEGER NOT NULL"
          ");",
      videoTable: "CREATE TABLE $videoTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "resolution TEXT NOT NULL, "
          "watermarkEnabled TEXT NOT NULL, "
          "watermarkPos TEXT NOT NULL, "
          "projectID INTEGER NOT NULL, "
          "photoCount INTEGER NOT NULL, "
          "framerate INTEGER NOT NULL, "
          "timestampCreated INTEGER NOT NULL"
          ");",
      customFontTable: "CREATE TABLE $customFontTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "displayName TEXT NOT NULL UNIQUE, "
          "familyName TEXT NOT NULL UNIQUE, "
          "filePath TEXT NOT NULL, "
          "fileSize INTEGER NOT NULL, "
          "installedAt INTEGER NOT NULL"
          ");",
      deletedLinkedSourcesTable: "CREATE TABLE $deletedLinkedSourcesTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "projectID INTEGER NOT NULL, "
          "sourceRelativePath TEXT NOT NULL, "
          "deletedAt INTEGER NOT NULL, "
          "UNIQUE(projectID, sourceRelativePath)"
          ");",
      faceDetectionCacheTable: "CREATE TABLE $faceDetectionCacheTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "timestamp TEXT NOT NULL, "
          "projectID INTEGER NOT NULL, "
          "orientation TEXT NOT NULL, "
          "faceIndex INTEGER NOT NULL, "
          "selectedFaceIndex INTEGER, "
          "boundingBoxLeft REAL, "
          "boundingBoxTop REAL, "
          "boundingBoxRight REAL, "
          "boundingBoxBottom REAL, "
          "leftEyeX REAL, "
          "leftEyeY REAL, "
          "rightEyeX REAL, "
          "rightEyeY REAL, "
          "modelVersion TEXT NOT NULL, "
          "fingerprint TEXT NOT NULL, "
          "UNIQUE(timestamp, projectID, orientation, faceIndex)"
          ");",
      transformCacheTable: "CREATE TABLE $transformCacheTable("
          "id INTEGER PRIMARY KEY AUTOINCREMENT, "
          "cacheKey TEXT NOT NULL UNIQUE, "
          "projectID INTEGER NOT NULL, "
          "fingerprint TEXT NOT NULL, "
          "projectType TEXT NOT NULL, "
          "modelVersion TEXT NOT NULL, "
          "transformAlgorithmVersion TEXT NOT NULL, "
          "settingsHash TEXT NOT NULL, "
          "scope TEXT NOT NULL, "
          "sourceOrientation TEXT NOT NULL, "
          "selectedFaceIndex INTEGER, "
          "faceCount INTEGER, "
          "sourceWidth INTEGER, "
          "sourceHeight INTEGER, "
          "canvasWidth INTEGER NOT NULL, "
          "canvasHeight INTEGER NOT NULL, "
          "translateX REAL NOT NULL, "
          "translateY REAL NOT NULL, "
          "rotationDegrees REAL NOT NULL, "
          "scaleFactor REAL NOT NULL, "
          "finalScore REAL, "
          "finalEyeDeltaY REAL, "
          "finalEyeDistance REAL, "
          "goalEyeDistance REAL, "
          "preScore REAL, "
          "rotationPassScore REAL, "
          "scalePassScore REAL, "
          "translationPassScore REAL, "
          "isEstimated INTEGER NOT NULL DEFAULT 0, "
          "exampleTimestamp TEXT, "
          "createdAt INTEGER NOT NULL, "
          "updatedAt INTEGER NOT NULL"
          ");",
    };

    for (MapEntry<String, String> entry in tablesToCreate.entries) {
      if (!existingTables.contains(entry.key)) {
        await db.execute(entry.value);
      }
    }

    await _ensurePhotoTransformColumns();
    await _ensureFaceDetectionCacheColumns();
    await _dropLegacyTransformCacheHitCount();
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_project_ts ON $photoTable(projectID, timestamp);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_project_deleted '
      'ON $photoTable(projectID, deletedAt);',
    );
    // Partial index used by the launch-time global purge, which filters by
    // deletedAt without a leading projectID (so the composite above can't
    // serve it). The partial predicate keeps the index tiny — it only stores
    // rows currently in Recently Deleted.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_deleted_at '
      'ON $photoTable(deletedAt) WHERE deletedAt IS NOT NULL;',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_project_orientation ON $photoTable(projectID, originalOrientation);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_project_stabilized_portrait ON $photoTable(projectID, stabilizedPortrait);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_project_stabilized_landscape ON $photoTable(projectID, stabilizedLandscape);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_source_path ON $photoTable(projectID, sourceRelativePath) WHERE sourceRelativePath IS NOT NULL;',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_photos_fingerprint '
      'ON $photoTable(projectID, fingerprint) WHERE fingerprint IS NOT NULL;',
    );

    // Active-photos view. SQLite flattens this trivial WHERE-only view into
    // the outer query so the underlying indexes on [photoTable] are still
    // selected (verify with `EXPLAIN QUERY PLAN` if a future change adds
    // aggregates / GROUP BY / DISTINCT — those would defeat flattening).
    await db.execute(
      'CREATE VIEW IF NOT EXISTS $photoActiveView AS '
      'SELECT * FROM $photoTable WHERE deletedAt IS NULL;',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_face_cache_lookup '
      'ON $faceDetectionCacheTable(timestamp, projectID, modelVersion, fingerprint);',
    );
    // cacheKey lookups use the auto-index from `UNIQUE` on the column. Drop
    // the redundant explicit index if an older DB still has it.
    await db.execute('DROP INDEX IF EXISTS idx_transform_cache_lookup;');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transform_cache_project '
      'ON $transformCacheTable(projectID);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transform_cache_fingerprint '
      'ON $transformCacheTable(projectID, fingerprint);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transform_cache_settings '
      'ON $transformCacheTable(projectID, settingsHash);',
    );

    // Deduplicate existing setting rows (keep lowest id per title+projectID)
    // then create unique index — both are idempotent on already-clean databases.
    await db.execute('''
      DELETE FROM $settingTable WHERE id NOT IN (
        SELECT MIN(id) FROM $settingTable GROUP BY title, projectID
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_setting_title_project '
      'ON $settingTable(title, projectID)',
    );
  }

  /* ┌──────────────────────┐
     │                      │
     │    Private Helpers   │
     │                      │
     └──────────────────────┘ */

  Future<T?> _querySingle<T>(
    String table,
    String where,
    List<dynamic> whereArgs,
    T Function(Map<String, dynamic>) mapper, {
    List<String>? columns,
  }) async {
    final db = await database;
    final results = await db.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (results.isEmpty) return null;
    return mapper(results.first);
  }

  Future<T?> _queryFirstByOrder<T>(
    String table,
    String where,
    List<dynamic> whereArgs,
    String orderBy,
    T Function(Map<String, dynamic>) mapper,
  ) async {
    final db = await database;
    final results = await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: 1,
    );
    if (results.isEmpty) return null;
    return mapper(results.first);
  }

  /* ┌──────────────────────┐
     │                      │
     │       Projects       │
     │                      │
     └──────────────────────┘ */

  Future<int> addProject(String name, String type, int timestampCreated) async {
    final db = await database;
    return await db.insert(projectTable, {
      'name': name,
      'type': type,
      'timestampCreated': timestampCreated,
      'newVideoNeeded': 0,
    });
  }

  Future<String?> getProjectNameById(int projectId) => _querySingle(
        projectTable,
        'id = ?',
        [projectId],
        (r) => r['name'] as String,
        columns: ['name'],
      );

  Future<Map<String, dynamic>?> getProject(int id) =>
      _querySingle(projectTable, 'id = ?', [id], (r) => r);

  Future<Map<String, dynamic>?> getFirstProjectByName(String name) =>
      _querySingle(projectTable, 'name = ?', [name], (r) => r);

  Future<List<Map<String, dynamic>>> getAllProjects() async {
    final db = await database;
    return await db.query(projectTable);
  }

  Future<int> updateProjectName(int id, String newName) async {
    final db = await database;
    return await db.update(
      projectTable,
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteProject(int id) async {
    final db = await database;
    return await db.delete(projectTable, where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes all database records associated with a project atomically.
  /// Uses a transaction to ensure atomicity - either all deletions
  /// succeed or none do.
  ///
  /// Deletes from: Photos, Videos, Setting tables, then Projects table.
  /// Returns true if deletion was successful.
  Future<bool> deleteProjectCascade(int projectId) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        await txn.delete(
          photoTable,
          where: 'projectID = ?',
          whereArgs: [projectId],
        );
        await txn.delete(
          videoTable,
          where: 'projectID = ?',
          whereArgs: [projectId],
        );
        await txn.delete(
          settingTable,
          where: 'projectID = ?',
          whereArgs: [projectId.toString()],
        );
        await txn.delete(
          deletedLinkedSourcesTable,
          where: 'projectID = ?',
          whereArgs: [projectId],
        );
        await txn.delete(
          faceDetectionCacheTable,
          where: 'projectID = ?',
          whereArgs: [projectId],
        );
        await txn.delete(
          transformCacheTable,
          where: 'projectID = ?',
          whereArgs: [projectId],
        );
        await txn.delete(projectTable, where: 'id = ?', whereArgs: [projectId]);
      });
      return true;
    } catch (e) {
      LogService.instance.log('Failed to delete project cascade: $e');
      return false;
    }
  }

  Future<String?> getProjectTypeByProjectId(int projectId) => _querySingle(
        projectTable,
        'id = ?',
        [projectId],
        (r) => r['type'] as String,
        columns: ['type'],
      );

  Future<void> setNewVideoNeeded(int projectId) async {
    final db = await database;
    await db.update(
      projectTable,
      {'newVideoNeeded': 1},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  void setNewVideoNotNeeded(int projectId) async {
    final db = await database;
    await db.update(
      projectTable,
      {'newVideoNeeded': 0},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<int?> getNewVideoNeeded(int projectId) => _querySingle(
        projectTable,
        'id = ?',
        [projectId],
        (r) => r['newVideoNeeded'] as int,
        columns: ['newVideoNeeded'],
      );

  /* ┌──────────────────────┐
     │                      │
     │       Settings       │
     │                      │
     └──────────────────────┘ */

  // Default setting values
  static const String globalSettingFlag = 'global';
  static const defaultValues = {
    'theme': 'dark',
    'framerate': '14',
    'enable_grid': 'true',
    'save_to_camera_roll': 'false',
    'camera_mirror': 'true',
    'default_project': 'none',
    'enable_notifications': 'true',
    'framerate_is_default': 'true',
    'enable_watermark': 'false',
    'watermark_position': 'lower left',
    'daily_notification_time': 'not set',
    'opened_nonempty_gallery': 'false',
    'has_taken_first_photo': 'false',
    'has_viewed_first_video': 'false',
    'has_opened_notif_page': 'false',
    'has_seen_guide_mode_tut': 'false',
    'watermark_opacity': '0.7',
    'camera_flash': 'auto',
    'grid_mode_index': '0',
    'project_orientation': 'landscape',
    'eyeOffsetXPortrait': '0.065',
    'eyeOffsetXLandscape': '0.035',
    'eyeOffsetYPortrait': '0.421875',
    'eyeOffsetYLandscape': '0.421875',
    'guideOffsetXPortrait': '0.09',
    'guideOffsetXLandscape': '0.045',
    'guideOffsetYPortrait': '0.421875',
    'guideOffsetYLandscape': '0.421875',
    'gridAxisCount': '5',
    'gallery_grid_mode': 'auto', // 'auto' or 'manual' (desktop only)
    'video_resolution': '1080p',
    'auto_compile_video': 'true',
    'aspect_ratio': '16:9',
    'selected_guide_photo': 'not set',
    'stabilization_mode': 'slow',
    'background_color': '#000000', // Stabilization background fill color (hex)
    // Date stamp settings
    'gallery_date_labels_enabled': 'false',
    'gallery_raw_date_labels_enabled': 'false',
    'gallery_date_format': 'MM/yy',
    'export_date_stamp_enabled': 'false',
    'export_date_stamp_format': 'MMM dd, yyyy',
    'export_date_stamp_position': 'lower right',
    'export_date_stamp_size': '3',
    'export_date_stamp_opacity': '1.0',
    'gallery_date_stamp_font': 'Inter',
    'gallery_date_stamp_size': '4',
    'export_date_stamp_font': '_same_as_gallery',
    'export_date_stamp_margin': '2',
    'export_date_stamp_margin_h': '2.0',
    'export_date_stamp_margin_v': '2.0',
    // Video codec and background
    'video_codec': 'h264',
    'video_background': 'TRANSPARENT',
    'blur_zoom': '3.0',
    'blur_strength': '1.0',
    // Camera timer
    'camera_timer_duration': '0',
    // Lossless storage (preserves source bit depth for RAW/DNG imports)
    'lossless_storage': 'auto',
    'linked_source_enabled': 'false',
    'linked_source_mode': 'none',
    'linked_source_display_path': '',
    'linked_source_root_path': '',
    'linked_source_tree_uri': '',
    'linked_source_bookmark': '',
    'linked_source_managed_by_app': 'false',
    'linked_source_last_scan_started_at': '0',
    'linked_source_last_scan_completed_at': '0',
  };

  Future<Map<String, dynamic>?> getSettingByTitle(
    String title, [
    String projectId = globalSettingFlag,
  ]) async {
    final db = await database;
    final results = await db.query(
      settingTable,
      where: 'title = ? AND projectId = ?',
      whereArgs: [title, projectId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return results.first;
    }

    if (!defaultValues.containsKey(title)) {
      return null;
    }

    final defaultSetting = Setting(
      title: title,
      value: defaultValues[title]!,
      projectId: projectId,
    );

    await db.insert(
      settingTable,
      defaultSetting.toJson(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return defaultSetting.toJson();
  }

  Future<String> getSettingValueByTitle(
    String title, [
    String? projectId = globalSettingFlag,
  ]) async {
    final Map<String, dynamic>? settingData;
    settingData = await getSettingByTitle(title, projectId!);
    var settingValue = settingData?['value'];

    if (title == 'daily_notification_time' && settingValue == "not_set") {
      return getNotifDefault();
    }

    return settingValue;
  }

  Future<Map<String, dynamic>?> getPhotoById(String id, int projectId) async {
    final db = await database;
    final results = await db.query(
      photoTable,
      where: 'id = ? AND projectID = ?',
      whereArgs: [id, projectId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Active-only variant of [getPhotoById]. Returns `null` when the row is
  /// soft-deleted, mirroring how the gallery and stabilizer should see it.
  Future<Map<String, dynamic>?> getActivePhotoById(
    String id,
    int projectId,
  ) async {
    final db = await database;
    final results = await db.query(
      photoActiveView,
      where: 'id = ? AND projectID = ?',
      whereArgs: [id, projectId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  String getNotifDefault() {
    final DateTime fivePM = NotificationUtil.getFivePMLocalTime();
    return fivePM.millisecondsSinceEpoch.toString();
  }

  Future<int> setSettingByTitle(
    String title,
    String value, [
    String? projectId = globalSettingFlag,
  ]) async {
    final db = await database;

    if (title == 'framerate') {
      await setSettingByTitle('framerate_is_default', 'false', projectId);
    }

    // Ensure setting exists before updating (creates with default if missing)
    await getSettingByTitle(title, projectId!);

    return await db.update(
      settingTable,
      {'value': value},
      where: 'title = ? AND projectId = ?',
      whereArgs: [title, projectId],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> addSetting(Setting setting) async {
    final db = await database;
    return await db.insert(
      settingTable,
      setting.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateSetting(Setting setting) async {
    final db = await database;
    return await db.update(
      settingTable,
      setting.toJson(),
      where: 'id = ?',
      whereArgs: [setting.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteSetting(Setting setting) async {
    final db = await database;
    return await db.delete(
      settingTable,
      where: 'id = ?',
      whereArgs: [setting.id],
    );
  }

  Future<List<Setting>> getAllSettings() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(settingTable);
    return maps.map((map) => Setting.fromJson(map)).toList();
  }

  /* ┌──────────────────────┐
     │                      │
     │        Photos        │
     │                      │
     └──────────────────────┘ */

  Future<bool> addPhoto(
    String timestamp,
    int projectID,
    String fileExtension,
    int imageLength,
    String originalFilename,
    String orientation, {
    String? sourceFilename,
    String? sourceRelativePath,
    String? sourceLocationType,
    String? fingerprint,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        photoTable,
        columns: ['timestamp'],
        where: _photoWhereClause,
        whereArgs: [timestamp, projectID],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;

      await txn.insert(photoTable, {
        'timestamp': timestamp,
        'projectID': projectID,
        'fileExtension': fileExtension,
        'imageLength': imageLength,
        'originalFilename': originalFilename,
        'originalOrientation': orientation,
        'stabilizedPortrait': 0,
        'stabilizedLandscape': 0,
        'stabFailed': 0,
        'noFacesFound': 0,
        'favorite': 0,
        'sourceFilename': sourceFilename,
        'sourceRelativePath': sourceRelativePath,
        'sourceLocationType': sourceLocationType,
        'fingerprint': fingerprint,
      });
      return true;
    });
  }

  /// Looks up an *active* photo in [projectId] whose stored `fingerprint`
  /// exactly matches [fingerprint]. Returns `null` when no row matches,
  /// including when no rows carry a fingerprint (legacy / pre-migration) and
  /// when the only matching row is soft-deleted. Callers MUST treat a
  /// non-null return as a confirmed duplicate of the source file — the
  /// fingerprint comparison is the whole check.
  ///
  /// Soft-deleted rows are intentionally excluded so re-importing a file the
  /// user previously trashed creates a fresh active row, leaving the trashed
  /// row in Recently Deleted to age out. This matches the contract documented
  /// on [ProjectUtils.deleteImage] for `direct_import` re-imports.
  Future<Map<String, dynamic>?> findPhotoByFingerprint(
    int projectId,
    String fingerprint,
  ) async {
    final db = await database;
    final rows = await db.query(
      photoActiveView,
      where: 'projectID = ? AND fingerprint = ?',
      whereArgs: [projectId, fingerprint],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Sets `fingerprint` on the row identified by (timestamp, projectId),
  /// intended for opportunistic backfill of legacy rows that predate the
  /// column. Does not overwrite an existing non-null fingerprint.
  Future<void> backfillPhotoFingerprint(
    String timestamp,
    int projectId,
    String fingerprint,
  ) async {
    final db = await database;
    await db.update(
      photoTable,
      {'fingerprint': fingerprint},
      where: '$_photoWhereClause AND fingerprint IS NULL',
      whereArgs: [timestamp, projectId],
    );
  }

  Future<void> _ensurePhotoTransformColumns() async {
    final db = await database;
    final cols = await db.rawQuery('PRAGMA table_info($photoTable)');
    bool has(String name) => cols.any((c) => c['name'] == name);

    final toAdd = <String, String>{
      'stabilizedPortraitTranslateX': 'REAL DEFAULT 0',
      'stabilizedPortraitTranslateY': 'REAL DEFAULT 0',
      'stabilizedPortraitRotationDegrees': 'REAL DEFAULT 0',
      'stabilizedPortraitScaleFactor': 'REAL DEFAULT 1',
      'stabilizedLandscapeTranslateX': 'REAL DEFAULT 0',
      'stabilizedLandscapeTranslateY': 'REAL DEFAULT 0',
      'stabilizedLandscapeRotationDegrees': 'REAL DEFAULT 0',
      'stabilizedLandscapeScaleFactor': 'REAL DEFAULT 1',
      'captureOffsetMinutes': 'INTEGER',
      'faceCount': 'INTEGER',
      'faceEmbedding': 'BLOB',
      'sourceFilename': 'TEXT',
      'sourceRelativePath': 'TEXT',
      'sourceLocationType': 'TEXT',
      'stabAttempts': 'INTEGER NOT NULL DEFAULT 0',
      'stabLastError': 'TEXT',
      'stabLastAttemptAt': 'INTEGER',
      'fingerprint': 'TEXT',
      // Soft-delete: NULL = active, INTEGER = ms-since-epoch when deleted.
      // Filtered out of all user-facing queries; purged after
      // [recentlyDeletedRetentionDays] (or per-setting override).
      'deletedAt': 'INTEGER',
    };

    for (final entry in toAdd.entries) {
      if (!has(entry.key)) {
        await db.execute(
          'ALTER TABLE $photoTable ADD COLUMN ${entry.key} ${entry.value};',
        );
      }
    }
  }

  Future<void> _ensureFaceDetectionCacheColumns() async {
    final db = await database;
    final cols = await db.rawQuery(
      'PRAGMA table_info($faceDetectionCacheTable)',
    );
    bool has(String name) => cols.any((c) => c['name'] == name);

    if (!has('selectedFaceIndex')) {
      await db.execute(
        'ALTER TABLE $faceDetectionCacheTable ADD COLUMN selectedFaceIndex INTEGER;',
      );
    }
  }

  Future<void> _dropLegacyTransformCacheHitCount() async {
    final db = await database;
    final cols = await db.rawQuery(
      'PRAGMA table_info($transformCacheTable)',
    );
    if (!cols.any((c) => c['name'] == 'hitCount')) return;
    try {
      await db.execute(
        'ALTER TABLE $transformCacheTable DROP COLUMN hitCount;',
      );
    } catch (e) {
      // SQLite < 3.35 lacks DROP COLUMN. The column is unused and defaults
      // to 0, so leaving it in place is harmless.
      LogService.instance.log(
        '[DB] Could not drop legacy hitCount column: $e',
      );
    }
  }

  Future<bool> isFavoritePhoto(String timestamp, int projectId) async {
    final db = await database;
    final results = await db.query(
      photoTable,
      columns: ['favorite'],
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
      limit: 1,
    );

    return results.isNotEmpty && results.first['favorite'] == 1;
  }

  Future<int?> updatePhotoTimestamp(
    String oldTimestamp,
    String newTimestamp,
    int projectId,
  ) async {
    final db = await database;

    final photoData = await getPhotoByTimestamp(oldTimestamp, projectId);
    if (photoData == null) return null;

    final Map<String, dynamic> updatedPhotoData = Map.from(photoData);
    updatedPhotoData['timestamp'] = newTimestamp;
    int? newId;
    await db.transaction((txn) async {
      newId = await txn.insert(
        photoTable,
        updatedPhotoData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        photoTable,
        where: _photoWhereClause,
        whereArgs: [oldTimestamp, projectId],
      );
    });

    return newId;
  }

  Future<void> setPhotoAsFavorite(String timestamp, int projectId) async {
    final db = await database;
    await db.update(
      photoTable,
      {'favorite': 1},
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  /// Hard-deletes a photo row. Used by the project-folder sync service
  /// (when an external linked file vanishes) and by [permanentlyDeletePhoto]
  /// after the recently-deleted retention window expires.
  Future<int> deletePhoto(int timestamp, int projectId) async {
    final db = await database;
    return await db.delete(
      photoTable,
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  /// Hard-deletes a photo row only if it is currently soft-deleted. Used by
  /// "Delete Forever" and the launch-time purge to guarantee that a row that
  /// has been restored (e.g. via another route) cannot be obliterated by a
  /// stale UI snapshot or a race with the purge.
  Future<int> hardDeletePhotoIfTrashed(int timestamp, int projectId) async {
    final db = await database;
    return await db.delete(
      photoTable,
      where: '$_photoWhereClause AND deletedAt IS NOT NULL',
      whereArgs: [timestamp, projectId],
    );
  }

  /// Counts active rows in [projectId] that reference [sourceRelativePath].
  ///
  /// Scoped per-project so two projects linked to *different* external roots
  /// that happen to contain the same relative path (e.g. `IMG_001.jpg` in
  /// each) don't false-positive each other and block source-file deletion.
  /// Same-project ref-counting still catches the case where a single project
  /// has multiple rows pointing at one file (rare, but possible via
  /// re-import + timestamp bump).
  Future<int> countActivePhotosBySourceRelativePath(
    int projectId,
    String sourceRelativePath,
  ) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $photoActiveView '
      'WHERE projectID = ? AND sourceRelativePath = ?',
      [projectId, sourceRelativePath],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Removes face-detection cache rows for the given (timestamp, project)
  /// across all model versions / orientations / face indices. Called from
  /// [permanentlyDeleteImage] so caches don't outlive the photo row.
  Future<int> clearFaceDetectionCacheForPhoto(
    String timestamp,
    int projectId,
  ) async {
    final db = await database;
    return await db.delete(
      faceDetectionCacheTable,
      where: 'timestamp = ? AND projectID = ?',
      whereArgs: [timestamp, projectId],
    );
  }

  /// Marks a photo as deleted without removing the row. The photo is hidden
  /// from all user-facing queries and from the video pipeline, but its files,
  /// face-detection cache, and transform cache remain so a fast restore is
  /// possible. Returns the number of rows affected.
  ///
  /// If [linkedSourceRelativePath] is non-null and non-empty, the linked-
  /// source tombstone is inserted in the *same transaction* so the sync
  /// service can never observe a state where the photo is hidden but the
  /// tombstone is missing (which would re-import the file on the next pass).
  ///
  /// [deletedAt] overrides the timestamp written to both the photo row and the
  /// tombstone. The rollback path in restoreImage passes the original value so
  /// the 30-day retention timer is preserved rather than reset.
  Future<int> softDeletePhoto(
    int timestamp,
    int projectId, {
    String? linkedSourceRelativePath,
    int? deletedAt,
  }) async {
    final db = await database;
    final int effectiveDeletedAt =
        deletedAt ?? DateTime.now().millisecondsSinceEpoch;
    int rows = 0;
    await db.transaction((txn) async {
      rows = await txn.update(
        photoTable,
        {'deletedAt': effectiveDeletedAt},
        // 'deletedAt IS NULL' guard ensures the UPDATE is idempotent — a
        // soft-delete on an already-trashed row is a no-op and won't reset
        // the retention timer. SQLite views are read-only so this UPDATE
        // can't go through [photoActiveView].
        where: '$_photoWhereClause AND deletedAt IS NULL',
        whereArgs: [timestamp, projectId],
      );
      if (rows > 0 &&
          linkedSourceRelativePath != null &&
          linkedSourceRelativePath.trim().isNotEmpty) {
        await txn.insert(
          deletedLinkedSourcesTable,
          {
            'projectID': projectId,
            'sourceRelativePath': linkedSourceRelativePath,
            'deletedAt': effectiveDeletedAt,
          },
          // Ignore (not replace) so a stale tombstone from a prior failed flow keeps
          // its original deletedAt — replacing would reset retention and delay the
          // launch-time purge.
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    return rows;
  }

  /// Clears the [deletedAt] flag, returning the photo to the active gallery.
  ///
  /// If [linkedSourceRelativePath] is non-null and non-empty, the linked-
  /// source tombstone is removed in the *same transaction* so the sync
  /// service can't see a restored row that's still tombstoned (which would
  /// silently block any future re-add of the file).
  Future<int> restorePhotoFromTrash(
    int timestamp,
    int projectId, {
    String? linkedSourceRelativePath,
  }) async {
    final db = await database;
    int rows = 0;
    await db.transaction((txn) async {
      rows = await txn.update(
        photoTable,
        {'deletedAt': null},
        where: '$_photoWhereClause AND deletedAt IS NOT NULL',
        whereArgs: [timestamp, projectId],
      );
      if (rows > 0 &&
          linkedSourceRelativePath != null &&
          linkedSourceRelativePath.trim().isNotEmpty) {
        await txn.delete(
          deletedLinkedSourcesTable,
          where: 'projectID = ? AND sourceRelativePath = ?',
          whereArgs: [projectId, linkedSourceRelativePath],
        );
      }
    });
    return rows;
  }

  /// Returns soft-deleted photos for a project, newest-deleted first.
  ///
  /// Selects only the columns needed by the Recently Deleted page and the
  /// launch-time purge. In particular `faceEmbedding` (BLOB), the manual
  /// stabilization offsets, and the bounding-box columns are excluded so a
  /// project with thousands of trashed rows doesn't pull tens of MB into
  /// memory.
  Future<List<Map<String, dynamic>>> getRecentlyDeletedPhotosByProjectID(
    int projectId,
  ) async {
    final db = await database;
    return await db.query(
      photoTable,
      columns: _recentlyDeletedColumns,
      where: 'projectID = ? AND deletedAt IS NOT NULL',
      whereArgs: [projectId],
      orderBy: 'deletedAt DESC',
    );
  }

  static const List<String> _recentlyDeletedColumns = <String>[
    'id',
    'timestamp',
    'projectID',
    'fileExtension',
    'deletedAt',
    'sourceLocationType',
    'sourceRelativePath',
    'sourceFilename',
    'originalFilename',
    'fingerprint',
  ];

  Future<int> getRecentlyDeletedCountByProjectID(int projectId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $photoTable '
      'WHERE projectID = ? AND deletedAt IS NOT NULL',
      [projectId],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Returns all photos whose [deletedAt] is older than the given cutoff
  /// (ms since epoch), across every project. Used by the launch-time purge.
  /// Selects only the columns the purge actually needs (timestamp, projectID,
  /// fileExtension) so a long-running install with many expired rows doesn't
  /// pull face-embedding BLOBs into memory.
  Future<List<Map<String, dynamic>>> getExpiredDeletedPhotos(
    int cutoffEpochMs,
  ) async {
    final db = await database;
    return await db.query(
      photoTable,
      columns: const ['timestamp', 'projectID', 'fileExtension'],
      where: 'deletedAt IS NOT NULL AND deletedAt < ?',
      whereArgs: [cutoffEpochMs],
    );
  }

  Future<int> deleteAllPhotos() async {
    final db = await database;
    return await db.delete(photoTable);
  }

  String? _resolveOrientation(
    List<Map<String, dynamic>> result, {
    required bool unanimous,
  }) {
    if (result.isEmpty) return null;
    final row = result.first;
    final total = (row[unanimous ? 'totalNonNull' : 'totalCount'] as int?) ?? 0;
    if (total == 0) return null;
    final landscapeCount = (row['landscapeCount'] as int?) ?? 0;
    if (unanimous) {
      final portraitCount = (row['portraitCount'] as int?) ?? 0;
      if (portraitCount == total) return 'portrait';
      return landscapeCount == total ? 'landscape' : null;
    }
    return landscapeCount / total >= 0.5 ? 'landscape' : 'portrait';
  }

  Future<String?> checkAllPhotoOrientations() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) AS totalNonNull,
        SUM(CASE WHEN originalOrientation = 'portrait' THEN 1 ELSE 0 END) AS portraitCount,
        SUM(CASE WHEN originalOrientation = 'landscape' THEN 1 ELSE 0 END) AS landscapeCount
      FROM $photoTable
      WHERE originalOrientation IS NOT NULL
    ''');
    return _resolveOrientation(result, unanimous: true);
  }

  Future<String?> checkPhotoOrientationThreshold(int projectId) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS totalCount,
        SUM(CASE WHEN originalOrientation = 'portrait' THEN 1 ELSE 0 END) AS portraitCount,
        SUM(CASE WHEN originalOrientation = 'landscape' THEN 1 ELSE 0 END) AS landscapeCount
      FROM $photoActiveView
      WHERE projectID = ? AND originalOrientation IS NOT NULL
    ''',
      [projectId],
    );
    return _resolveOrientation(result, unanimous: false);
  }

  String getStabilizedColumn(String projectOrientation) {
    return projectOrientation.toLowerCase() == "portrait"
        ? "stabilizedPortrait"
        : "stabilizedLandscape";
  }

  Future<void> resetStabilizedColumn(String projectOrientation) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);
    await db.update(photoTable, {stabilizedColumn: 0});
  }

  Future<void> resetStabilizedColumnByTimestamp(
    String projectOrientation,
    String timestamp,
    int projectId,
  ) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);
    await db.update(
      photoTable,
      {stabilizedColumn: 0},
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  Future<void> resetPhotoStabilizationState({
    required String timestamp,
    required int projectId,
    required String orientation,
  }) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(orientation);
    await db.update(
      photoTable,
      {stabilizedColumn: 0, 'stabFailed': 0, 'noFacesFound': 0},
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
    try {
      await db.update(
        photoTable,
        {'stabAttempts': 0, 'stabLastError': null},
        where: _photoWhereClause,
        whereArgs: [timestamp, projectId],
      );
    } catch (e) {
      LogService.instance.log(
        '[DB] resetPhotoStabilizationState: could not reset stabAttempts/stabLastError (old schema?): $e',
      );
    }
  }

  Future<String?> getPhotoExtensionByTimestampAndProjectId(
    String timestamp,
    int projectId,
  ) =>
      _querySingle(
        photoTable,
        _photoWhereClause,
        [timestamp, projectId],
        (r) => r['fileExtension'] as String,
        columns: ['fileExtension'],
      );

  Future<Map<String, dynamic>?> getOriginalInfoByTimestamp(
    String timestamp,
    int projectId,
  ) =>
      _querySingle(
        photoTable,
        _photoWhereClause,
        [timestamp, projectId],
        (r) => r,
        columns: [
          'id',
          'timestamp',
          'fileExtension',
          'originalFilename',
          'sourceFilename',
          'sourceRelativePath',
          'sourceLocationType',
          // Needed by permanentlyDeleteImage to clear the transform cache.
          'fingerprint',
          'deletedAt',
        ],
      );

  /// Batch query to get original source filenames for multiple timestamps.
  /// Returns a map of timestamp -> sourceFilename. Queries in chunks to avoid
  /// SQLite parameter limits.
  Future<Map<String, String>> getSourceFilenamesBatch(
    List<String> timestamps,
    int projectId,
  ) async {
    if (timestamps.isEmpty) return {};

    final db = await database;
    final Map<String, String> result = {};

    const chunkSize = 500;
    for (int i = 0; i < timestamps.length; i += chunkSize) {
      final chunk = timestamps.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');

      final rows = await db.query(
        photoTable,
        columns: ['timestamp', 'sourceFilename', 'originalFilename'],
        where: 'timestamp IN ($placeholders) AND projectID = ?',
        whereArgs: [...chunk, projectId],
      );

      for (final row in rows) {
        final timestamp = row['timestamp'] as String?;
        final sourceFilename = row['sourceFilename'] as String?;
        final originalFilename = row['originalFilename'] as String?;
        if (timestamp == null) continue;
        final effectiveFilename = sourceFilename?.trim().isNotEmpty == true
            ? sourceFilename!.trim()
            : (originalFilename?.trim() ?? '');
        if (effectiveFilename.isEmpty) continue;
        result[timestamp] = effectiveFilename;
      }
    }

    return result;
  }

  Future<Map<String, dynamic>?> getPhotoBySourceRelativePath(
    String relativePath,
    int projectId,
  ) =>
      _querySingle(
          photoActiveView,
          'sourceRelativePath = ? AND projectID = ?',
          [
            relativePath,
            projectId,
          ],
          (r) => r);

  Future<List<Map<String, dynamic>>> getPhotosBySourceLocationType(
    int projectId,
    String sourceLocationType,
  ) async {
    final db = await database;
    return db.query(
      photoActiveView,
      where: 'projectID = ? AND sourceLocationType = ?',
      whereArgs: [projectId, sourceLocationType],
    );
  }

  Future<void> updatePhotoSourceInfo(
    String timestamp,
    int projectId, {
    String? sourceFilename,
    String? sourceRelativePath,
    String? sourceLocationType,
  }) async {
    final db = await database;
    final data = <String, Object?>{};
    if (sourceFilename != null) data['sourceFilename'] = sourceFilename;
    if (sourceRelativePath != null) {
      data['sourceRelativePath'] = sourceRelativePath;
    }
    if (sourceLocationType != null) {
      data['sourceLocationType'] = sourceLocationType;
    }
    if (data.isEmpty) return;
    await db.update(
      photoTable,
      data,
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  Future<List<Map<String, dynamic>>> getPhotosByImageLength(
    int projectId,
    int imageLength, {
    bool whereSourceRelativePathIsNull = false,
  }) async {
    final db = await database;
    final where = StringBuffer('projectID = ? AND imageLength = ?');
    if (whereSourceRelativePathIsNull) {
      where.write(' AND sourceRelativePath IS NULL');
    }
    return db.query(
      photoActiveView,
      where: where.toString(),
      whereArgs: [projectId, imageLength],
    );
  }

  Future<List<Map<String, dynamic>>> getUnstabilizedPhotos(
    int projectId,
    String projectOrientation, {
    int maxAttempts = 5,
  }) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);
    return await db.query(
      photoActiveView,
      where:
          '$stabilizedColumn = ? AND noFacesFound = ? AND stabFailed = ? AND projectID = ? AND stabAttempts < ?',
      whereArgs: [0, 0, 0, projectId, maxAttempts],
      orderBy: '$_orderByTimestamp ASC',
    );
  }

  Future<void> setPhotoStabilized(
    String timestamp,
    int projectId,
    String projectOrientation,
    String aspectRatio,
    String resolution,
    double offsetX,
    double offsetY, {
    double? translateX,
    double? translateY,
    double? rotationDegrees,
    double? scaleFactor,
  }) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);

    final Map<String, Object?> data = {
      stabilizedColumn: 1,
      "${stabilizedColumn}AspectRatio": aspectRatio,
      "${stabilizedColumn}Resolution": resolution,
      "${stabilizedColumn}OffsetX": offsetX.toString(),
      "${stabilizedColumn}OffsetY": offsetY.toString(),
      "stabFailed": 0,
      "noFacesFound": 0,
      "stabAttempts": 0,
      "stabLastError": null,
    };

    if (translateX != null) {
      data["${stabilizedColumn}TranslateX"] = translateX;
    }
    if (translateY != null) {
      data["${stabilizedColumn}TranslateY"] = translateY;
    }
    if (rotationDegrees != null) {
      data["${stabilizedColumn}RotationDegrees"] = rotationDegrees;
    }
    if (scaleFactor != null) {
      data["${stabilizedColumn}ScaleFactor"] = scaleFactor;
    }

    await db.update(
      photoTable,
      data,
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  Future<dynamic> getPhotoColumnValueByTimestamp(
    String timestamp,
    String columnName,
    int projectId,
  ) async {
    final db = await database;
    final results = await db.query(
      photoTable,
      columns: [columnName],
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return results.first[columnName];
    } else {
      return null;
    }
  }

  Future<List<Map<String, Object?>>> getSetEyePhoto(
    double offsetX,
    int projectId,
  ) async {
    final db = await database;
    final String projectOrientation = await SettingsUtil.loadProjectOrientation(
      projectId.toString(),
    );
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);
    return await db.query(
      photoActiveView,
      where:
          '$stabilizedColumn = ? AND projectID = ? AND ${stabilizedColumn}OffsetX = ?',
      whereArgs: [1, projectId, offsetX.toString()],
      orderBy: '$_orderByTimestamp ASC',
    );
  }

  Future<void> _setPhotoField(
    String timestamp,
    int projectId,
    String field,
  ) async {
    final db = await database;
    await db.update(
      photoTable,
      {field: 1},
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  Future<void> setPhotoNoFacesFound(String timestamp, int projectId) =>
      _setPhotoField(timestamp, projectId, 'noFacesFound');

  Future<void> setPhotoStabFailed(String timestamp, int projectId) =>
      _setPhotoField(timestamp, projectId, 'stabFailed');

  Future<void> incrementPhotoStabAttempts({
    required String timestamp,
    required int projectId,
    String? errorMessage,
  }) async {
    try {
      final db = await database;
      await db.rawUpdate(
        'UPDATE $photoTable SET stabAttempts = stabAttempts + 1, stabLastError = ?, stabLastAttemptAt = ? WHERE timestamp = ? AND projectID = ?',
        [
          errorMessage,
          DateTime.now().millisecondsSinceEpoch,
          timestamp,
          projectId,
        ],
      );
    } catch (e) {
      LogService.instance.log('[DB] incrementPhotoStabAttempts failed: $e');
    }
  }

  /// Stores face count and optional embedding for a photo.
  /// [faceCount] is the number of faces detected.
  /// [embedding] is the 192-dim Float32List as bytes (only stored for single-face photos).
  Future<void> setPhotoFaceData(
    String timestamp,
    int projectId,
    int faceCount, {
    Uint8List? embedding,
  }) async {
    final db = await database;
    final Map<String, Object?> data = {'faceCount': faceCount};
    if (embedding != null) {
      data['faceEmbedding'] = embedding;
    }
    await db.update(
      photoTable,
      data,
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  /// Gets the closest single-face photo by timestamp for embedding-based face matching.
  /// Returns the embedding bytes and timestamp of the nearest photo with exactly 1 face.
  /// Returns null if no single-face photos exist for this project.
  Future<Map<String, dynamic>?> getClosestSingleFacePhoto(
    String targetTimestamp,
    int projectId,
  ) async {
    final db = await database;
    // Query for single-face photos with embeddings, ordered by absolute timestamp difference
    final results = await db.rawQuery(
      '''
      SELECT timestamp, faceEmbedding
      FROM $photoActiveView
      WHERE projectID = ?
        AND faceCount = 1
        AND faceEmbedding IS NOT NULL
      ORDER BY ABS($_orderByTimestamp - CAST(? AS INTEGER))
      LIMIT 1
    ''',
      [projectId, targetTimestamp],
    );

    if (results.isEmpty) return null;
    return results.first;
  }

  /// Gets the face embedding for a specific photo.
  Future<Uint8List?> getPhotoEmbedding(String timestamp, int projectId) async {
    final db = await database;
    final results = await db.query(
      photoTable,
      columns: ['faceEmbedding'],
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first['faceEmbedding'] as Uint8List?;
  }

  Future<void> setCaptureOffsetMinutesByTimestamp(
    String timestamp,
    int projectId,
    int? minutes,
  ) async {
    final db = await database;
    await db.update(
      photoTable,
      {'captureOffsetMinutes': minutes},
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  /// Includes soft-deleted rows. The (timestamp, projectID) pair is also the
  /// raw-file slot identifier on disk, so importers and renamers need to know
  /// whether the slot is taken regardless of trash state.
  Future<bool> doesPhotoExistByTimestamp(
    String timestamp,
    int projectId,
  ) async {
    final db = await database;
    final results = await db.query(
      photoTable,
      columns: ['timestamp'],
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// Includes soft-deleted rows (see [doesPhotoExistByTimestamp]).
  Future<List<Map<String, dynamic>>> getPhotosByTimestamp(
    String timestamp,
    int projectId,
  ) async {
    final db = await database;
    return await db.query(
      photoTable,
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
    );
  }

  /// Includes soft-deleted rows. Use [getActivePhotoByTimestamp] from
  /// gallery / preview / stabilizer code paths that should never see trashed
  /// rows.
  Future<Map<String, dynamic>?> getPhotoByTimestamp(
    String timestamp,
    int projectId,
  ) async {
    final photos = await getPhotosByTimestamp(timestamp, projectId);
    return photos.firstOrNull;
  }

  /// Active-only variant of [getPhotoByTimestamp]. Returns `null` when the
  /// row is soft-deleted.
  Future<Map<String, dynamic>?> getActivePhotoByTimestamp(
    String timestamp,
    int projectId,
  ) async {
    final db = await database;
    final results = await db.query(
      photoActiveView,
      where: _photoWhereClause,
      whereArgs: [timestamp, projectId],
      limit: 1,
    );
    return results.isEmpty ? null : results.first;
  }

  Future<List<Map<String, dynamic>>> getPhotosByProjectID(int projectID) async {
    final db = await database;
    return await db.query(
      photoActiveView,
      where: 'projectID = ?',
      whereArgs: [projectID],
    );
  }

  /// Get captureOffsetMinutes for a list of timestamps.
  /// Returns a map of timestamp -> offset minutes (null if not found).
  Future<Map<String, int?>> getCaptureOffsetMinutesForTimestamps(
    List<String> timestamps,
    int projectId,
  ) async {
    final db = await database;
    final result = <String, int?>{};
    if (timestamps.isEmpty) return result;

    // Batch query for efficiency
    final placeholders = List.filled(timestamps.length, '?').join(',');
    final photos = await db.query(
      photoTable,
      columns: ['timestamp', 'captureOffsetMinutes'],
      where: 'timestamp IN ($placeholders) AND projectID = ?',
      whereArgs: [...timestamps, projectId],
    );

    for (final photo in photos) {
      final ts = photo['timestamp'] as String?;
      if (ts != null) {
        result[ts] = photo['captureOffsetMinutes'] as int?;
      }
    }
    return result;
  }

  Future<int> getPhotoCountByProjectID(int projectId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $photoActiveView WHERE projectID = ?',
      [projectId],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<List<String>> getAllPhotoPathsByProjectID(int projectId) async {
    final db = await database;

    final List<Map<String, dynamic>> photos = await db.query(
      photoActiveView,
      columns: ['timestamp', 'fileExtension'],
      where: 'projectID = ?',
      whereArgs: [projectId],
      orderBy: '$_orderByTimestamp DESC',
    );

    List<Future<String>> futurePaths = photos.map((photo) async {
      final String timestamp = photo['timestamp'];
      return await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        timestamp,
        projectId,
        fileExtension: photo['fileExtension'],
      );
    }).toList();

    List<String> rawImagePaths = await Future.wait(futurePaths);

    return rawImagePaths;
  }

  Future<List<Map<String, dynamic>>> getStabilizedPhotosByProjectID(
    int projectId,
    String projectOrientation,
  ) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);
    return await db.query(
      photoActiveView,
      where: '$stabilizedColumn = ? AND projectID = ?',
      whereArgs: [1, projectId],
    );
  }

  /// Get stabilized photos that need re-stabilization due to settings change.
  /// Returns photos where stored OffsetX doesn't match the current setting.
  Future<List<Map<String, dynamic>>> getPhotosNeedingRestabilization(
    int projectId,
    String projectOrientation,
    String currentOffsetX,
  ) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);
    return await db.query(
      photoActiveView,
      where:
          '$stabilizedColumn = ? AND projectID = ? AND ${stabilizedColumn}OffsetX != ?',
      whereArgs: [1, projectId, currentOffsetX],
    );
  }

  Future<List<Map<String, dynamic>>> getStabilizedAndFailedPhotosByProjectID(
    int projectId,
    String projectOrientation,
  ) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);

    return await db.query(
      photoActiveView,
      columns: ['timestamp', 'fileExtension'],
      where:
          '($stabilizedColumn = ? OR stabFailed = ? OR noFacesFound = ?) AND projectID = ?',
      whereArgs: [1, 1, 1, projectId],
      orderBy: '$_orderByTimestamp DESC',
    );
  }

  /// Batch query to get photo status flags for multiple timestamps.
  /// Returns a map of timestamp -> {noFacesFound, stabFailed} for efficient
  /// thumbnail status prefetching. Queries in chunks to avoid SQLite limits.
  Future<Map<String, Map<String, int>>> getPhotoStatusBatch(
    List<String> timestamps,
    int projectId,
  ) async {
    if (timestamps.isEmpty) return {};

    final db = await database;
    final Map<String, Map<String, int>> result = {};

    // SQLite has a limit of ~999 parameters, chunk to 500 for safety
    const chunkSize = 500;
    for (int i = 0; i < timestamps.length; i += chunkSize) {
      final chunk = timestamps.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');

      final rows = await db.query(
        photoTable,
        columns: ['timestamp', 'noFacesFound', 'stabFailed'],
        where: 'timestamp IN ($placeholders) AND projectID = ?',
        whereArgs: [...chunk, projectId],
      );

      for (final row in rows) {
        final ts = row['timestamp'] as String;
        result[ts] = {
          'noFacesFound': row['noFacesFound'] as int? ?? 0,
          'stabFailed': row['stabFailed'] as int? ?? 0,
        };
      }
    }

    return result;
  }

  Future<int> getStabilizedPhotoCountByProjectID(
    int projectId,
    String projectOrientation,
  ) async {
    final db = await database;
    final String stabilizedColumn = getStabilizedColumn(projectOrientation);

    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM $photoActiveView '
      'WHERE $stabilizedColumn = 1 AND projectID = ?',
      [projectId],
    );

    return result.first.values.first as int? ?? 0;
  }

  Future<bool> hasStabilizedPhotos(
    int projectId,
    String projectOrientation,
  ) async {
    final count = await getStabilizedPhotoCountByProjectID(
      projectId,
      projectOrientation,
    );
    return count > 0;
  }

  Future<List<Map<String, dynamic>>> getPhotosByProjectIDNewestFirst(
    int projectID,
  ) async {
    final db = await database;
    return await db.query(
      photoActiveView,
      where: 'projectID = ?',
      whereArgs: [projectID],
      orderBy: '$_orderByTimestamp DESC',
    );
  }

  Future<void> resetStabilizationStatusForProject(
    int projectId,
    String projectOrientation,
  ) async {
    final db = await database;

    String inactiveProjectOrientation =
        projectOrientation.toLowerCase() == "landscape"
            ? "portrait"
            : "landscape";

    String activePOColumn = getStabilizedColumn(projectOrientation);
    String inactivePOColumn = getStabilizedColumn(inactiveProjectOrientation);

    await db.update(
      photoTable,
      {
        activePOColumn: 0,
        inactivePOColumn: 0,
        "noFacesFound": 0,
        "stabFailed": 0,
      },
      where: 'projectID = ?',
      whereArgs: [projectId],
    );

    // Also clear retry-count state so previously-capped photos (stabAttempts
    // >= maxAttempts) are eligible for stabilization again after an explicit
    // user-triggered reset (settings change, retry, etc). Guarded with
    // try/catch for old schemas that pre-date the stabAttempts columns.
    try {
      await db.update(
        photoTable,
        {'stabAttempts': 0, 'stabLastError': null},
        where: 'projectID = ?',
        whereArgs: [projectId],
      );
    } catch (e) {
      LogService.instance.log(
        '[DB] resetStabilizationStatusForProject: could not clear stabAttempts/stabLastError (old schema?): $e',
      );
    }

    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(
      projectId,
    );
    final Directory stabilizedDir = Directory(stabilizedDirPath);
    await DirUtils.deleteDirectoryContents(stabilizedDir);
  }

  Future<String?> getEarliestPhotoTimestamp(int projectId) =>
      _queryFirstByOrder(
        photoActiveView,
        'projectID = ?',
        [projectId],
        '$_orderByTimestamp ASC',
        (r) => r['timestamp'] as String,
      );

  Future<String?> getLatestPhotoTimestamp(int projectId) => _queryFirstByOrder(
        photoActiveView,
        'projectID = ?',
        [projectId],
        '$_orderByTimestamp DESC',
        (r) => r['timestamp'] as String,
      );

  /* ┌──────────────────────┐
     │                      │
     │        Videos        │
     │                      │
     └──────────────────────┘ */

  Future<int> addVideo(
    int projectId,
    String resolution,
    String watermarkEnabled,
    String watermarkPos,
    int photoCount,
    int framerate,
  ) async {
    final db = await database;
    final timestampCreated = DateTime.now().millisecondsSinceEpoch;
    return await db.insert(
        videoTable,
        {
          'projectID': projectId,
          'resolution': resolution,
          'watermarkEnabled': watermarkEnabled,
          'watermarkPos': watermarkPos,
          'photoCount': photoCount,
          'framerate': framerate,
          'timestampCreated': timestampCreated,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getNewestVideoByProjectId(int projectId) =>
      _queryFirstByOrder(
        videoTable,
        'projectID = ?',
        [projectId],
        'timestampCreated DESC',
        (r) => r,
      );

  /* ┌──────────────────────┐
     │                      │
     │    Custom Fonts      │
     │                      │
     └──────────────────────┘ */

  /// Add a custom font to the database.
  /// Returns the ID of the inserted font.
  Future<int> addCustomFont({
    required String displayName,
    required String familyName,
    required String filePath,
    required int fileSize,
  }) async {
    final db = await database;
    final installedAt = DateTime.now().millisecondsSinceEpoch;
    return await db.insert(
        customFontTable,
        {
          'displayName': displayName,
          'familyName': familyName,
          'filePath': filePath,
          'fileSize': fileSize,
          'installedAt': installedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get all custom fonts from the database.
  Future<List<CustomFont>> getAllCustomFonts() async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      customFontTable,
      orderBy: 'displayName ASC',
    );
    return results.map((row) => CustomFont.fromJson(row)).toList();
  }

  /// Get a custom font by its ID.
  Future<CustomFont?> getCustomFontById(int id) =>
      _querySingle(customFontTable, 'id = ?', [id], CustomFont.fromJson);

  /// Get a custom font by its family name.
  Future<CustomFont?> getCustomFontByFamilyName(String familyName) =>
      _querySingle(
          customFontTable,
          'familyName = ?',
          [
            familyName,
          ],
          CustomFont.fromJson);

  /// Get a custom font by its display name.
  Future<CustomFont?> getCustomFontByDisplayName(String displayName) =>
      _querySingle(
          customFontTable,
          'displayName = ?',
          [
            displayName,
          ],
          CustomFont.fromJson);

  /// Delete a custom font by its ID.
  Future<int> deleteCustomFont(int id) async {
    final db = await database;
    return await db.delete(customFontTable, where: 'id = ?', whereArgs: [id]);
  }

  /// Update the display name of a custom font.
  Future<int> updateCustomFontDisplayName(int id, String newDisplayName) async {
    final db = await database;
    return await db.update(
      customFontTable,
      {'displayName': newDisplayName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get the count of installed custom fonts.
  Future<int> getCustomFontCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $customFontTable',
    );
    return result.first['count'] as int? ?? 0;
  }

  /* ┌──────────────────────────────┐
     │                              │
     │   Deleted Linked Sources     │
     │                              │
     └──────────────────────────────┘ */

  /// Records that a linked source file was explicitly deleted by the user,
  /// preventing the sync service from reimporting it.
  Future<void> insertDeletedLinkedSource(
    int projectId,
    String sourceRelativePath,
  ) async {
    final db = await database;
    await db.insert(
        deletedLinkedSourcesTable,
        {
          'projectID': projectId,
          'sourceRelativePath': sourceRelativePath,
          'deletedAt': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Returns true if the given relative path was explicitly deleted by the user
  /// for this project (i.e. it is in the tombstone table).
  Future<bool> isLinkedSourceDeleted(
    int projectId,
    String sourceRelativePath,
  ) async {
    final db = await database;
    final results = await db.query(
      deletedLinkedSourcesTable,
      columns: ['id'],
      where: 'projectID = ? AND sourceRelativePath = ?',
      whereArgs: [projectId, sourceRelativePath],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// Removes the tombstone for a linked source that has been restored, allowing
  /// the sync service to reimport it if it reappears.
  Future<void> deleteLinkedSourceTombstone(
    int projectId,
    String sourceRelativePath,
  ) async {
    final db = await database;
    await db.delete(
      deletedLinkedSourcesTable,
      where: 'projectID = ? AND sourceRelativePath = ?',
      whereArgs: [projectId, sourceRelativePath],
    );
  }

  /* ┌──────────────────────────────┐
     │                              │
     │   Face Detection Cache       │
     │                              │
     └──────────────────────────────┘ */

  Future<FaceDetectionCacheResult?> getFaceDetectionCache(
    String timestamp,
    int projectId,
    String modelVersion,
    String fingerprint,
  ) async {
    final db = await database;
    final rows = await db.query(
      faceDetectionCacheTable,
      where:
          'timestamp = ? AND projectID = ? AND modelVersion = ? AND fingerprint = ?',
      whereArgs: [timestamp, projectId, modelVersion, fingerprint],
      orderBy: 'faceIndex ASC',
    );
    if (rows.isEmpty) return null;

    final orientation = rows.first['orientation'] as String;

    if (orientation == 'no_faces') {
      return const FaceDetectionCacheResult(orientation: 'no_faces', faces: []);
    }

    final selectedFaceIndex = rows.first['selectedFaceIndex'] as int?;
    final entries = rows.map((row) {
      final left = row['boundingBoxLeft'] as double;
      final top = row['boundingBoxTop'] as double;
      final right = row['boundingBoxRight'] as double;
      final bottom = row['boundingBoxBottom'] as double;
      final leftEyeX = row['leftEyeX'] as double?;
      final leftEyeY = row['leftEyeY'] as double?;
      final rightEyeX = row['rightEyeX'] as double?;
      final rightEyeY = row['rightEyeY'] as double?;
      return CachedFace(
        boundingBox: Rect.fromLTRB(left, top, right, bottom),
        leftEye: leftEyeX != null && leftEyeY != null
            ? Point<double>(leftEyeX, leftEyeY)
            : null,
        rightEye: rightEyeX != null && rightEyeY != null
            ? Point<double>(rightEyeX, rightEyeY)
            : null,
      );
    }).toList();

    return FaceDetectionCacheResult(
      orientation: orientation,
      faces: entries,
      selectedFaceIndex: selectedFaceIndex,
    );
  }

  /// Persists a successful detection's faces under [orientation] (one of
  /// 'original', 'flipped', 'ccw', 'cw'). Replaces any existing entry for
  /// (timestamp, projectId). For the "no faces found" result, use
  /// [writeNoFacesSentinel] instead.
  Future<void> writeFaceDetectionCache(
    String timestamp,
    int projectId,
    String orientation,
    List<Map<String, Object?>> faceRows,
    String modelVersion,
    String fingerprint, {
    int? selectedFaceIndex,
  }) async {
    if (orientation == 'no_faces') {
      throw ArgumentError(
        'writeFaceDetectionCache: use writeNoFacesSentinel for no_faces',
      );
    }
    if (faceRows.isEmpty) {
      throw ArgumentError(
        'writeFaceDetectionCache: faceRows must be non-empty',
      );
    }
    if (selectedFaceIndex != null &&
        (selectedFaceIndex < 0 || selectedFaceIndex >= faceRows.length)) {
      throw ArgumentError(
        'writeFaceDetectionCache: selectedFaceIndex out of range',
      );
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        faceDetectionCacheTable,
        where: 'timestamp = ? AND projectID = ?',
        whereArgs: [timestamp, projectId],
      );

      for (int i = 0; i < faceRows.length; i++) {
        final face = faceRows[i];
        await txn.insert(
            faceDetectionCacheTable,
            {
              'timestamp': timestamp,
              'projectID': projectId,
              'orientation': orientation,
              'faceIndex': i,
              'selectedFaceIndex': selectedFaceIndex,
              'boundingBoxLeft': face['boundingBoxLeft'],
              'boundingBoxTop': face['boundingBoxTop'],
              'boundingBoxRight': face['boundingBoxRight'],
              'boundingBoxBottom': face['boundingBoxBottom'],
              'leftEyeX': face['leftEyeX'],
              'leftEyeY': face['leftEyeY'],
              'rightEyeX': face['rightEyeX'],
              'rightEyeY': face['rightEyeY'],
              'modelVersion': modelVersion,
              'fingerprint': fingerprint,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Records that no faces were found across any orientation. Replaces any
  /// existing entry for (timestamp, projectId).
  Future<void> writeNoFacesSentinel(
    String timestamp,
    int projectId,
    String modelVersion,
    String fingerprint,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        faceDetectionCacheTable,
        where: 'timestamp = ? AND projectID = ?',
        whereArgs: [timestamp, projectId],
      );
      await txn.insert(
          faceDetectionCacheTable,
          {
            'timestamp': timestamp,
            'projectID': projectId,
            'orientation': 'no_faces',
            'faceIndex': -1,
            'selectedFaceIndex': null,
            'boundingBoxLeft': null,
            'boundingBoxTop': null,
            'boundingBoxRight': null,
            'boundingBoxBottom': null,
            'leftEyeX': null,
            'leftEyeY': null,
            'rightEyeX': null,
            'rightEyeY': null,
            'modelVersion': modelVersion,
            'fingerprint': fingerprint,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> clearFaceDetectionCacheForProject(int projectId) async {
    final db = await database;
    await db.delete(
      faceDetectionCacheTable,
      where: 'projectID = ?',
      whereArgs: [projectId],
    );
  }

  /* ┌──────────────────────────────┐
     │                              │
     │      Transform Cache         │
     │                              │
     └──────────────────────────────┘ */

  Future<TransformCacheEntry?> getTransformCache(String cacheKey) =>
      _querySingle(
          transformCacheTable,
          'cacheKey = ?',
          [
            cacheKey,
          ],
          TransformCacheEntry.fromMap);

  Future<void> writeTransformCache(TransformCacheEntry entry) async {
    final db = await database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        transformCacheTable,
        columns: ['id', 'createdAt'],
        where: 'cacheKey = ?',
        whereArgs: [entry.cacheKey],
        limit: 1,
      );

      if (existing.isEmpty) {
        await txn.insert(transformCacheTable, entry.toMap());
        return;
      }

      final row = existing.first;
      final map = entry
          .copyWith(
            id: row['id'] as int?,
            createdAt: row['createdAt'] as int?,
          )
          .toMap();
      await txn.update(
        transformCacheTable,
        map,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    });
  }

  Future<void> clearTransformCacheForProject(int projectId) async {
    final db = await database;
    await db.delete(
      transformCacheTable,
      where: 'projectID = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> clearTransformCacheForFingerprint(
    int projectId,
    String fingerprint, {
    String? settingsHash,
    // Pass null to clear all scopes (auto + manual). Defaults to 'auto' so
    // existing callers that intentionally preserve manual overrides are unaffected.
    String? scope = 'auto',
  }) async {
    final db = await database;
    final where = StringBuffer('projectID = ? AND fingerprint = ?');
    final whereArgs = <Object?>[projectId, fingerprint];
    if (scope != null) {
      where.write(' AND scope = ?');
      whereArgs.add(scope);
    }
    if (settingsHash != null) {
      where.write(' AND settingsHash = ?');
      whereArgs.add(settingsHash);
    }

    await db.delete(
      transformCacheTable,
      where: where.toString(),
      whereArgs: whereArgs,
    );
  }
}

/// Represents a custom font installed by the user.
/// This class is defined here to avoid circular imports with custom_font_manager.dart.
class CustomFont {
  final int id;
  final String displayName;
  final String familyName;
  final String filePath;
  final int fileSize;
  final int installedAt;

  const CustomFont({
    required this.id,
    required this.displayName,
    required this.familyName,
    required this.filePath,
    required this.fileSize,
    required this.installedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'familyName': familyName,
        'filePath': filePath,
        'fileSize': fileSize,
        'installedAt': installedAt,
      };

  factory CustomFont.fromJson(Map<String, dynamic> json) => CustomFont(
        id: json['id'] as int,
        displayName: json['displayName'] as String,
        familyName: json['familyName'] as String,
        filePath: json['filePath'] as String,
        fileSize: json['fileSize'] as int,
        installedAt: json['installedAt'] as int,
      );

  @override
  String toString() => 'CustomFont($displayName, $familyName)';
}
