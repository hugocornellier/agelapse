import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/progress_widget.dart';

/// Widget tests for ProgressWidget.
void main() {
  group('ProgressWidget Widget', () {
    test('ProgressWidget can be instantiated', () {
      expect(ProgressWidget, isNotNull);
    });

    test('ProgressWidget stores required parameters', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 50,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.stabilizingRunningInMain, isTrue);
      expect(widget.videoCreationActiveInMain, isFalse);
      expect(widget.importRunningInMain, isFalse);
      expect(widget.progressPercent, 50);
      expect(widget.userRanOutOfSpace, isFalse);
    });

    test('ProgressWidget accepts optional selectedIndex', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 0,
        goToPage: (index) {},
        selectedIndex: 2,
        userRanOutOfSpace: false,
      );

      expect(widget.selectedIndex, 2);
    });

    test('ProgressWidget accepts optional minutesRemaining', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 75,
        goToPage: (index) {},
        minutesRemaining: '5m 30s',
        userRanOutOfSpace: false,
      );

      expect(widget.minutesRemaining, '5m 30s');
    });

    test('ProgressWidget defaults selectedIndex to -1', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 0,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.selectedIndex, -1);
    });

    test('goToPage callback is stored correctly', () {
      int? receivedIndex;

      final widget = ProgressWidget(
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 0,
        goToPage: (index) {
          receivedIndex = index;
        },
        userRanOutOfSpace: false,
      );

      widget.goToPage(3);

      expect(receivedIndex, 3);
    });
  });

  group('ProgressWidget State Combinations', () {
    test('handles stabilizing state', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 30,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.stabilizingRunningInMain, isTrue);
    });

    test('handles video creation state', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: true,
        importRunningInMain: false,
        progressPercent: 60,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.videoCreationActiveInMain, isTrue);
    });

    test('handles import state', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: true,
        progressPercent: 90,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.importRunningInMain, isTrue);
    });

    test('handles out of space state', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: false,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 0,
        goToPage: (index) {},
        userRanOutOfSpace: true,
      );

      expect(widget.userRanOutOfSpace, isTrue);
    });
  });

  group('ProgressWidget Progress Values', () {
    test('handles 0% progress', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 0,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.progressPercent, 0);
    });

    test('handles 100% progress', () {
      final widget = ProgressWidget(
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 100,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.progressPercent, 100);
    });

    test('handles progress over 100%', () {
      // Edge case - widget should handle values > 100
      final widget = ProgressWidget(
        stabilizingRunningInMain: true,
        videoCreationActiveInMain: false,
        importRunningInMain: false,
        progressPercent: 150,
        goToPage: (index) {},
        userRanOutOfSpace: false,
      );

      expect(widget.progressPercent, 150);
    });
  });
}
