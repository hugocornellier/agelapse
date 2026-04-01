/// Desktop "fast" aggregator — runs all non-video integration tests in a single
/// app build + launch.  If this works on desktop (single suite = single launch,
/// sidesteps the multi-file "debug connection" bug), it eliminates the need for
/// the sequential per-file workaround.
///
/// File name deliberately omits the `_test.dart` suffix so `flutter test
/// integration_test/` won't auto-discover it.
///
/// Run with: `flutter test integration_test/desktop_fast.dart -d macos`
library;

import 'package:integration_test/integration_test.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

import 'smoke_test.dart' as smoke_tests;
import 'app_test.dart' as app_tests;
import 'database_test.dart' as database_tests;
import 'error_handling_test.dart' as error_handling_tests;
import 'image_format_test.dart' as image_format_tests;
import 'stabilization_test.dart' as stabilization_tests;
import 'cat_stabilization_test.dart' as cat_stabilization_tests;
import 'dog_stabilization_test.dart' as dog_stabilization_tests;
import 'pose_stabilization_test.dart' as pose_stabilization_tests;
import 'export_test.dart' as export_tests;
import 'screenshot_test.dart' as screenshot_tests;
import 'e2e_workflow_test.dart' as e2e_workflow_tests;
import 'linked_source_sync_test.dart' as linked_source_sync_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test_config.isTestMode = true;

  smoke_tests.main();
  app_tests.main();
  database_tests.main();
  error_handling_tests.main();
  stabilization_tests.main();
  cat_stabilization_tests.main();
  dog_stabilization_tests.main();
  pose_stabilization_tests.main();
  export_tests.main();
  screenshot_tests.main();
  e2e_workflow_tests.main();
  linked_source_sync_tests.main();
  // image_format_test runs last: libheif DLL teardown can crash the process
  // on Windows, so all other tests must complete first.
  image_format_tests.main();
}
