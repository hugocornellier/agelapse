import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/info_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Widget tests for InfoPage.
void main() {
  group('InfoPage Widget', () {
    test('InfoPage can be instantiated', () {
      expect(InfoPage, isNotNull);
    });

    test('InfoPage stores required parameters', () {
      final widget = InfoPage(
        projectId: 1,
        projectName: 'Test Project',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {},
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
      expect(widget.stabilizingRunningInMain, isFalse);
    });

    test('InfoPage creates state', () {
      final widget = InfoPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {},
      );

      expect(widget.createState(), isA<InfoPageState>());
    });

    test('goToPage callback is stored correctly', () {
      int? receivedIndex;

      final widget = InfoPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: false,
        goToPage: (index) {
          receivedIndex = index;
        },
      );

      widget.goToPage(4);
      expect(receivedIndex, 4);
    });

    test('cancelStabCallback is accessible', () async {
      bool cancelCalled = false;

      final widget = InfoPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {
          cancelCalled = true;
        },
        stabilizingRunningInMain: false,
        goToPage: (index) {},
      );

      await widget.cancelStabCallback();
      expect(cancelCalled, isTrue);
    });
  });

  group('InfoPage State Combinations', () {
    test('handles stabilizing state', () {
      final widget = InfoPage(
        projectId: 1,
        projectName: 'Test',
        cancelStabCallback: () async {},
        stabilizingRunningInMain: true,
        goToPage: (index) {},
      );

      expect(widget.stabilizingRunningInMain, isTrue);
    });
  });

  group('InfoPage version label', () {
    test('hides build metadata for stable versions', () {
      final label = formatInfoVersionLabel(
        PackageInfo(
          appName: 'AgeLapse',
          packageName: 'com.hugocornellier.agelapse',
          version: '2.7.0',
          buildNumber: '44',
        ),
      );

      expect(label, 'Version: 2.7.0');
    });

    test('normalizes semver pre-release suffixes', () {
      final label = formatInfoVersionLabel(
        PackageInfo(
          appName: 'AgeLapse',
          packageName: 'com.hugocornellier.agelapse',
          version: '2.7.0-pre',
          buildNumber: '44',
        ),
      );

      expect(label, 'Version: 2.7.0 (Pre-Release)');
    });

    test('marks normalized Apple bundle versions as pre-release', () {
      final label = formatInfoVersionLabel(
        PackageInfo(
          appName: 'AgeLapse',
          packageName: 'com.hugocornellier.agelapse',
          version: '2.7.0',
          buildNumber: '44',
        ),
        forcePreRelease: true,
      );

      expect(label, 'Version: 2.7.0 (Pre-Release)');
    });
  });
}
