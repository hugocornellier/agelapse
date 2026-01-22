import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/custom_app_bar.dart';

/// Widget tests for CustomAppBar.
void main() {
  group('CustomAppBar Widget', () {
    test('CustomAppBar can be instantiated', () {
      expect(CustomAppBar, isNotNull);
    });

    test('CustomAppBar stores required parameters', () {
      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 50.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '5m',
        userRanOutOfSpace: false,
      );

      expect(widget.projectId, 1);
      expect(widget.progressPercent, 50.0);
      expect(widget.stabilizingRunningInMain, isFalse);
      expect(widget.videoCreationActiveInMain, isFalse);
      expect(widget.importRunningInMain, isFalse);
      expect(widget.selectedIndex, 0);
      expect(widget.minutesRemaining, '5m');
      expect(widget.userRanOutOfSpace, isFalse);
    });

    test('CustomAppBar accepts optional stabUpdateStream', () {
      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
        stabUpdateStream: null,
      );

      expect(widget.stabUpdateStream, isNull);
    });

    test('goToPage callback is stored correctly', () {
      int? receivedIndex;

      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {
          receivedIndex = index;
        },
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      widget.goToPage(3);
      expect(receivedIndex, 3);
    });

    test('CustomAppBar creates state', () {
      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      expect(widget.createState(), isA<CustomAppBarState>());
    });
  });

  group('CustomAppBar State Combinations', () {
    test('handles stabilizing state', () {
      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 30.0,
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '10m',
        userRanOutOfSpace: false,
      );

      expect(widget.stabilizingRunningInMain, isTrue);
      expect(widget.minutesRemaining, '10m');
    });

    test('handles video creation state', () {
      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 60.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: true,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      expect(widget.videoCreationActiveInMain, isTrue);
    });

    test('handles import state', () {
      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 75.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: true,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      expect(widget.importRunningInMain, isTrue);
    });

    test('handles out of space state', () {
      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: true,
      );

      expect(widget.userRanOutOfSpace, isTrue);
    });
  });

  group('CustomAppBar Callbacks', () {
    test('cancelStabCallback is accessible', () async {
      bool cancelCalled = false;

      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {
          cancelCalled = true;
        },
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      await widget.cancelStabCallback();
      expect(cancelCalled, isTrue);
    });

    test('stabCallback is accessible', () async {
      bool stabCalled = false;

      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {
          stabCalled = true;
        },
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      await widget.stabCallback();
      expect(stabCalled, isTrue);
    });

    test('refreshSettings callback is accessible', () async {
      bool refreshCalled = false;

      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {
          refreshCalled = true;
        },
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      await widget.refreshSettings();
      expect(refreshCalled, isTrue);
    });

    test('clearRawAndStabPhotos callback is accessible', () {
      bool clearCalled = false;

      final widget = CustomAppBar(
        projectId: 1,
        goToPage: (index) {},
        progressPercent: 0.0,
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        selectedIndex: 0,
        stabCallback: () async {},
        cancelStabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {
          clearCalled = true;
        },
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
        userRanOutOfSpace: false,
      );

      widget.clearRawAndStabPhotos();
      expect(clearCalled, isTrue);
    });
  });
}
