import 'dart:ui' as ui;

import '../utils/project_utils.dart';
import '../utils/linked_source_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import 'database_helper.dart';

class SettingsCache {
  bool hasOpenedNonEmptyGallery;
  bool? isLightTheme;
  bool noPhotos;
  bool hasViewedFirstVideo;
  bool hasOpenedNotifications;
  bool hasTakenMoreThanOnePhoto;
  bool hasSeenGuideModeTut;
  bool hasTakenFirstPhoto;
  int streak;
  int photoCount;
  String firstPhotoDate;
  String lastPhotoDate;
  int lengthInDays;
  String projectOrientation;
  String aspectRatio;
  String resolution;
  bool watermarkEnabled;
  ui.Image? image;
  double eyeOffsetX;
  double eyeOffsetY;
  bool galleryDateLabelsEnabled;
  bool exportDateStampEnabled;
  bool linkedSourceEnabled;
  String linkedSourceMode;
  String linkedSourceDisplayPath;
  String linkedSourceRootPath;
  String linkedSourceTreeUri;
  String linkedSourceBookmark;
  bool linkedSourceManagedByApp;
  int linkedSourceLastScanStartedAt;
  int linkedSourceLastScanCompletedAt;

  SettingsCache({
    required this.hasOpenedNonEmptyGallery,
    required this.isLightTheme,
    required this.noPhotos,
    required this.hasViewedFirstVideo,
    required this.hasOpenedNotifications,
    required this.hasTakenMoreThanOnePhoto,
    required this.hasSeenGuideModeTut,
    required this.hasTakenFirstPhoto,
    required this.streak,
    required this.photoCount,
    required this.firstPhotoDate,
    required this.lastPhotoDate,
    required this.lengthInDays,
    required this.projectOrientation,
    required this.aspectRatio,
    required this.resolution,
    required this.watermarkEnabled,
    required this.image,
    required this.eyeOffsetX,
    required this.eyeOffsetY,
    required this.galleryDateLabelsEnabled,
    required this.exportDateStampEnabled,
    this.linkedSourceEnabled = false,
    this.linkedSourceMode = 'none',
    this.linkedSourceDisplayPath = '',
    this.linkedSourceRootPath = '',
    this.linkedSourceTreeUri = '',
    this.linkedSourceBookmark = '',
    this.linkedSourceManagedByApp = false,
    this.linkedSourceLastScanStartedAt = 0,
    this.linkedSourceLastScanCompletedAt = 0,
  });

  /// Dispose native resources. Call this when the cache is no longer needed.
  void dispose() {
    image?.dispose();
    image = null;
  }

