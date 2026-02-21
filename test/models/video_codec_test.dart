import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/video_codec.dart';

void main() {
  group('VideoCodec', () {
    group('fromString', () {
      test('parses h264', () {
        expect(VideoCodec.fromString('h264'), VideoCodec.h264);
      });

      test('parses hevc', () {
        expect(VideoCodec.fromString('hevc'), VideoCodec.hevc);
      });

      test('parses prores422', () {
        expect(VideoCodec.fromString('prores422'), VideoCodec.prores422);
      });

      test('parses prores422hq', () {
        expect(VideoCodec.fromString('prores422hq'), VideoCodec.prores422hq);
      });

      test('parses prores4444', () {
        expect(VideoCodec.fromString('prores4444'), VideoCodec.prores4444);
      });

      test('parses vp9', () {
        expect(VideoCodec.fromString('vp9'), VideoCodec.vp9);
      });

      test('defaults to h264 for invalid string', () {
        expect(VideoCodec.fromString('invalid'), VideoCodec.h264);
      });

      test('defaults to h264 for empty string', () {
        expect(VideoCodec.fromString(''), VideoCodec.h264);
      });

      test('is case-insensitive', () {
        expect(VideoCodec.fromString('H264'), VideoCodec.h264);
        expect(VideoCodec.fromString('HEVC'), VideoCodec.hevc);
        expect(VideoCodec.fromString('ProRes422'), VideoCodec.prores422);
        expect(VideoCodec.fromString('VP9'), VideoCodec.vp9);
      });

      test('round-trips through name property', () {
        for (final codec in VideoCodec.values) {
          expect(VideoCodec.fromString(codec.name), codec);
        }
      });
    });

    group('displayName', () {
      test('h264 displays as H.264', () {
        expect(VideoCodec.h264.displayName, 'H.264');
      });

      test('hevc displays as HEVC (H.265)', () {
        expect(VideoCodec.hevc.displayName, 'HEVC (H.265)');
      });

      test('prores422 displays as ProRes 422', () {
        expect(VideoCodec.prores422.displayName, 'ProRes 422');
      });

      test('prores422hq displays as ProRes 422 HQ', () {
        expect(VideoCodec.prores422hq.displayName, 'ProRes 422 HQ');
      });

      test('prores4444 displays as ProRes 4444', () {
        expect(VideoCodec.prores4444.displayName, 'ProRes 4444');
      });

      test('vp9 displays as VP9', () {
        expect(VideoCodec.vp9.displayName, 'VP9');
      });

      test('all codecs have non-empty display names', () {
        for (final codec in VideoCodec.values) {
          expect(codec.displayName, isNotEmpty);
        }
      });
    });

    group('description', () {
      test('all codecs have non-empty descriptions', () {
        for (final codec in VideoCodec.values) {
          expect(codec.description, isNotEmpty);
        }
      });
    });

    group('containerExtension', () {
      test('h264 uses .mp4', () {
        expect(VideoCodec.h264.containerExtension, '.mp4');
      });

      test('hevc uses .mp4', () {
        expect(VideoCodec.hevc.containerExtension, '.mp4');
      });

      test('prores422 uses .mov', () {
        expect(VideoCodec.prores422.containerExtension, '.mov');
      });

      test('prores422hq uses .mov', () {
        expect(VideoCodec.prores422hq.containerExtension, '.mov');
      });

      test('prores4444 uses .mov', () {
        expect(VideoCodec.prores4444.containerExtension, '.mov');
      });

      test('vp9 uses .webm', () {
        expect(VideoCodec.vp9.containerExtension, '.webm');
      });

      test('all extensions start with a dot', () {
        for (final codec in VideoCodec.values) {
          expect(codec.containerExtension, startsWith('.'));
        }
      });
    });

    group('pixelFormat', () {
      test('h264 uses yuv420p', () {
        expect(VideoCodec.h264.pixelFormat, 'yuv420p');
      });

      test('hevc uses yuv420p', () {
        expect(VideoCodec.hevc.pixelFormat, 'yuv420p');
      });

      test('prores422 uses yuv422p10le', () {
        expect(VideoCodec.prores422.pixelFormat, 'yuv422p10le');
      });

      test('prores422hq uses yuv422p10le', () {
        expect(VideoCodec.prores422hq.pixelFormat, 'yuv422p10le');
      });

      test('prores4444 uses yuva444p10le', () {
        expect(VideoCodec.prores4444.pixelFormat, 'yuva444p10le');
      });

      test('vp9 uses yuva420p', () {
        expect(VideoCodec.vp9.pixelFormat, 'yuva420p');
      });

      test('all pixel formats are non-empty', () {
        for (final codec in VideoCodec.values) {
          expect(codec.pixelFormat, isNotEmpty);
        }
      });
    });

    group('supportsAlpha', () {
      test('only prores4444 and vp9 support alpha', () {
        expect(VideoCodec.h264.supportsAlpha, false);
        expect(VideoCodec.hevc.supportsAlpha, false);
        expect(VideoCodec.prores422.supportsAlpha, false);
        expect(VideoCodec.prores422hq.supportsAlpha, false);
        expect(VideoCodec.prores4444.supportsAlpha, true);
        expect(VideoCodec.vp9.supportsAlpha, true);
      });
    });

    group('usesBitrateControl', () {
      test('h264 uses bitrate control', () {
        expect(VideoCodec.h264.usesBitrateControl, true);
      });

      test('hevc uses bitrate control', () {
        expect(VideoCodec.hevc.usesBitrateControl, true);
      });

      test('vp9 uses bitrate control', () {
        expect(VideoCodec.vp9.usesBitrateControl, true);
      });

      test('prores variants do not use bitrate control', () {
        expect(VideoCodec.prores422.usesBitrateControl, false);
        expect(VideoCodec.prores422hq.usesBitrateControl, false);
        expect(VideoCodec.prores4444.usesBitrateControl, false);
      });
    });

    group('usesMovFlags', () {
      test('only h264 and hevc use movflags', () {
        expect(VideoCodec.h264.usesMovFlags, true);
        expect(VideoCodec.hevc.usesMovFlags, true);
        expect(VideoCodec.prores422.usesMovFlags, false);
        expect(VideoCodec.prores422hq.usesMovFlags, false);
        expect(VideoCodec.prores4444.usesMovFlags, false);
        expect(VideoCodec.vp9.usesMovFlags, false);
      });
    });

    group('encoder (platform-specific)', () {
      // These tests verify the encoder strings contain expected substrings
      // without depending on the specific platform the test runs on.

      test('encoderApple returns videotoolbox for h264', () {
        expect(VideoCodec.h264.encoderApple, 'h264_videotoolbox');
      });

      test('encoderApple returns videotoolbox for hevc with sw fallback', () {
        expect(VideoCodec.hevc.encoderApple, contains('hevc_videotoolbox'));
        expect(VideoCodec.hevc.encoderApple, contains('-allow_sw 1'));
      });

      test('encoderApple returns prores_ks for prores variants', () {
        expect(VideoCodec.prores422.encoderApple, contains('prores_ks'));
        expect(VideoCodec.prores422.encoderApple, contains('standard'));
        expect(VideoCodec.prores422hq.encoderApple, contains('prores_ks'));
        expect(VideoCodec.prores422hq.encoderApple, contains('hq'));
      });

      test('encoderApple returns prores_ks 4444 with alpha for prores4444', () {
        expect(VideoCodec.prores4444.encoderApple, contains('prores_ks'));
        expect(VideoCodec.prores4444.encoderApple, contains('4444'));
        expect(VideoCodec.prores4444.encoderApple, contains('-alpha_bits 16'));
        expect(VideoCodec.prores4444.encoderApple, contains('-vendor apl0'));
      });

      test('encoderDesktop returns libx264 for h264', () {
        expect(VideoCodec.h264.encoderDesktop, 'libx264');
      });

      test('encoderDesktop returns libx265 for hevc', () {
        expect(VideoCodec.hevc.encoderDesktop, 'libx265');
      });

      test('encoderDesktop returns prores_ks for prores 422 variants', () {
        expect(VideoCodec.prores422.encoderDesktop, contains('prores_ks'));
        expect(VideoCodec.prores422hq.encoderDesktop, contains('prores_ks'));
      });

      test('encoderDesktop falls back to vp9 for prores4444', () {
        expect(VideoCodec.prores4444.encoderDesktop, 'libvpx-vp9');
      });

      test('encoderAndroid matches encoderDesktop except hevc', () {
        for (final codec in VideoCodec.values) {
          if (codec == VideoCodec.hevc) continue;
          expect(codec.encoderAndroid, codec.encoderDesktop);
        }
      });

      test('encoderAndroid for hevc includes profile flag', () {
        expect(VideoCodec.hevc.encoderAndroid, 'libx265 -profile:v main');
      });

      test('all encoders are non-empty', () {
        for (final codec in VideoCodec.values) {
          expect(codec.encoderApple, isNotEmpty);
          expect(codec.encoderDesktop, isNotEmpty);
          expect(codec.encoderAndroid, isNotEmpty);
        }
      });
    });

    group('codecTag', () {
      // codecTag is platform-dependent, so test the known values
      test('non-h264/hevc codecs have empty tag', () {
        expect(VideoCodec.prores422.codecTag, '');
        expect(VideoCodec.prores422hq.codecTag, '');
        expect(VideoCodec.prores4444.codecTag, '');
        expect(VideoCodec.vp9.codecTag, '');
      });
    });

    group('availableCodecs', () {
      test('opaque returns h264, hevc, prores422, prores422hq, prores4444', () {
        final codecs = VideoCodec.availableCodecs(isTransparentVideo: false);
        expect(codecs, [
          VideoCodec.h264,
          VideoCodec.hevc,
          VideoCodec.prores422,
          VideoCodec.prores422hq,
          VideoCodec.prores4444,
        ]);
      });

      test('transparent returns only alpha-capable codecs', () {
        final codecs = VideoCodec.availableCodecs(isTransparentVideo: true);
        expect(codecs.length, 1);
        for (final c in codecs) {
          expect(c.supportsAlpha, true);
        }
      });

      test('transparent codecs are platform-specific', () {
        final codecs = VideoCodec.availableCodecs(isTransparentVideo: true);
        // On macOS test runner, should be [prores4444]
        // On Linux CI, should be [vp9]
        expect(codecs.first.supportsAlpha, true);
      });
    });

    group('defaultCodec', () {
      test('opaque default is h264', () {
        expect(
          VideoCodec.defaultCodec(isTransparentVideo: false),
          VideoCodec.h264,
        );
      });

      test('transparent default is alpha-capable', () {
        final codec = VideoCodec.defaultCodec(isTransparentVideo: true);
        expect(codec.supportsAlpha, true);
      });
    });
  });
}
