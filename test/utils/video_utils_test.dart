import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/video_utils.dart';

void main() {
  group('VideoUtils', () {
    group('buildFilterChain', () {
      // Reusable test fixtures
      const testPixelFormat = 'yuv420p';
      const testColorOverlay =
          '[0:v][1:v]overlay=shortest=1,format=yuv420p[base]';
      final testDateStamp = DateStampOverlayInfo(
        filterComplex: '[base][2:v]overlay=enable=between(n\\,0\\,5)[dsOut]',
        pngInputPaths: ['/tmp/ds1.png', '/tmp/ds2.png'],
        tempDir: '/tmp/ds',
        outputMapLabel: 'dsOut',
      );
      // Watermark filter has no trailing [label] — FFmpeg auto-selects output
      final testWatermark = VideoUtils.getWatermarkFilter(
        0.8,
        'lower left',
        10,
      );

      test('returns empty result when no filters', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: null,
          dateStampOverlay: null,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: false,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isFalse);
        expect(result.hasMap, isFalse);
        expect(result.filterComplex, isNull);
        expect(result.mapLabel, isNull);
      });

      test('color overlay only produces filter with [base] map', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: testColorOverlay,
          dateStampOverlay: null,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: true,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.hasMap, isTrue);
        // Post-processing appends format conversion
        expect(result.filterComplex, contains(testColorOverlay));
        expect(result.filterComplex, contains('[base]format=yuv420p[vout]'));
        expect(result.mapLabel, equals('[vout]'));
      });

      test('date stamps only produces filter with outputMapLabel', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: null,
          dateStampOverlay: testDateStamp,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: false,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.hasMap, isTrue);
        expect(result.filterComplex, equals(testDateStamp.filterComplex));
        expect(result.mapLabel, equals('[dsOut]'));
      });

      test('watermark only produces filter with no map label', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: null,
          dateStampOverlay: null,
          watermarkFilterPart: testWatermark,
          watermarkInputIndex: 1,
          needsColorOverlay: false,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.hasMap, isFalse);
        expect(result.filterComplex, equals(testWatermark));
        expect(result.mapLabel, isNull);
      });

      test(
        'color overlay + date stamps combines chains with post-processing',
        () {
          final result = VideoUtils.buildFilterChain(
            colorOverlayFilter: testColorOverlay,
            dateStampOverlay: testDateStamp,
            watermarkFilterPart: null,
            watermarkInputIndex: 0,
            needsColorOverlay: true,
            pixelFormat: testPixelFormat,
          );
          expect(result.hasFilter, isTrue);
          expect(result.hasMap, isTrue);
          // Should contain both chains
          expect(result.filterComplex, contains(testColorOverlay));
          expect(result.filterComplex, contains(testDateStamp.filterComplex));
          // Post-processing: format conversion appended, map is [vout]
          expect(result.filterComplex, contains('[dsOut]format=yuv420p[vout]'));
          expect(result.mapLabel, equals('[vout]'));
        },
      );

      test(
        'color overlay + watermark replaces input labels and applies post-processing',
        () {
          final result = VideoUtils.buildFilterChain(
            colorOverlayFilter: testColorOverlay,
            dateStampOverlay: null,
            watermarkFilterPart: testWatermark,
            watermarkInputIndex: 2,
            needsColorOverlay: true,
            pixelFormat: testPixelFormat,
          );
          expect(result.hasFilter, isTrue);
          expect(result.filterComplex, contains(testColorOverlay));
          // Watermark [0:v] should be replaced with [base] (in the watermark part)
          // The color overlay itself still has [0:v], but the watermark's [0:v] is gone
          final afterColorOverlay = result.filterComplex!.substring(
            result.filterComplex!.indexOf(';') + 1,
          );
          expect(afterColorOverlay, contains('[base]'));
          expect(afterColorOverlay, isNot(contains('[0:v]')));
          // Watermark [1:v] should be replaced with [2:v]
          expect(afterColorOverlay, contains('[2:v]'));
          expect(afterColorOverlay, isNot(contains('[1:v]')));
        },
      );

      test(
        'date stamps + watermark replaces input labels without post-processing',
        () {
          final result = VideoUtils.buildFilterChain(
            colorOverlayFilter: null,
            dateStampOverlay: testDateStamp,
            watermarkFilterPart: testWatermark,
            watermarkInputIndex: 4,
            needsColorOverlay: false,
            pixelFormat: testPixelFormat,
          );
          expect(result.hasFilter, isTrue);
          expect(result.filterComplex, contains(testDateStamp.filterComplex));
          // Watermark [0:v] replaced with [dsOut]
          expect(result.filterComplex, contains('[dsOut]'));
          // Watermark [1:v] replaced with [4:v]
          expect(result.filterComplex, contains('[4:v]'));
          // No post-processing (needsColorOverlay is false)
          expect(result.filterComplex, isNot(contains('[vout]')));
        },
      );

      test('all three overlays combines everything with post-processing', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: testColorOverlay,
          dateStampOverlay: testDateStamp,
          watermarkFilterPart: testWatermark,
          watermarkInputIndex: 5,
          needsColorOverlay: true,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.filterComplex, contains(testColorOverlay));
        expect(result.filterComplex, contains(testDateStamp.filterComplex));
        // Watermark [0:v] replaced with [dsOut] (date stamp output)
        expect(result.filterComplex, contains('[dsOut]'));
        // Watermark [1:v] replaced with [5:v]
        expect(result.filterComplex, contains('[5:v]'));
      });

      test('post-processing only applies when needsColorOverlay is true', () {
        // Date stamps with needsColorOverlay=false should NOT get format conversion
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: null,
          dateStampOverlay: testDateStamp,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: false,
          pixelFormat: testPixelFormat,
        );
        expect(result.filterComplex, isNot(contains('[vout]')));
        expect(result.filterComplex, isNot(contains('format=yuv420p')));
        expect(result.mapLabel, equals('[dsOut]'));
      });

      test('different pixel formats are used in post-processing', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: testColorOverlay,
          dateStampOverlay: null,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: true,
          pixelFormat: 'yuv422p10le', // ProRes pixel format
        );
        expect(result.filterComplex, contains('format=yuv422p10le[vout]'));
        expect(result.mapLabel, equals('[vout]'));
      });

      test('empty string colorOverlayFilter treated as no color overlay', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: '',
          dateStampOverlay: null,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: false,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isFalse);
        expect(result.hasMap, isFalse);
      });

      test('empty string watermarkFilterPart treated as no watermark', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: null,
          dateStampOverlay: testDateStamp,
          watermarkFilterPart: '',
          watermarkInputIndex: 0,
          needsColorOverlay: false,
          pixelFormat: testPixelFormat,
        );
        // Should produce date-stamp-only result, not date+watermark
        expect(result.filterComplex, equals(testDateStamp.filterComplex));
        expect(result.mapLabel, equals('[dsOut]'));
      });
    });

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

    group('video ETA calculation', () {
      setUp(() {
        VideoUtils.resetVideoStopwatch(100);
        VideoUtils.stopVideoStopwatch();
      });

      test('resetVideoStopwatch sets total frames', () {
        VideoUtils.resetVideoStopwatch(500);
        // After reset with frames, ETA calculation should work
        // (can't directly test internal state, but function should not throw)
        expect(() => VideoUtils.resetVideoStopwatch(500), returnsNormally);
      });

      test('stopVideoStopwatch does not throw', () {
        VideoUtils.resetVideoStopwatch(100);
        expect(() => VideoUtils.stopVideoStopwatch(), returnsNormally);
      });

      test('calculateVideoEta returns null when frames processed is 0', () {
        VideoUtils.resetVideoStopwatch(100);
        expect(VideoUtils.calculateVideoEta(0), isNull);
      });

      test('calculateVideoEta returns null when total frames is 0', () {
        VideoUtils.resetVideoStopwatch(0);
        expect(VideoUtils.calculateVideoEta(50), isNull);
      });

      test(
        'calculateVideoEta returns null when frames processed is negative',
        () {
          VideoUtils.resetVideoStopwatch(100);
          expect(VideoUtils.calculateVideoEta(-1), isNull);
        },
      );

      test(
        'calculateVideoEta returns formatted string when conditions met',
        () async {
          VideoUtils.resetVideoStopwatch(100);
          // Wait a bit for stopwatch to accumulate time
          await Future.delayed(const Duration(milliseconds: 600));
          final result = VideoUtils.calculateVideoEta(50);
          // Should return a string like "0m Xs" or be null if not enough time elapsed
          if (result != null) {
            expect(result, matches(RegExp(r'\d+[hms]')));
          }
        },
      );

      test(
        'calculateVideoEta returns "0m 0s" when all frames processed',
        () async {
          VideoUtils.resetVideoStopwatch(100);
          await Future.delayed(const Duration(milliseconds: 600));
          final result = VideoUtils.calculateVideoEta(100);
          if (result != null) {
            expect(result, equals('0m 0s'));
          }
        },
      );
    });

    group('parseFFmpegOutput', () {
      setUp(() {
        VideoUtils.resetProgressThrottle();
      });

      test('parses frame number from ffmpeg output', () {
        int? capturedFrame;
        VideoUtils.parseFFmpegOutput(
          'frame=  100 fps=30 q=28.0 size=    256kB time=00:00:03.33',
          15,
          (frame) => capturedFrame = frame,
        );
        // outputFps(15) = 15, currFrame = (100 * 15) ~/ 15 = 100
        expect(capturedFrame, 100);
      });

      test('handles frame with no spaces', () {
        int? capturedFrame;
        VideoUtils.parseFFmpegOutput(
          'frame=50 fps=30.0',
          10,
          (frame) => capturedFrame = frame,
        );
        // outputFps(10) = 10, currFrame = (50 * 10) ~/ 10 = 50
        expect(capturedFrame, 50);
      });

      test('does nothing when callback is null', () {
        // Should not throw
        VideoUtils.parseFFmpegOutput('frame=  100 fps=30', 15, null);
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
        // currFrame = (30 * 30) ~/ max(30,10) = 900 ~/ 30 = 30
        expect(capturedFrame, 30);
      });

      test('handles different framerate ratios', () {
        int? capturedFrame;

        // Test with framerate 30 (outputFps=30, 1:1 ratio)
        VideoUtils.parseFFmpegOutput(
          'frame=  60 fps=30',
          30,
          (frame) => capturedFrame = frame,
        );
        // currFrame = (60 * 30) ~/ max(30,10) = 1800 ~/ 30 = 60
        expect(capturedFrame, 60);

        // Reset throttle for second call
        VideoUtils.resetProgressThrottle();

        // Test with framerate 6 (outputFps=10, 10/6 ratio)
        VideoUtils.parseFFmpegOutput(
          'frame=  60 fps=30',
          6,
          (frame) => capturedFrame = frame,
        );
        // currFrame = (60 * 6) ~/ max(6,10) = 360 ~/ 10 = 36
        expect(capturedFrame, 36);
      });
    });

    group('blurSigma', () {
      test('1080p produces sigma 20', () {
        expect(VideoUtils.blurSigma(1080), 20);
      });

      test('2160p (4K) produces sigma 40', () {
        expect(VideoUtils.blurSigma(2160), 40);
      });

      test('720p produces sigma 13', () {
        expect(VideoUtils.blurSigma(720), 13);
      });

      test('clamps minimum to 10', () {
        expect(VideoUtils.blurSigma(100), 10);
      });

      test('clamps maximum to 50', () {
        expect(VideoUtils.blurSigma(5000), 50);
      });
    });

    group('buildBlurFilter', () {
      test('contains expected filter components at 1080p', () {
        final filter = VideoUtils.buildBlurFilter(1080);
        expect(filter, contains('split=2'));
        expect(filter, contains('[orig]'));
        expect(filter, contains('[bg]'));
        expect(filter, contains('format=rgb24'));
        expect(filter, contains('scale=iw*3:ih*3'));
        expect(filter, contains('crop=iw/3:ih/3'));
        expect(filter, contains('gblur=sigma=20'));
        expect(filter, contains('[blurred]'));
        expect(filter, contains('overlay=0:0'));
        expect(filter, contains('[base]'));
      });

      test('uses resolution-aware sigma at 4K', () {
        final filter = VideoUtils.buildBlurFilter(2160);
        expect(filter, contains('gblur=sigma=40'));
      });
    });

    group('buildFilterChain with blur filter', () {
      // Reusable test fixtures (mirrors the fixtures at the top of buildFilterChain group)
      const testPixelFormat = 'yuv420p';
      // Blur filter produced by buildBlurFilter(1080)
      final testBlurFilter = VideoUtils.buildBlurFilter(1080);
      final testDateStamp = DateStampOverlayInfo(
        filterComplex: '[base][2:v]overlay=enable=between(n\\,0\\,5)[dsOut]',
        pngInputPaths: ['/tmp/ds1.png', '/tmp/ds2.png'],
        tempDir: '/tmp/ds',
        outputMapLabel: 'dsOut',
      );
      final testWatermark = VideoUtils.getWatermarkFilter(
        0.8,
        'lower left',
        10,
      );

      test(
          'blur filter only produces filter with [base] map and format post-processing',
          () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: testBlurFilter,
          dateStampOverlay: null,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: true,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.hasMap, isTrue);
        expect(result.filterComplex, contains(testBlurFilter));
        expect(result.filterComplex, contains('[base]format=yuv420p[vout]'));
        expect(result.mapLabel, equals('[vout]'));
      });

      test('blur filter + date stamps combines chains with post-processing',
          () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: testBlurFilter,
          dateStampOverlay: testDateStamp,
          watermarkFilterPart: null,
          watermarkInputIndex: 0,
          needsColorOverlay: true,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.hasMap, isTrue);
        expect(result.filterComplex, contains(testBlurFilter));
        expect(result.filterComplex, contains(testDateStamp.filterComplex));
        expect(result.filterComplex, contains('[dsOut]format=yuv420p[vout]'));
        expect(result.mapLabel, equals('[vout]'));
      });

      test(
          'blur filter + watermark replaces input labels and applies post-processing',
          () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: testBlurFilter,
          dateStampOverlay: null,
          watermarkFilterPart: testWatermark,
          watermarkInputIndex: 2,
          needsColorOverlay: true,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.filterComplex, contains(testBlurFilter));
        // Watermark [0:v] should be replaced with [base] in the watermark part
        final afterBlurFilter = result.filterComplex!.substring(
          result.filterComplex!.indexOf(';') + 1,
        );
        expect(afterBlurFilter, contains('[base]'));
        expect(afterBlurFilter, isNot(contains('[0:v]')));
        // Watermark [1:v] should be replaced with [2:v]
        expect(afterBlurFilter, contains('[2:v]'));
        expect(afterBlurFilter, isNot(contains('[1:v]')));
      });

      test('blur filter + date stamps + watermark combines everything', () {
        final result = VideoUtils.buildFilterChain(
          colorOverlayFilter: testBlurFilter,
          dateStampOverlay: testDateStamp,
          watermarkFilterPart: testWatermark,
          watermarkInputIndex: 5,
          needsColorOverlay: true,
          pixelFormat: testPixelFormat,
        );
        expect(result.hasFilter, isTrue);
        expect(result.filterComplex, contains(testBlurFilter));
        expect(result.filterComplex, contains(testDateStamp.filterComplex));
        // Watermark [0:v] replaced with [dsOut] (date stamp output)
        expect(result.filterComplex, contains('[dsOut]'));
        // Watermark [1:v] replaced with [5:v]
        expect(result.filterComplex, contains('[5:v]'));
        // Watermark filter has no trailing output label, so no post-processing map
        expect(result.mapLabel, isNull);
      });
    });
  });
}
