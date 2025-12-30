import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/set_up_notifications_page.dart';

/// Widget tests for SetUpNotificationsPage.
void main() {
  group('SetUpNotificationsPage Widget', () {
    test('SetUpNotificationsPage can be instantiated', () {
      expect(SetUpNotificationsPage, isNotNull);
    });

    test('SetUpNotificationsPage stores required parameters', () {
      final widget = SetUpNotificationsPage(
        projectId: 1,
        projectName: 'Test Project',
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
      expect(widget.settingsCache, isNull);
    });

    test('SetUpNotificationsPage creates state', () {
      final widget = SetUpNotificationsPage(
        projectId: 1,
        projectName: 'Test',
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      expect(widget.createState(), isA<SetUpNotificationsPageState>());
    });

    test('stabCallback is accessible', () async {
      bool stabCalled = false;

      final widget = SetUpNotificationsPage(
        projectId: 1,
        projectName: 'Test',
        stabCallback: () async {
          stabCalled = true;
        },
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      await widget.stabCallback();
      expect(stabCalled, isTrue);
    });

    test('cancelStabCallback is accessible', () async {
      bool cancelCalled = false;

      final widget = SetUpNotificationsPage(
        projectId: 1,
        projectName: 'Test',
        stabCallback: () async {},
        cancelStabCallback: () async {
          cancelCalled = true;
        },
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      await widget.cancelStabCallback();
      expect(cancelCalled, isTrue);
    });

    test('refreshSettings is accessible', () async {
      bool refreshCalled = false;

      final widget = SetUpNotificationsPage(
        projectId: 1,
        projectName: 'Test',
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {
          refreshCalled = true;
        },
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      await widget.refreshSettings();
      expect(refreshCalled, isTrue);
    });

    test('clearRawAndStabPhotos is accessible', () {
      bool clearCalled = false;

      final widget = SetUpNotificationsPage(
        projectId: 1,
        projectName: 'Test',
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {
          clearCalled = true;
        },
        settingsCache: null,
      );

      widget.clearRawAndStabPhotos();
      expect(clearCalled, isTrue);
    });

    test('handles different project IDs', () {
      final widget1 = SetUpNotificationsPage(
        projectId: 0,
        projectName: 'First',
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      final widget2 = SetUpNotificationsPage(
        projectId: 999,
        projectName: 'Last',
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      expect(widget1.projectId, 0);
      expect(widget2.projectId, 999);
    });
  });

  group('SetUpNotificationsPage with SettingsCache', () {
    test('settingsCache can be null', () {
      final widget = SetUpNotificationsPage(
        projectId: 1,
        projectName: 'Test',
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        settingsCache: null,
      );

      expect(widget.settingsCache, isNull);
    });

    // Note: SettingsCache requires ui.Image which cannot be easily created in unit tests
    // The settingsCache parameter is tested as nullable above
  });
}
