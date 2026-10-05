import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/video_diagnostics.dart';

/// Unit tests for [FrameCheck].
///
/// The verdict decides whether the iOS video player falls back from a Flutter
/// texture to a platform view. It must fall back when the screen is black but
/// the file has a picture (or decodes no frames at all), and must not fall back
/// for a video that is simply dark.
void main() {
  FrameCheck check({
    double screenLuma = 120,
    double screenChroma = 90,
    int framesDecoded = 36,
    double decodedLuma = 110,
  }) => FrameCheck(
    screenLuma: screenLuma,
    screenChroma: screenChroma,
    framesDecoded: framesDecoded,
    decodedLuma: decodedLuma,
  );

  group('FrameCheck', () {
    test('a picture on screen is ok', () {
      expect(check().verdict, FrameVerdict.ok);
      expect(check().shouldFallBackToPlatformView, isFalse);
    });

    test('black screen with a decoded picture is a rendering failure', () {
      final result = check(screenLuma: 0, screenChroma: 0);
      expect(result.verdict, FrameVerdict.notRendered);
      expect(result.shouldFallBackToPlatformView, isTrue);
    });

    test('black screen with no decoded frames falls back', () {
      final result = check(
        screenLuma: 2,
        screenChroma: 1,
        framesDecoded: 0,
        decodedLuma: 0,
      );
      expect(result.verdict, FrameVerdict.noFramesDecoded);
      expect(result.shouldFallBackToPlatformView, isTrue);
    });

    test('a dark video stays on the texture player', () {
      final result = check(screenLuma: 5, screenChroma: 2, decodedLuma: 10);
      expect(result.verdict, FrameVerdict.videoIsDark);
      expect(result.shouldFallBackToPlatformView, isFalse);
    });

    test('a dim but colorful screen is not black', () {
      expect(check(screenLuma: 8, screenChroma: 40).verdict, FrameVerdict.ok);
    });

    test('thresholds count their exact values as not black / visible', () {
      expect(
        check(
          screenLuma: FrameCheck.blackScreenLuma,
          screenChroma: 0,
        ).screenIsBlack,
        isFalse,
      );
      expect(
        check(
          screenLuma: 0,
          screenChroma: FrameCheck.blackScreenChroma,
        ).screenIsBlack,
        isFalse,
      );
      expect(
        check(
          screenLuma: 0,
          screenChroma: 0,
          decodedLuma: FrameCheck.visibleLuma,
        ).verdict,
        FrameVerdict.notRendered,
      );
    });
  });
}
