import 'package:integration_test/integration_test.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

import 'app_test.dart' as app_tests;
import 'database_test.dart' as database_tests;
import 'error_handling_test.dart' as error_handling_tests;
import 'export_test.dart' as export_tests;
import 'image_format_test.dart' as image_format_tests;
import 'stabilization_test.dart' as stabilization_tests;
import 'smoke_test.dart' as smoke_tests;
import 'video_codec_test.dart' as video_codec_tests;
import 'video_compilation_test.dart' as video_compilation_tests;
import 'video_playback_test.dart' as video_playback_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Enable test mode - uses isolated test database and skips window operations
  test_config.isTestMode = true;

  // Core smoke tests - validates critical app paths
  smoke_tests.main();

  // Basic app launch tests
  app_tests.main();

  // Database CRUD tests
  database_tests.main();

  // Error handling and edge case tests
  error_handling_tests.main();

  // Image format conversion tests (AVIF, HEIC)
  image_format_tests.main();

  // Stabilization algorithm tests
  stabilization_tests.main();

  // Video compilation tests
  video_compilation_tests.main();

  // Video codec tests (codec × resolution × transparency × orientation)
  video_codec_tests.main();

  // Video playback tests (compile then verify playback via VideoPlayerController)
  video_playback_tests.main();

  // Export ZIP tests
  export_tests.main();
}
