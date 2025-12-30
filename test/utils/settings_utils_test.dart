import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/settings_utils.dart';

/// Unit tests for SettingsUtil.
/// Tests settings loading methods.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SettingsUtil Loading Methods', () {
    test('loadEnableGrid returns Future<bool>', () {
      final result = SettingsUtil.loadEnableGrid();
      expect(result, isA<Future<bool>>());
    });

    test('loadSaveToCameraRoll returns Future<bool>', () {
      final result = SettingsUtil.loadSaveToCameraRoll();
      expect(result, isA<Future<bool>>());
    });

    test('loadCameraMirror returns Future<bool>', () async {
      final result = SettingsUtil.loadCameraMirror('1');
      expect(result, isA<Future<bool>>());
      // Await to handle async error (path_provider not available in tests)
      try {
        await result;
      } on MissingPluginException {
        // Expected in test environment without path_provider
      }
    });

    test('loadNotificationSetting returns Future<bool>', () {
      final result = SettingsUtil.loadNotificationSetting();
      expect(result, isA<Future<bool>>());
    });

    test('loadProjectOrientation returns Future<String>', () async {
      final result = SettingsUtil.loadProjectOrientation('1');
      expect(result, isA<Future<String>>());
      // Await to handle async error (path_provider not available in tests)
      try {
        await result;
      } on MissingPluginException {
        // Expected in test environment without path_provider
      }
    });
  });

  group('SettingsUtil Method Signatures', () {
    test('loadEnableGrid accepts no parameters', () {
      // Should compile and return Future<bool>
      final result = SettingsUtil.loadEnableGrid();
      expect(result, isA<Future<bool>>());
    });

    test('loadProjectOrientation accepts project ID string', () async {
      // Should compile and return Future<String>
      final result1 = SettingsUtil.loadProjectOrientation('1');
      final result2 = SettingsUtil.loadProjectOrientation('999');
      final result3 = SettingsUtil.loadProjectOrientation('test');

      expect(result1, isA<Future<String>>());
      expect(result2, isA<Future<String>>());
      expect(result3, isA<Future<String>>());

      // Await to handle async errors (path_provider not available in tests)
      for (final future in [result1, result2, result3]) {
        try {
          await future;
        } on MissingPluginException {
          // Expected in test environment without path_provider
        }
      }
    });
  });
}
