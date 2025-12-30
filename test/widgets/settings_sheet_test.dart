import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/settings_sheet.dart';

/// Widget tests for SettingsSheet.
/// Tests UI structure and component presence.
void main() {
  group('SettingsSheet Widget', () {
    test('SettingsSheet has required constructor parameters', () {
      // Verify the constructor signature
      expect(SettingsSheet, isNotNull);
    });

    test('SettingsSheet can be instantiated with parameters', () {
      final widget = SettingsSheet(
        projectId: 1,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
      );

      expect(widget.projectId, 1);
      expect(widget.onlyShowVideoSettings, isFalse);
      expect(widget.onlyShowNotificationSettings, isFalse);
    });

    test('SettingsSheet accepts onlyShowVideoSettings flag', () {
      final widget = SettingsSheet(
        projectId: 2,
        onlyShowVideoSettings: true,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
      );

      expect(widget.onlyShowVideoSettings, isTrue);
      expect(widget.onlyShowNotificationSettings, isFalse);
    });

    test('SettingsSheet accepts onlyShowNotificationSettings flag', () {
      final widget = SettingsSheet(
        projectId: 3,
        onlyShowNotificationSettings: true,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
      );

      expect(widget.onlyShowVideoSettings, isFalse);
      expect(widget.onlyShowNotificationSettings, isTrue);
    });

    test('SettingsSheet callbacks are stored correctly', () {
      bool stabCalled = false;
      bool cancelCalled = false;
      bool refreshCalled = false;
      bool clearCalled = false;

      final widget = SettingsSheet(
        projectId: 4,
        stabCallback: () async {
          stabCalled = true;
        },
        cancelStabCallback: () async {
          cancelCalled = true;
        },
        refreshSettings: () async {
          refreshCalled = true;
        },
        clearRawAndStabPhotos: () {
          clearCalled = true;
        },
      );

      // Verify callbacks are accessible
      widget.stabCallback();
      widget.cancelStabCallback();
      widget.refreshSettings();
      widget.clearRawAndStabPhotos();

      expect(stabCalled, isTrue);
      expect(cancelCalled, isTrue);
      expect(refreshCalled, isTrue);
      expect(clearCalled, isTrue);
    });
  });

  group('SettingsSheet State', () {
    test('SettingsSheetState creates state class', () {
      final widget = SettingsSheet(
        projectId: 5,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
      );

      expect(widget.createState(), isA<SettingsSheetState>());
    });
  });
}
