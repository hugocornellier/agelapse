import 'package:integration_test/integration_test.dart';
import 'package:agelapse/utils/test_mode.dart' as test_config;

import 'app_test.dart' as app_tests;
import 'database_test.dart' as database_tests;
import 'error_handling_test.dart' as error_handling_tests;
import 'image_format_test.dart' as image_format_tests;
import 'stabilization_test.dart' as stabilization_tests;
import 'smoke_test.dart' as smoke_tests;

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
}
