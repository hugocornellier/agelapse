import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/video_utils.dart';

void main() {
  group('VideoUtils', () {
    group('pickBitrateKbps', () {
      // Resolution setting string tests
      test('returns 100000 kbps for "8K" setting string', () {
        expect(VideoUtils.pickBitrateKbps('8K'), 100000);
      });

      test('returns 50000 kbps for "4K" setting string', () {
        expect(VideoUtils.pickBitrateKbps('4K'), 50000);
      });

      test('returns 14000 kbps for "1080p" setting string', () {
        expect(VideoUtils.pickBitrateKbps('1080p'), 14000);
      });

      // Custom numeric resolution string tests (short side value)
      test('calculates bitrate for custom numeric resolution "4320" (8K)', () {
        // 4320 short side with 16:9 aspect = 4320 * 7680 pixels
        expect(VideoUtils.pickBitrateKbps('4320'), 100000);
      });

      test('calculates bitrate for custom numeric resolution "2304" (4K)', () {
        // 2304 short side with 16:9 aspect = 2304 * 4096 pixels
        expect(VideoUtils.pickBitrateKbps('2304'), 50000);
      });

      test('calculates bitrate for custom numeric resolution "1728" (3K)', () {
        // 1728 short side with 16:9 aspect = 1728 * 3072 = 5,308,416 pixels
        // This is between 4K and 1440p thresholds, so returns 20000
        expect(VideoUtils.pickBitrateKbps('1728'), 20000);
      });

      test('calculates bitrate for custom numeric resolution "1440"', () {
        // 1440 short side with 16:9 aspect = 1440 * 2560 = 3,686,400 pixels
        // At 1440p threshold
        expect(VideoUtils.pickBitrateKbps('1440'), 20000);
      });

      test('calculates bitrate for custom numeric resolution "1080"', () {
        // 1080 short side with 16:9 aspect = 1080 * 1920 = 2,073,600 pixels
        expect(VideoUtils.pickBitrateKbps('1080'), 14000);
      });

      test('calculates bitrate for custom numeric resolution "720"', () {
        // 720 short side with 16:9 aspect = 720 * 1280 = 921,600 pixels
        expect(VideoUtils.pickBitrateKbps('720'), 8000);
      });

      test('calculates bitrate for custom numeric resolution "480"', () {
        // 480 short side with 16:9 aspect = 480 * 853 = ~409,440 pixels
        expect(VideoUtils.pickBitrateKbps('480'), 5000);
      });

      // Dimension string tests
      test('returns 100000 kbps for 8K resolution (7680x4320)', () {
        expect(VideoUtils.pickBitrateKbps('7680x4320'), 100000);
      });

      test('handles 8K portrait orientation (4320x7680)', () {
        expect(VideoUtils.pickBitrateKbps('4320x7680'), 100000);
      });

      test('handles 8K with 4:3 aspect ratio (5760x4320)', () {
        expect(VideoUtils.pickBitrateKbps('5760x4320'), 100000);
      });

      test('returns 50000 kbps for 4K resolution (3840x2160)', () {
        expect(VideoUtils.pickBitrateKbps('3840x2160'), 50000);
      });

      test('returns 20000 kbps for 1440p resolution (2560x1440)', () {
        expect(VideoUtils.pickBitrateKbps('2560x1440'), 20000);
      });

      test('returns 14000 kbps for 1080p resolution (1920x1080)', () {
        expect(VideoUtils.pickBitrateKbps('1920x1080'), 14000);
      });

      test('returns 8000 kbps for 720p resolution (1280x720)', () {
        expect(VideoUtils.pickBitrateKbps('1280x720'), 8000);
      });

      test('returns 5000 kbps for lower resolutions (640x480)', () {
        expect(VideoUtils.pickBitrateKbps('640x480'), 5000);
      });

      test('returns 12000 kbps default for invalid format', () {
        expect(VideoUtils.pickBitrateKbps('invalid'), 12000);
      });

      test('returns 12000 kbps default for empty string', () {
        expect(VideoUtils.pickBitrateKbps(''), 12000);
      });

      test('returns 12000 kbps default for unrecognized resolution string', () {
        expect(VideoUtils.pickBitrateKbps('720p'), 12000);
      });

      test('handles portrait orientation (1080x1920)', () {
        // 1080x1920 = 2,073,600 pixels, same as 1920x1080
        expect(VideoUtils.pickBitrateKbps('1080x1920'), 14000);
      });

      test('handles non-standard aspect ratios', () {
        // 2048x1536 = 3,145,728 pixels (below 1440p threshold of 3,686,400)
        // Falls into 1080p tier (>= 2,073,600)
        expect(VideoUtils.pickBitrateKbps('2048x1536'), 14000);
      });

      test('handles exact threshold boundaries', () {
        // Exactly 1920x1080 should give 1080p bitrate
        expect(VideoUtils.pickBitrateKbps('1920x1080'), 14000);
        // Just above 1080p (2,076,601 pixels) - still below 1440p threshold
        expect(VideoUtils.pickBitrateKbps('1921x1081'), 14000);
        // At 1440p threshold exactly
        expect(VideoUtils.pickBitrateKbps('2560x1440'), 20000);
      });
    });

    group('getWatermarkFilter', () {
      test('returns correct filter for lower left position', () {
        final filter = VideoUtils.getWatermarkFilter(0.8, 'lower left', 10);
        expect(filter, contains('colorchannelmixer=aa=0.8'));
        expect(filter, contains('10:main_h-overlay_h-10'));
      });

      test('returns correct filter for lower right position', () {
        final filter = VideoUtils.getWatermarkFilter(0.7, 'lower right', 15);
        expect(filter, contains('colorchannelmixer=aa=0.7'));
        expect(filter, contains('main_w-overlay_w-15:main_h-overlay_h-15'));
      });

      test('returns correct filter for upper left position', () {
        final filter = VideoUtils.getWatermarkFilter(1.0, 'upper left', 20);
        expect(filter, contains('colorchannelmixer=aa=1.0'));
        expect(filter, contains('20:20'));
      });

      test('returns correct filter for upper right position', () {
        final filter = VideoUtils.getWatermarkFilter(0.5, 'upper right', 5);
        expect(filter, contains('colorchannelmixer=aa=0.5'));
        expect(filter, contains('main_w-overlay_w-5:5'));
      });

      test('defaults to lower left for unknown position', () {
        final filter = VideoUtils.getWatermarkFilter(0.8, 'center', 10);
        expect(filter, contains('10:main_h-overlay_h-10'));
      });

      test('handles zero opacity', () {
        final filter = VideoUtils.getWatermarkFilter(0.0, 'lower left', 10);
        expect(filter, contains('colorchannelmixer=aa=0.0'));
      });

      test('handles zero offset', () {
        final filter = VideoUtils.getWatermarkFilter(0.8, 'lower left', 0);
        expect(filter, contains('0:main_h-overlay_h-0'));
      });

      test('filter structure is correct', () {
        final filter = VideoUtils.getWatermarkFilter(0.8, 'lower left', 10);
        expect(filter, startsWith('[1:v]format=rgba,colorchannelmixer=aa='));
        expect(filter, contains('[watermark];[0:v][watermark]overlay='));
      });
    });

    group('parseFFmpegOutput', () {
      test('parses frame number from ffmpeg output', () {
        int? capturedFrame;
        VideoUtils.parseFFmpegOutput(
          'frame=  100 fps=30 q=28.0 size=    256kB time=00:00:03.33',
          15,
          (frame) => capturedFrame = frame,
        );
        // frame=100, fps output is 30, source framerate is 15
        // currFrame = 100 ~/ (30 / 15) = 100 ~/ 2 = 50
        expect(capturedFrame, 50);
      });

      test('handles frame with no spaces', () {
        int? capturedFrame;
        VideoUtils.parseFFmpegOutput(
          'frame=50 fps=30.0',
          10,
          (frame) => capturedFrame = frame,
        );
        // currFrame = 50 ~/ (30 / 10) = 50 ~/ 3 = 16
        expect(capturedFrame, 16);
      });

      test('does nothing when callback is null', () {
        // Should not throw
        VideoUtils.parseFFmpegOutput(
          'frame=  100 fps=30',
          15,
          null,
        );
      });

      test('does nothing when no frame found in output', () {
        int? capturedFrame;
        VideoUtils.parseFFmpegOutput(
          'Duration: 00:00:10.00, start: 0.000000',
          15,
          (frame) => capturedFrame = frame,
        );
        expect(capturedFrame, isNull);
      });

      test('uses last frame match when multiple present', () {
        int? capturedFrame;
        VideoUtils.parseFFmpegOutput(
          'frame=  10 frame=  20 frame=  30',
          30,
          (frame) => capturedFrame = frame,
        );
        // currFrame = 30 ~/ (30 / 30) = 30 ~/ 1 = 30
        expect(capturedFrame, 30);
      });

      test('handles different framerate ratios', () {
        int? capturedFrame;

        // Test with framerate 30 (same as output)
        VideoUtils.parseFFmpegOutput(
          'frame=  60 fps=30',
          30,
          (frame) => capturedFrame = frame,
        );
        expect(capturedFrame, 60);

        // Test with framerate 6 (5x slower)
        VideoUtils.parseFFmpegOutput(
          'frame=  60 fps=30',
          6,
          (frame) => capturedFrame = frame,
        );
        // currFrame = 60 ~/ (30 / 6) = 60 ~/ 5 = 12
        expect(capturedFrame, 12);
      });
    });
  });
}
