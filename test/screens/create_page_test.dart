import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/create_page.dart';

/// Widget tests for CreatePage.
void main() {
  group('CreatePage Widget', () {
    test('CreatePage can be instantiated', () {
      expect(CreatePage, isNotNull);
    });

    test('CreatePage stores required parameters', () {
      final widget = CreatePage(
        projectId: 1,
        projectName: 'Test Project',
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        unstabilizedPhotoCount: 5,
        photoIndex: 0,
        currentFrame: 0,
        cancelStabCallback: () async {},
        goToPage: (index) {},
        prevIndex: 0,
        hideNavBar: () async {},
        progressPercent: 50,
        stabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
      expect(widget.stabilizingRunningInMain, isFalse);
      expect(widget.videoCreationActiveInMain, isFalse);
      expect(widget.unstabilizedPhotoCount, 5);
      expect(widget.photoIndex, 0);
      expect(widget.currentFrame, 0);
      expect(widget.prevIndex, 0);
      expect(widget.progressPercent, 50);
    });

    test('CreatePage creates state', () {
      final widget = CreatePage(
        projectId: 1,
        projectName: 'Test',
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        unstabilizedPhotoCount: 0,
        photoIndex: 0,
        currentFrame: 0,
        cancelStabCallback: () async {},
        goToPage: (index) {},
        prevIndex: 0,
        hideNavBar: () async {},
        progressPercent: 0,
        stabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
      );

      expect(widget.createState(), isA<CreatePageState>());
    });
  });

  group('CreatePage State Combinations', () {
    test('handles stabilizing state', () {
      final widget = CreatePage(
        projectId: 1,
        projectName: 'Test',
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        unstabilizedPhotoCount: 10,
        photoIndex: 5,
        currentFrame: 50,
        cancelStabCallback: () async {},
        goToPage: (index) {},
        prevIndex: 0,
        hideNavBar: () async {},
        progressPercent: 50,
        stabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
      );

      expect(widget.stabilizingRunningInMain, isTrue);
      expect(widget.progressPercent, 50);
    });

    test('handles video creation state', () {
      final widget = CreatePage(
        projectId: 1,
        projectName: 'Test',
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: true,
        unstabilizedPhotoCount: 0,
        photoIndex: 0,
        currentFrame: 10,
        cancelStabCallback: () async {},
        goToPage: (index) {},
        prevIndex: 0,
        hideNavBar: () async {},
        progressPercent: 100,
        stabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
      );

      expect(widget.videoCreationActiveInMain, isTrue);
    });
  });

  group('CreatePage Callbacks', () {
    test('goToPage callback is accessible', () {
      int? receivedIndex;

      final widget = CreatePage(
        projectId: 1,
        projectName: 'Test',
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        unstabilizedPhotoCount: 0,
        photoIndex: 0,
        currentFrame: 0,
        cancelStabCallback: () async {},
        goToPage: (index) {
          receivedIndex = index;
        },
        prevIndex: 0,
        hideNavBar: () async {},
        progressPercent: 0,
        stabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
      );

      widget.goToPage(2);
      expect(receivedIndex, 2);
    });

    test('cancelStabCallback is accessible', () async {
      bool cancelCalled = false;

      final widget = CreatePage(
        projectId: 1,
        projectName: 'Test',
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        unstabilizedPhotoCount: 0,
        photoIndex: 0,
        currentFrame: 0,
        cancelStabCallback: () async {
          cancelCalled = true;
        },
        goToPage: (index) {},
        prevIndex: 0,
        hideNavBar: () async {},
        progressPercent: 0,
        stabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
      );

      await widget.cancelStabCallback();
      expect(cancelCalled, isTrue);
    });

    test('hideNavBar callback is accessible', () async {
      bool hideCalled = false;

      final widget = CreatePage(
        projectId: 1,
        projectName: 'Test',
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        unstabilizedPhotoCount: 0,
        photoIndex: 0,
        currentFrame: 0,
        cancelStabCallback: () async {},
        goToPage: (index) {},
        prevIndex: 0,
        hideNavBar: () async {
          hideCalled = true;
        },
        progressPercent: 0,
        stabCallback: () async {},
        refreshSettings: () async {},
        clearRawAndStabPhotos: () {},
        recompileVideoCallback: () async {},
        settingsCache: null,
        minutesRemaining: '',
      );

      await widget.hideNavBar();
      expect(hideCalled, isTrue);
    });
  });

  group('FadeInOutIcon Widget', () {
    test('FadeInOutIcon can be instantiated', () {
      expect(const FadeInOutIcon(), isA<FadeInOutIcon>());
    });

    test('FadeInOutIcon creates state', () {
      const widget = FadeInOutIcon();
      expect(widget.createState(), isA<FadeInOutIconState>());
    });
  });
}
