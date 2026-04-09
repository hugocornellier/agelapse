/// Mobile "video" aggregator — runs all video-related integration tests in a
/// single app build + launch.
///
/// File name deliberately omits the `_test.dart` suffix so `flutter test
/// integration_test/` won't auto-discover it.
///
/// Run with: `flutter test integration_test/mobile_video.dart -d <device>`
library;

import 'package:integration_test/integration_test.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

import 'video_compilation_test.dart' as video_compilation_tests;
import 'video_codec_test.dart' as video_codec_tests;
import 'video_playback_test.dart' as video_playback_tests;
import 'settings_pipeline_test.dart' as settings_pipeline_tests;
import 'e2e_pipeline_test.dart' as e2e_pipeline_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  video_compilation_tests.main();
  video_codec_tests.main();
  video_playback_tests.main();
  settings_pipeline_tests.main();
  e2e_pipeline_tests.main();
}
