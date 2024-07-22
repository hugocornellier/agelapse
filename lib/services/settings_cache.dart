import 'dart:ui' as ui;

import '../utils/project_utils.dart';
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
  bool hasSeenGuideModeTut; // New value
  bool hasTakenFirstPhoto;  // New value
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

  SettingsCache({
    required this.hasOpenedNonEmptyGallery,
    required this.isLightTheme,
    required this.noPhotos,
    required this.hasViewedFirstVideo,
    required this.hasOpenedNotifications,
    required this.hasTakenMoreThanOnePhoto,
    required this.hasSeenGuideModeTut, // New value
    required this.hasTakenFirstPhoto,  // New value
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
  });

  static Future<SettingsCache> initialize(int projectId) async {
    final List<dynamic> settings = await Future.wait([
      SettingsUtil.hasOpenedNonEmptyGallery(projectId.toString()),
      SettingsUtil.lightThemeActive(),
      DB.instance.getPhotosByProjectID(projectId),
      SettingsUtil.hasSeenFirstVideo(projectId.toString()),
      SettingsUtil.hasOpenedNotifPage(projectId.toString()),
      DB.instance.getEarliestPhotoTimestamp(projectId),
      DB.instance.getLatestPhotoTimestamp(projectId),
      ProjectUtils.calculateStreak(projectId),
      SettingsUtil.loadProjectOrientation(projectId.toString()),
      SettingsUtil.loadAspectRatio(projectId.toString()),
      SettingsUtil.loadVideoResolution(projectId.toString()),
      SettingsUtil.loadWatermarkSetting(projectId.toString()),
      ProjectUtils.loadImage('assets/images/person-grey.png'),
      SettingsUtil.loadOffsetXCurrentOrientation(projectId.toString()),
      SettingsUtil.loadOffsetYCurrentOrientation(projectId.toString()),
      SettingsUtil.hasSeenGuideModeTut(projectId.toString()),  // New value
      SettingsUtil.hasTakenFirstPhoto(projectId.toString()),   // New value
    ]);

    final List<Map<String, dynamic>> allPhotos = settings[2] as List<Map<String, dynamic>>;
    final int? firstPhotoTimestamp = settings[5] != null ? int.tryParse(settings[5] as String) : null;
    final int? latestPhotoTimestamp = settings[6] != null ? int.tryParse(settings[6] as String) : null;
    final int? streak = settings[7] as int?;

    return SettingsCache(
      hasOpenedNonEmptyGallery: settings[0] as bool? ?? false,
      isLightTheme: settings[1] as bool?,
      noPhotos: allPhotos.isEmpty,
      hasViewedFirstVideo: settings[3] as bool? ?? false,
      hasOpenedNotifications: settings[4] as bool? ?? false,
      hasTakenMoreThanOnePhoto: allPhotos.length > 1,
      hasSeenGuideModeTut: settings[15] as bool? ?? false,  // New value
      hasTakenFirstPhoto: settings[16] as bool? ?? false,   // New value
      streak: streak ?? 0,
      photoCount: allPhotos.length,
      firstPhotoDate: firstPhotoTimestamp != null ? Utils.formatUnixTimestamp(firstPhotoTimestamp) : '',
      lastPhotoDate: latestPhotoTimestamp != null ? Utils.formatUnixTimestamp(latestPhotoTimestamp) : '',
      lengthInDays: firstPhotoTimestamp != null && latestPhotoTimestamp != null
          ? ProjectUtils.calculateDateDifference(firstPhotoTimestamp, latestPhotoTimestamp).inDays + 1
          : 0,
      projectOrientation: settings[8] as String,
      aspectRatio: settings[9] as String,
      resolution: settings[10] as String,
      watermarkEnabled: settings[11] as bool,
      image: settings[12] as ui.Image,
      eyeOffsetX: double.parse(settings[13] as String),
      eyeOffsetY: double.parse(settings[14] as String),
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
      image: await ProjectUtils.loadImage('assets/images/person-grey.png'),
      eyeOffsetX: double.parse(defaults['eyeOffsetXPortrait']!),
      eyeOffsetY: double.parse(defaults['eyeOffsetYPortrait']!),
    );
  }
}