  static Future<SettingsCache> initialize(int projectId) async {
    final List<dynamic> settings = await Future.wait([
      SettingsUtil.hasOpenedNonEmptyGallery(projectId.toString()),
      SettingsUtil.lightThemeActive(),
      DB.instance.getPhotoCountByProjectID(projectId),
      SettingsUtil.hasSeenFirstVideo(projectId.toString()),
      SettingsUtil.hasOpenedNotifPage(projectId.toString()),
      DB.instance.getEarliestPhotoTimestamp(projectId),
      DB.instance.getLatestPhotoTimestamp(projectId),
      ProjectUtils.calculateStreak(projectId),
      SettingsUtil.loadProjectOrientation(projectId.toString()),
      SettingsUtil.loadAspectRatio(projectId.toString()),
      SettingsUtil.loadVideoResolution(projectId.toString()),
      SettingsUtil.loadWatermarkSetting(projectId.toString()),
      ProjectUtils.loadSvgImage(
        'assets/images/person-grey.svg',
        width: 400,
        height: 480,
      ),
      SettingsUtil.loadOffsetXCurrentOrientation(projectId.toString()),
      SettingsUtil.loadOffsetYCurrentOrientation(projectId.toString()),
      SettingsUtil.hasSeenGuideModeTut(projectId.toString()),
      SettingsUtil.hasTakenFirstPhoto(projectId.toString()),
      SettingsUtil.loadGalleryDateLabelsEnabled(projectId.toString()),
      SettingsUtil.loadExportDateStampEnabled(projectId.toString()),
      LinkedSourceUtils.loadConfig(projectId),
    ]);

    final int photoCount = settings[2] as int;
    final int? firstPhotoTimestamp =
        settings[5] != null ? int.tryParse(settings[5] as String) : null;
    final int? latestPhotoTimestamp =
        settings[6] != null ? int.tryParse(settings[6] as String) : null;
    final int? streak = settings[7] as int?;

    return SettingsCache(
      hasOpenedNonEmptyGallery: settings[0] as bool? ?? false,
      isLightTheme: settings[1] as bool?,
      noPhotos: photoCount == 0,
      hasViewedFirstVideo: settings[3] as bool? ?? false,
      hasOpenedNotifications: settings[4] as bool? ?? false,
      hasTakenMoreThanOnePhoto: photoCount > 1,
      hasSeenGuideModeTut: settings[15] as bool? ?? false,
      hasTakenFirstPhoto: settings[16] as bool? ?? false,
      streak: streak ?? 0,
      photoCount: photoCount,
      firstPhotoDate: firstPhotoTimestamp != null
          ? Utils.formatUnixTimestamp(firstPhotoTimestamp)
          : '',
      lastPhotoDate: latestPhotoTimestamp != null
          ? Utils.formatUnixTimestamp(latestPhotoTimestamp)
          : '',
      lengthInDays: firstPhotoTimestamp != null && latestPhotoTimestamp != null
          ? ProjectUtils.calculateDateDifference(
                firstPhotoTimestamp,
                latestPhotoTimestamp,
              ).inDays +
              1
          : 0,
      projectOrientation: settings[8] as String,
      aspectRatio: settings[9] as String,
      resolution: settings[10] as String,
      watermarkEnabled: settings[11] as bool,
      image: settings[12] as ui.Image,
      eyeOffsetX: double.tryParse(settings[13] as String) ?? 0.065,
      eyeOffsetY: double.tryParse(settings[14] as String) ?? 0.421875,
      galleryDateLabelsEnabled: settings[17] as bool? ?? false,
      exportDateStampEnabled: settings[18] as bool? ?? false,
      linkedSourceEnabled: (settings[19] as LinkedSourceConfig).enabled,
      linkedSourceMode: (settings[19] as LinkedSourceConfig).mode,
      linkedSourceDisplayPath: (settings[19] as LinkedSourceConfig).displayPath,
      linkedSourceRootPath: (settings[19] as LinkedSourceConfig).rootPath,
      linkedSourceTreeUri: (settings[19] as LinkedSourceConfig).treeUri,
      linkedSourceBookmark: (settings[19] as LinkedSourceConfig).bookmark,
      linkedSourceManagedByApp:
          (settings[19] as LinkedSourceConfig).managedByApp,
      linkedSourceLastScanStartedAt:
          (settings[19] as LinkedSourceConfig).lastScanStartedAt,
      linkedSourceLastScanCompletedAt:
          (settings[19] as LinkedSourceConfig).lastScanCompletedAt,
    );
  }

  static Future<SettingsCache> initializeWithDefaults() async {
    const defaults = DB.defaultValues;

    return SettingsCache(
      hasOpenedNonEmptyGallery: defaults['opened_nonempty_gallery'] == 'true',
      isLightTheme: defaults['theme'] == 'light',
      noPhotos: true,
      hasViewedFirstVideo: defaults['has_viewed_first_video'] == 'false',
      hasOpenedNotifications: defaults['has_opened_notif_page'] == 'false',
      hasTakenMoreThanOnePhoto: false,
      hasSeenGuideModeTut: defaults['has_seen_guide_mode_tut'] == 'false',
      hasTakenFirstPhoto: defaults['has_taken_first_photo'] == 'false',
      streak: 0,
      photoCount: 0,
      firstPhotoDate: '',
      lastPhotoDate: '',
      lengthInDays: 0,
      projectOrientation: defaults['project_orientation']!,
      aspectRatio: defaults['aspect_ratio']!,
      resolution: defaults['video_resolution']!,
      watermarkEnabled: defaults['enable_watermark'] == 'true',
      image: await ProjectUtils.loadSvgImage(
        'assets/images/person-grey.svg',
        width: 400,
        height: 480,
      ),
      eyeOffsetX: double.parse(defaults['eyeOffsetXPortrait']!),
      eyeOffsetY: double.parse(defaults['eyeOffsetYPortrait']!),
      galleryDateLabelsEnabled: false,
      exportDateStampEnabled: false,
      linkedSourceEnabled: defaults['linked_source_enabled'] == 'true',
      linkedSourceMode: defaults['linked_source_mode']!,
      linkedSourceDisplayPath: defaults['linked_source_display_path']!,
      linkedSourceRootPath: defaults['linked_source_root_path']!,
      linkedSourceTreeUri: defaults['linked_source_tree_uri']!,
      linkedSourceBookmark: defaults['linked_source_bookmark']!,
      linkedSourceManagedByApp:
          defaults['linked_source_managed_by_app'] == 'true',
      linkedSourceLastScanStartedAt:
          int.tryParse(defaults['linked_source_last_scan_started_at']!) ?? 0,
      linkedSourceLastScanCompletedAt:
          int.tryParse(defaults['linked_source_last_scan_completed_at']!) ?? 0,
    );
  }
}
